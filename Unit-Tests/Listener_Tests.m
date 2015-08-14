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
#import "CBLClientCertAuthorizer.h"
#import "BLIPPocketSocketConnection.h"
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
}

- (void)tearDown {
    listener.delegate = nil;
    [listener stop];
    ++sPort;
    [super tearDown];
}


- (void)test01_SSL_NoClientCert {
    if (!self.isSQLiteDB)
        return;
    NSError* error;
    Assert([listener setAnonymousSSLIdentityWithLabel: @"CBLUnitTests" error: &error],
           @"Failed to set SSL identity: %@", error);
    // Wait for listener to start:
    if (listener.port == 0) {
        [self keyValueObservingExpectationForObject: listener keyPath: @"port" expectedValue: @(sPort)];
        [listener start: NULL];
        [self waitForExpectationsWithTimeout: kTimeout handler: nil];
    }

    _expectAuthenticateTrust = [self expectationWithDescription: @"authenticateWithTrust"];
    [self connect];
}


- (void)test02_SSL_ClientCert {
    if (!self.isSQLiteDB)
        return;
    NSError* error;
    Assert([listener setAnonymousSSLIdentityWithLabel: @"CBLUnitTests" error: &error],
           @"Failed to set SSL identity: %@", error);
    // Wait for listener to start:
    if (listener.port == 0) {
        [self keyValueObservingExpectationForObject: listener keyPath: @"port" expectedValue: @(sPort)];
        [listener start: NULL];
        [self waitForExpectationsWithTimeout: kTimeout handler: nil];
    }

    SecIdentityRef identity = MYGetOrCreateAnonymousIdentity(@"CBLUnitTests-Client",
                                                     kMYAnonymousIdentityDefaultExpirationInterval,
                                                     &error);
    Assert(identity, @"Couldn't create client identity: %@", error);
    clientCredential = [NSURLCredential credentialWithIdentity: identity certificates: nil
                                                   persistence: NSURLCredentialPersistenceNone];

    _expectAuthenticateTrust = [self expectationWithDescription: @"authenticateWithTrust"];
    [self connect];
}


- (void) connect {
    NSURL* url = [[listener.URL URLByAppendingPathComponent: db.name]
                                      URLByAppendingPathComponent: @"_blipsync"];
    Log(@"Connecting to <%@>", url);
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




@interface ListenerHTTP_Tests : Listener_Tests <CBLRemoteRequestDelegate>
@end


@implementation ListenerHTTP_Tests
{
    XCTestExpectation* _expectCheckServerTrust;
}

- (Class) listenerClass {
    return [CBLHTTPListener class];
}

// Have to override these so Xcode will recognize that these tests exist in this class:
- (void)test01_SSL_NoClientCert    {[super test01_SSL_NoClientCert];}
- (void)test02_SSL_ClientCert      {[super test02_SSL_ClientCert];}


- (void) connect {
    Log(@"Connecting to <%@>", listener.URL);
    XCTestExpectation* expectDidComplete = [self expectationWithDescription: @"didComplete"];
    CBLRemoteRequest* req = [[CBLRemoteJSONRequest alloc] initWithMethod: @"GET" URL: listener.URL body: nil requestHeaders: nil onCompletion:^(id result, NSError *error) {
        AssertNil(error);
        Assert(result != nil);
        [expectDidComplete fulfill];
    }];

    if (clientCredential) {
        req.authorizer = [[CBLClientCertAuthorizer alloc] initWithIdentity: clientCredential.identity supportingCerts: clientCredential.certificates];
    }

    _expectCheckServerTrust = [self expectationWithDescription: @"checkServerTrust"];
    req.delegate = self;
    [req start];
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

@end
