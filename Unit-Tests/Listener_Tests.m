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
#import "BLIPPocketSocketConnection.h"
#import "MYAnonymousIdentity.h"

#import <arpa/inet.h>


#define kPort 59999


@interface Listener_Tests : CBLTestCaseWithDB <CBLListenerDelegate, BLIPConnectionDelegate>
@end


@implementation Listener_Tests
{
    CBLListener* listener;
    NSURLCredential* clientCredential;
    XCTestExpectation *_expectValidateServerTrust, *_expectDidOpen, *_expectDidClose;
    XCTestExpectation *_expectAuthenticateTrust;
}

- (void)setUp {
    [super setUp];
    dbmgr.dispatchQueue = dispatch_get_main_queue();
    dbmgr.replicatorClassName = @"CBLBlipReplicator";
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}


- (void)testSSL {
    listener = [[CBLSyncListener alloc] initWithManager: dbmgr port: kPort];
    listener.delegate = self;
    NSError* error;
    Assert([listener setAnonymousSSLIdentityWithLabel: @"CBLUnitTests" error: &error],
           @"Failed to set SSL identity: %@", error);
    // Wait for listener to start:
    [self keyValueObservingExpectationForObject: listener keyPath: @"port" expectedValue: @(kPort)];
    [listener start: NULL];
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];

    [self connect];

    [listener stop];
}


- (void)testSSLClientCert {
    listener = [[CBLSyncListener alloc] initWithManager: dbmgr port: kPort];
    listener.delegate = self;
    NSError* error;
    Assert([listener setAnonymousSSLIdentityWithLabel: @"CBLUnitTests" error: &error],
           @"Failed to set SSL identity: %@", error);
    // Wait for listener to start:
    [self keyValueObservingExpectationForObject: listener keyPath: @"port" expectedValue: @(kPort)];
    [listener start: NULL];
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];

    SecIdentityRef identity = MYGetOrCreateAnonymousIdentity(@"CBLUnitTests-Client",
                                                     kMYAnonymousIdentityDefaultExpirationInterval,
                                                     &error);
    Assert(identity, @"Couldn't create client identity: %@", error);
    clientCredential = [NSURLCredential credentialWithIdentity: identity certificates: nil
                                                   persistence: NSURLCredentialPersistenceNone];

    _expectAuthenticateTrust = [self expectationWithDescription: @"authenticateWithTrust"];
    [self connect];

    [listener stop];
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
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];

    _expectDidClose = [self expectationWithDescription: @"didClose"];
    [conn close];
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
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
    Assert(address != nil);
    if (clientCredential) {
        Assert(trust != nil);
        SecCertificateRef clientCert = SecTrustGetCertificateAtIndex(trust, 0);
        SecCertificateRef realClientCert;
        SecIdentityCopyCertificate(clientCredential.identity, &realClientCert);
        Assert(CFEqual(clientCert, realClientCert));
        [_expectAuthenticateTrust fulfill];
        return @"userWithClientCert";
    } else {
        AssertEq(trust, NULL);
        return nil;
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
