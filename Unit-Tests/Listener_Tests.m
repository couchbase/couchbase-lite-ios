//
//  Listener_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 7/8/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLManager+Internal.h"
#import "CBLSyncListener.h"
#import "CBLHTTPListener.h"
#import "CBLRemoteRequest.h"
#import "CBLRemoteSession.h"
#import "CBLClientCertAuthorizer.h"
#import "BLIP.h"
#import "MYAnonymousIdentity.h"

#import <arpa/inet.h>


#define kTimeout 5.0


@interface Listener_Tests : CBLTestCaseWithDB <CBLListenerDelegate, BLIPConnectionDelegate>
@end


static UInt16 sPort = 60000;


@implementation Listener_Tests
{
    @protected
    CBLListener* listener;
    NSURLCredential* clientCredential;
    XCTestExpectation *_expectValidateServerTrust, *_expectDidOpen, *_expectDidClose;
    XCTestExpectation *_expectAuthenticateTrust;
}

- (Class) listenerClass {
    return [CBLSyncListener class];
}

- (void)setUp {
    [super setUp];
    dbmgr.dispatchQueue = dispatch_get_main_queue();
    dbmgr.replicatorClassName = @"CBLBlipReplicator";

    // Each test run uses a different port number (sPort is incremented) to prevent CFNetwork from
    // resuming the previous SSL session. Because if it does that, the previous client cert gets
    // used on the server side, which breaks the test. Haven't found a workaround for this yet.
    // --Jens 7/2015
    listener = [[[self listenerClass] alloc] initWithManager: dbmgr port: sPort];
    listener.delegate = self;
    // Need to register a Bonjour service, otherwise on an iOS device the listener's URL doesn't
    // work because the .local hostname hasn't been registered over mDNS.
    [listener setBonjourName: @"CBL Unit Tests" type: @"_cblunittests._tcp"];

    if (self.iOSVersion >= 9)
        [self enableSSL];
}

- (void)tearDown {
    listener.delegate = nil;
    [listener stop];
    ++sPort;
    [super tearDown];
}


- (void) enableSSL {
    if (!listener.SSLIdentity) {
        NSError* error;
        Assert([listener setAnonymousSSLIdentityWithLabel: @"CBLUnitTests" error: &error],
               @"Failed to set SSL identity: %@", error);
    }
}

- (void) startListener {
    if (listener.port == 0) {
        [self keyValueObservingExpectationForObject: listener
                                            keyPath: @"port"
                                      expectedValue: @(sPort)];
        [listener start: NULL];
        [self waitForExpectationsWithTimeout: kTimeout handler: nil];
    }
}


- (void)test01_SSL_NoClientCert {
    if (!self.isSQLiteDB)
        return;
    [self enableSSL];
    [self startListener];
    _expectAuthenticateTrust = [self expectationWithDescription: @"authenticateWithTrust"];
    [self connect];
}


- (void)test02_SSL_ClientCert {
    if (!self.isSQLiteDB)
        return;
    [self enableSSL];
    [self startListener];

    NSError* error;
    SecIdentityRef identity = MYGetOrCreateAnonymousIdentity(@"CBLUnitTests-Client",
                                                     kMYAnonymousIdentityDefaultExpirationInterval,
                                                     &error);
    Assert(identity, @"Couldn't create client identity: %@", error);
    clientCredential = [NSURLCredential credentialWithIdentity: identity certificates: nil
                                                   persistence: NSURLCredentialPersistenceNone];

    _expectAuthenticateTrust = [self expectationWithDescription: @"authenticateWithTrust"];
    [self connect];
}

- (void)test03_ReadOnly {
    if (!self.isSQLiteDB || ![listener isKindOfClass: [CBLSyncListener class]])
        return;

    // Enable readOnly mode:
    listener.readOnly = YES;

    [self startListener];

    NSURL* url = self.listenerSyncURL;
    Log(@"Connecting to <%@>", url);
    BLIPPocketSocketConnection* conn = [[BLIPPocketSocketConnection alloc] initWithURL: url];
    [conn setDelegate: self queue: dispatch_get_main_queue()];

    NSError* error;
    Assert([conn connect: &error], @"Can't connect: %@", error);
    _expectDidOpen = [self expectationWithDescription: @"didOpen"];
    [self waitForExpectationsWithTimeout: kTimeout handler: nil];

    // getCheckpoint:
    BLIPRequest* request = [conn request];
    request.profile = @"getCheckpoint";
    request[@"client"] = @"TestReadOnly";
    [self sendRequest: request expectedErrorCode: 0 expectedResult: nil];

    // setCheckpoint:
    request = [conn request];
    request.profile = @"setCheckpoint";
    request[@"client"] = @"TestReadOnly";
    request[@"rev"] = @"1-000";
    request.bodyJSON = $dict({@"lastSequence", @(1)});
    [self sendRequest: request expectedErrorCode: 0 expectedResult: nil];

    // subChanges:
    request = [conn request];
    request.profile = @"subChanges";
    [self sendRequest: request expectedErrorCode: 0 expectedResult: nil];

    // changes:
    request = [conn request];
    request.profile = @"changes";
    request.bodyJSON = @[@[@(1), @"doc1", @"1-001"]];
    [self sendRequest: request expectedErrorCode: 403 expectedResult: nil];

    // rev:
    request = [conn request];
    request.profile = @"rev";
    request[@"history"] = @"1-001";
    request.bodyJSON = @{@"_id": @"doc1", @"_rev": @"1-001"};
    [self sendRequest: request expectedErrorCode: 403 expectedResult: nil];

    // getAttachment:
    CBLUnsavedRevision* newRev =[[db createDocument] newRevision];
    NSData* body = [@"This is an attachment." dataUsingEncoding: NSUTF8StringEncoding];
    [newRev setAttachmentNamed: @"attach" withContentType: @"text/plain" content: body];
    CBLAttachment* att = [[newRev save: nil] attachmentNamed: @"attach"];
    Assert(att);

    request = [conn request];
    request.profile = @"getAttachment";
    request[@"digest"] = att.metadata[@"digest"];
    [self sendRequest: request expectedErrorCode: 0 expectedResult: nil];

    // proveAttachment:
    request = [conn request];
    request.profile = @"proveAttachment";
    request[@"digest"] = att.metadata[@"digest"];
    uint8_t nonceBytes[16];
    (void)SecRandomCopyBytes(kSecRandomDefault, sizeof(nonceBytes), nonceBytes);
    NSData* nonceData = [NSData dataWithBytes: nonceBytes length: sizeof(nonceBytes)];
    request.body = nonceData;
    [self sendRequest: request expectedErrorCode: 0 expectedResult: nil];

    _expectDidClose = [self expectationWithDescription: @"didClose"];
    [conn close];
    [self waitForExpectationsWithTimeout: kTimeout handler: nil];
}


#pragma mark - Test Utilities

- (NSURL*) listenerSyncURL {
    NSURL* url = [[listener.URL URLByAppendingPathComponent: db.name]
                                    URLByAppendingPathComponent: @"_blipsync"];
#if TARGET_OS_IPHONE && TARGET_OS_SIMULATOR
    // Simulator has trouble with Bonjour URLs sometimes -- symptom is that both client and
    // listener simultaneously get a connection refused/aborted (-61 or -9806) error.
    NSURLComponents* comp = [[NSURLComponents alloc] initWithURL: url resolvingAgainstBaseURL: NO];
    comp.host = @"localhost";
    url = comp.URL;
#endif
    return url;
}

- (void) connect {
    NSURL* url = self.listenerSyncURL;
    BLIPPocketSocketConnection* conn = [[BLIPPocketSocketConnection alloc] initWithURL: url];
    [conn setDelegate: self queue: dispatch_get_main_queue()];
    conn.credential = clientCredential;

    NSError* error;
    Assert([conn connect: &error], @"Can't connect: %@", error);

    _expectValidateServerTrust = [self expectationWithDescription: @"validateServerTrust"];
    _expectDidOpen = [self expectationWithDescription: @"didOpen"];
    [self waitForExpectationsWithTimeout: kTimeout handler: nil];

    _expectDidClose = [self expectationWithDescription: @"didClose"];
    [conn close];
    [self waitForExpectationsWithTimeout: kTimeout handler: nil];
}

- (void)sendRequest: (BLIPRequest*)request
  expectedErrorCode: (NSInteger)expectedErrorCode
     expectedResult: (id)expectedResult
{
    XCTestExpectation* expectDidComplete = [self expectationWithDescription: @"didComplete"];
    [request send].onComplete = ^(BLIPResponse* response) {
        Assert(response);
        AssertEq(response.error.code, expectedErrorCode);
        if (expectedResult)
            AssertEqual(response.bodyJSON, expectedResult);
        [expectDidComplete fulfill];
    };
    [self waitForExpectationsWithTimeout: kTimeout handler: nil];
}


#pragma mark - CBLListenerDelegate


static NSString* addressToString(NSData* addrData) {
    if (!addrData)
        return nil;
    const struct sockaddr_in *addr = addrData.bytes;
    // Format it in readable (e.g. dotted-quad) form, with the port number:
    char nameBuf[INET6_ADDRSTRLEN];
    if (inet_ntop(addr->sin_family, &addr->sin_addr, nameBuf, (socklen_t)sizeof(nameBuf)) == NULL)
        return nil;
    return [NSString stringWithFormat: @"%s:%hu", nameBuf, ntohs(addr->sin_port)];
}


- (NSString*) authenticateConnectionFromAddress: (NSData*)address
                                      withTrust: (SecTrustRef)trust
{
    Log(@"authenticateConnectionFromAddress: %@ withTrust: %@",
        addressToString(address), trust);
    [_expectAuthenticateTrust fulfill];
    Assert(address != nil);
    if (clientCredential) {
        Assert(trust != nil);
        SecCertificateRef clientCert = SecTrustGetCertificateAtIndex(trust, 0);
        SecCertificateRef realClientCert;
        SecIdentityCopyCertificate(clientCredential.identity, &realClientCert);
        Assert(CFEqual(clientCert, realClientCert));
        CFRelease(realClientCert);
        return @"userWithClientCert";
    } else {
        AssertEq(trust, NULL);
        return @"";
    }
}


#pragma mark - BLIPConnectionDelegate

- (BOOL)blipConnection: (BLIPConnection*)connection
        validateServerTrust: (SecTrustRef)trust
{
    Log(@"validateServerTrust: %@", trust);
    [_expectValidateServerTrust fulfill];
    return YES;
}

- (void)blipConnectionDidOpen:(BLIPConnection*)connection {
    Log(@"didOpen");
    [_expectDidOpen fulfill];
}

- (void)blipConnection: (BLIPConnection*)connection
        didFailWithError: (NSError*)error
{
    XCTAssert(NO, @"Connection failed to open: %@", error);
}

- (void)blipConnection: (BLIPConnection*)connection
        didCloseWithError: (NSError*)error
{
    Log(@"didClose");
    XCTAssertNil(error, @"Unexpected error closing");
    XCTAssertNotNil(_expectDidClose);
    [_expectDidClose fulfill];
}


@end


@interface ListenerTestRemoteRequest : CBLRemoteRequest {
@private
    NSMutableData* _data;
}
- (void) setValue:(NSString*)value forHTTPHeaderField:(NSString *)header;
@property (readonly) NSData* data;
@property (readonly) int status;
@end


@interface ListenerHTTP_Tests : Listener_Tests <CBLRemoteRequestDelegate>
@end


@implementation ListenerHTTP_Tests
{
    CBLRemoteSession* _session;
    XCTestExpectation* _expectCheckServerTrust;
}

- (void) setUp {
    [super setUp];
    _session = [[CBLRemoteSession alloc] initWithDelegate: self];
}

- (Class) listenerClass {
    return [CBLHTTPListener class];
}

// Have to override these so Xcode will recognize that these tests exist in this class:
// Have to override these so Xcode will recognize that these tests exist in this class:
- (void)test01_SSL_NoClientCert    {[super test01_SSL_NoClientCert];}
- (void)test02_SSL_ClientCert      {[super test02_SSL_ClientCert];}

- (void)test03_ReadOnly {
    if (!self.isSQLiteDB)
        return;

    // Enable readOnly mode:
    listener.readOnly = YES;
    [self startListener];

    NSString* dbPath = [NSString stringWithFormat:@"%@/", db.name];

    [self sendRequest: @"PUT" path: [dbPath stringByAppendingString: @"doc1"]
              headers: nil body: @{} expectedStatus: 403
      expectedHeaders: nil expectedResult: nil];

    [self sendRequest: @"PUT" path: [dbPath stringByAppendingString: @"_local/remotecheckpointdocid"]
              headers: nil body: @{@"lastSequence": @"1"} expectedStatus: 201
      expectedHeaders: nil expectedResult: nil];

    Assert([[db documentWithID: @"doc2"] putProperties: @{} error: nil]);
    [self sendRequest: @"GET" path: [dbPath stringByAppendingString: @"doc2"]
              headers: nil body: nil expectedStatus: 200
      expectedHeaders: nil expectedResult: nil];
}

- (void)test04_GetRange {
    [self startListener];

    // Create a document with an attachment:
    CBLDocument* doc = [db createDocument];
    CBLUnsavedRevision* newRev = [doc newRevision];
    NSData* attach = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    [newRev setAttachmentNamed: @"attach" withContentType: @"text/plain" content: attach];
    Assert([newRev save: nil]);

    // URL to the attachment:
    NSString* path = [NSString stringWithFormat:@"%@/%@/attach", db.name, doc.documentID];

    [self sendRequest: @"GET" path: path headers: @{@"Range": @"bytes=5-15"} body: nil
       expectedStatus: 206 expectedHeaders: @{@"Content-Range": @"bytes 5-15/27"}
       expectedResult: [@"is the body" dataUsingEncoding: NSUTF8StringEncoding]];

    [self sendRequest: @"GET" path: path headers: @{@"Range": @"bytes=12-"} body: nil
       expectedStatus: 206 expectedHeaders: @{@"Content-Range": @"bytes 12-26/27"}
       expectedResult: [@"body of attach1" dataUsingEncoding: NSUTF8StringEncoding]];

    [self sendRequest: @"GET" path: path headers: @{@"Range": @"bytes=12-100"} body: nil
       expectedStatus: 206 expectedHeaders: @{@"Content-Range": @"bytes 12-26/27"}
       expectedResult: [@"body of attach1" dataUsingEncoding: NSUTF8StringEncoding]];

    [self sendRequest: @"GET" path: path headers: @{@"Range": @"bytes=-7"} body: nil
       expectedStatus: 206 expectedHeaders: @{@"Content-Range": @"bytes 20-26/27"}
       expectedResult: [@"attach1" dataUsingEncoding: NSUTF8StringEncoding]];

    [self sendRequest: @"GET" path: path headers: @{@"Range": @"bytes=5-3"} body: nil
       expectedStatus: 200 expectedHeaders: nil
       expectedResult: [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding]];

    [self sendRequest: @"GET" path: path headers: @{@"Range": @"bytes=100-"} body: nil
       expectedStatus: 416 expectedHeaders: @{@"Content-Range": @"bytes */27"}
       expectedResult: nil];

    [self sendRequest: @"GET" path: path headers: @{@"Range": @"bytes=-100"} body: nil
       expectedStatus: 200 expectedHeaders: nil
       expectedResult: [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding]];

    [self sendRequest: @"GET" path: path headers: @{@"Range": @"bytes=500-100"} body: nil
       expectedStatus: 200 expectedHeaders: nil
       expectedResult: [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding]];

    [self sendRequest: @"GET" path: path headers: @{@"Range": @"bytes=0-27"} body: nil
       expectedStatus: 200 expectedHeaders: nil
       expectedResult: [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding]];

    [self sendRequest: @"GET" path: path headers: @{@"Range": @"bytes=27-28"} body: nil
       expectedStatus: 416 expectedHeaders: @{@"Content-Range": @"bytes */27"}
       expectedResult: nil];
}


- (void) connect {
    Log(@"Connecting to <%@>", listener.URL);
    XCTestExpectation* expectDidComplete = [self expectationWithDescription: @"didComplete"];
    CBLRemoteRequest* req = [[CBLRemoteJSONRequest alloc] initWithMethod: @"GET" URL: listener.URL body: nil onCompletion:^(id result, NSError *error) {
        AssertNil(error);
        Assert(result != nil);
        [expectDidComplete fulfill];
    }];

    if (clientCredential) {
        req.authorizer = [[CBLClientCertAuthorizer alloc] initWithIdentity: clientCredential.identity supportingCerts: clientCredential.certificates];
    }

    _expectCheckServerTrust = [self expectationWithDescription: @"checkServerTrust"];

    [_session startRequest: req];
    [self waitForExpectationsWithTimeout: kTimeout handler: nil];
}


- (BOOL) checkSSLServerTrust: (NSURLProtectionSpace*)protectionSpace {
    Log(@"checkSSLServerTrust called!");
    [_expectCheckServerTrust fulfill];
    // Verify that the cert is the same one I told the listener to use:
    SecCertificateRef cert = SecTrustGetCertificateAtIndex(protectionSpace.serverTrust, 0);
    SecCertificateRef realServerCert;
    SecIdentityCopyCertificate(listener.SSLIdentity, &realServerCert);
    Assert(CFEqual(cert, realServerCert));
    CFRelease(realServerCert);
    Assert(CBLForceTrusted(protectionSpace.serverTrust));
    return YES;
}


- (void) remoteRequestReceivedResponse:(CBLRemoteRequest *)request {
}


- (void) sendRequest: (NSString*)method
                path: (NSString*)path
             headers: (NSDictionary*)headers
                body: (id)bodyObj
      expectedStatus: (NSInteger)expectedStatus
     expectedHeaders: (NSDictionary*)expectedHeader
      expectedResult: (NSData*)expectedResult {
    XCTestExpectation* expectDidComplete = [self expectationWithDescription: @"didComplete"];
    NSURL* url = [NSURL URLWithString: path relativeToURL: listener.URL];
    ListenerTestRemoteRequest* req =
        [[ListenerTestRemoteRequest alloc] initWithMethod: method
                                                      URL: url
                                                     body: bodyObj
                                             onCompletion:
         ^(ListenerTestRemoteRequest* result, NSError *error) {
             AssertEq(result.status, expectedStatus);
             for (NSString* key in [expectedHeader allKeys])
                 AssertEqual(result.responseHeaders[key], expectedHeader[key]);
             if (expectedResult)
                 AssertEqual(result.data, expectedResult);

             [expectDidComplete fulfill];
         }];

    [headers enumerateKeysAndObjectsUsingBlock:^(id header, id value, BOOL* stop) {
        [req setValue: value forHTTPHeaderField: header];
    }];
    if (clientCredential) {
        req.authorizer = [[CBLClientCertAuthorizer alloc] initWithIdentity: clientCredential.identity
                                                           supportingCerts: clientCredential.certificates];
    }

    [_session startRequest: req];
    [self waitForExpectationsWithTimeout: kTimeout handler: nil];
}

@end

@implementation ListenerTestRemoteRequest

@synthesize data=_data;

- (void) setValue:(NSString*)value forHTTPHeaderField:(NSString *)header {
    [_request setValue: value forHTTPHeaderField: header];
}

- (int)status {
    return _status;
}

- (void) didReceiveData:(NSData *)data {
    [super didReceiveData: data];
    if (!_data)
        _data = [[NSMutableData alloc] initWithCapacity: data.length];
    [_data appendData: data];
}

- (void) didFailWithError:(NSError *)error {
    [self clearConnection];
    [self respondWithResult: self error: error];
}

@end
