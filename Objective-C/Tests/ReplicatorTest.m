//
//  ReplicatorTest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLReplicator+Internal.h"
#import "CBLURLEndpoint+Internal.h"
#import "CBLDatabase+Internal.h"
#import "ConflictTest.h"
#import "CollectionUtils.h"


@interface ReplicatorTest : CBLTestCase
@end


@implementation ReplicatorTest
{
    CBLDatabase* otherDB;
    CBLReplicator* repl;
    NSTimeInterval timeout;
    BOOL _stopped;
    BOOL _pinServerCert;
}


- (void) setUp {
    [super setUp];

    timeout = 5.0;
    _pinServerCert = YES;
    NSError* error;
    otherDB = [self openDBNamed: @"otherdb" error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
}


- (void) tearDown {
    NSError* error;
    Assert([otherDB close: &error]);
    otherDB = nil;
    repl = nil;
    [super tearDown];
}


/** Returns an endpoint for a Sync Gateway test database, or nil if SG tests are not enabled.
    To enable these tests, set the hostname of the server in the environment variable
    "CBL_TEST_HOST".
    The port number defaults to 4984, or 4994 for SSL. To override these, set the environment
    variables "CBL_TEST_PORT" and/or "CBL_TEST_PORT_SSL".
    Note: On iOS, all endpoints will be SSL regardless of the `secure` flag. */
- (CBLURLEndpoint*) remoteEndpointWithName: (NSString*)dbName secure: (BOOL)secure {
    NSString* host = NSProcessInfo.processInfo.environment[@"CBL_TEST_HOST"];
    if (!host) {
        Log(@"NOTE: Skipping test: no CBL_TEST_HOST configured in environment");
        return nil;
    }

    NSString* portKey = secure ? @"CBL_TEST_PORT_SSL" : @"CBL_TEST_PORT";
    NSInteger port = NSProcessInfo.processInfo.environment[portKey].integerValue;
    if (!port)
        port = secure ? 4994 : 4984;

    NSURLComponents *comp = [NSURLComponents new];
    comp.scheme = secure ? kCBLURLEndpointTLSScheme : kCBLURLEndpointScheme;
    comp.host = host;
    comp.port = @(port);
    comp.path = [NSString stringWithFormat:@"/%@", dbName];
    NSURL* url = comp.URL;
    Assert(url);
    return [[CBLURLEndpoint alloc] initWithURL: url];
}


- (BOOL) eraseRemoteEndpoint: (CBLURLEndpoint*)endpoint {
    NSURL* endpointURL = endpoint.url;
    
    Assert([endpointURL.path isEqualToString: @"/scratch"], @"Only scratch db should be erased");
    NSURLComponents *comp = [NSURLComponents new];
    comp.scheme = [endpointURL.scheme isEqualToString: kCBLURLEndpointTLSScheme] ? @"https" : @"http";
    comp.host = endpointURL.host;
    comp.port = @([endpointURL.port intValue] + 1);   // assuming admin port is at usual offset
    comp.path = [NSString stringWithFormat: @"%@/_flush", endpointURL.path];
    NSURL* url = comp.URL;
    Assert(url);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = @"POST";

    __block NSError* error = nil;
    __block NSInteger status = 0;
    XCTestExpectation* x = [self expectationWithDescription: @"Complete Request"];
    NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest: request
                                                                 completionHandler:
                                  ^(NSData *data, NSURLResponse *response, NSError *err)
    {
        error = err;
        status = ((NSHTTPURLResponse*)response).statusCode;
        [x fulfill];
    }];
    [task resume];
    [self waitForExpectations: @[x] timeout: timeout];
    
    if (error != nil || status >= 300) {
        XCTFail(@"Failed to delete remote db; URL=<%@>, status=%ld, error=%@",
                url, (long)status, error);
        return NO;
    } else {
        Log(@"Erased remote database %@", url);
        return YES;
    }
}


- (SecCertificateRef) secureServerCert {
    NSData* certData = [self dataFromResource: @"SelfSigned" ofType: @"cer"];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert);
    return (SecCertificateRef)CFAutorelease(cert);
}


- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
{
    return [self configWithTarget: target
                             type: type
                       continuous: continuous
                    authenticator: nil
                 conflictResolver: nil];
}


- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
                                conflictResolver: (nullable id <CBLConflictResolver>)resolver
{
    return [self configWithTarget: target
                             type: type
                       continuous: continuous
                    authenticator: nil
                 conflictResolver: resolver];
}


- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
                                   authenticator: (CBLAuthenticator*)authenticator
                                conflictResolver: (nullable id <CBLConflictResolver>)resolver
{
    CBLReplicatorConfiguration* c = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                  target: target];
    c.replicatorType = type;
    c.continuous = continuous;
    c.authenticator = authenticator;
    if (resolver)
        c.conflictResolver = resolver;
    
    if ([$castIf(CBLURLEndpoint, target).url.scheme isEqualToString: @"wss"] && _pinServerCert)
        c.pinnedServerCertificate = self.secureServerCert;
    
    if (continuous)
        c.checkpointInterval = 1.0; // For testing only
    
    return c;
}


- (void) run: (CBLReplicatorConfiguration*)config
   errorCode: (NSInteger)errorCode
 errorDomain: (NSString*)errorDomain
{
    repl = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation* x = [self expectationWithDescription: @"Replicator Change"];
    __weak typeof(self) wSelf = self;
    id token = [repl addChangeListener: ^(CBLReplicatorChange* change) {
        typeof(self) strongSelf = wSelf;
        [strongSelf verifyChange: change errorCode: errorCode errorDomain:errorDomain];
        if (config.continuous && change.status.activity == kCBLReplicatorIdle
                    && change.status.progress.completed == change.status.progress.total) {
            [strongSelf->repl stop];
        }
        if (change.status.activity == kCBLReplicatorStopped) {
            [x fulfill];
        }
    }];
    
    [repl start];
    [self waitForExpectations: @[x] timeout: 10.0];
    [repl removeChangeListenerWithToken: token];
}


- (void) verifyChange: (CBLReplicatorChange*)change
            errorCode: (NSInteger)code
          errorDomain: (NSString*)domain
{
    CBLReplicatorStatus* s = change.status;
    
    static const char* const kActivityNames[5] = { "stopped", "offline", "connecting", "idle", "busy" };
    NSLog(@"---Status: %s (%llu / %llu), lastError = %@",
          kActivityNames[s.activity], s.progress.completed, s.progress.total,
          s.error.localizedDescription);
    
    if (s.activity == kCBLReplicatorStopped) {
        if (code != 0) {
            AssertEqual(s.error.code, code);
            if (domain)
                AssertEqualObjects(s.error.domain, domain);
        } else
            AssertNil(s.error);
    }
}


#pragma mark - TESTS:


- (void)testEmptyPush {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) testPushDoc {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 stringForKey:@"name"], @"Tiger");
}


- (void) testPushDocContinuous {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 stringForKey:@"name"], @"Tiger");
}


- (void) testPullDoc {
    // For https://github.com/couchbase/couchbase-lite-core/issues/156
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);

    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];

    AssertEqual(self.db.count, 2u);
    CBLDocument* savedDoc2 = [self.db documentWithID:@"doc2"];
    AssertEqualObjects([savedDoc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullDocContinuous {
    // For https://github.com/couchbase/couchbase-lite-core/issues/156
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID:@"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    CBLDocument* savedDoc2 = [self.db documentWithID: @"doc2"];
    AssertEqualObjects([savedDoc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullConflict_MineWins {
    [self testPullConflictWithResolver: [MineWins new]
                        expectedResult: @{@"species": @"Tiger",
                                          @"name": @"Hobbes"}];
}

- (void) testPullConflict_TheirsWins {
    [self testPullConflictWithResolver: [TheirsWins new]
                        expectedResult: @{@"species": @"Tiger",
                                          @"pattern": @"striped"}];
}

- (void) testPullConflict_MergeThenTheirsWins {
    MergeThenTheirsWins* resolver = [MergeThenTheirsWins new];
    resolver.requireBaseRevision = true;
    [self testPullConflictWithResolver: resolver
                        expectedResult: @{@"species": @"Tiger",
                                          @"name": @"Hobbes",
                                          @"pattern": @"striped"}];
}

- (void) testPullConflictWithResolver: (TestResolver*)resolver
                       expectedResult: (NSDictionary*)expectedResult
{
    // Create a document and push it to otherDB:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);

    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id pushConfig = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: pushConfig errorCode: 0 errorDomain: nil];

    // Now make different changes in db and otherDB:
    doc1 = [[self.db documentWithID: @"doc"] toMutable];
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);

    CBLMutableDocument* doc2 = [[otherDB documentWithID: @"doc"] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    // Pull from otherDB, creating a conflict to resolve:
    id pullConfig = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO
                   conflictResolver: resolver];
    [self run: pullConfig errorCode: 0 errorDomain: nil];

    // Check that it was resolved:
    Assert(resolver.wasCalled);
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertEqualObjects(savedDoc.toDictionary, expectedResult);

    // Push to otherDB again to verify there is no replication conflict now,
    // and that otherDB ends up with the same resolved document:
    [self run: pushConfig errorCode: 0 errorDomain: nil];

    AssertEqual(otherDB.count, 1u);
    CBLDocument* otherSavedDoc = [otherDB documentWithID: @"doc"];
    AssertEqualObjects(otherSavedDoc.toDictionary, expectedResult);
}


- (void) testPullConflictNoBaseRevision {
    // Create the conflicting docs separately in each database. They have the same base revID
    // because the contents are identical, but because the db never pushed revision 1, it doesn't
    // think it needs to preserve its body; so when it pulls a conflict, there won't be a base
    // revision for the resolver.
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    
    doc1 = [[self.db saveDocument: doc1 error: &error] toMutable];
    Assert(doc1);
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);

    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc2 setValue: @"Tiger" forKey: @"species"];
    doc2 = [[otherDB saveDocument: doc2 error: &error] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type :kCBLReplicatorTypePull continuous: NO
                      conflictResolver: [MergeThenTheirsWins new]];
    [self run: config errorCode: 0 errorDomain: nil];

    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertEqualObjects(savedDoc.toDictionary, (@{@"species": @"Tiger",
                                                 @"name": @"Hobbes",
                                                 @"pattern": @"striped"}));
}


- (void) testStopContinuousReplicator {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];

    NSArray* stopWhen = @[@(kCBLReplicatorConnecting), @(kCBLReplicatorBusy),
                          @(kCBLReplicatorIdle), @(kCBLReplicatorIdle)];
    for (id when in stopWhen) {
        XCTestExpectation* x = [self expectationWithDescription: @"Replicator Change"];
        __weak typeof(self) wSelf = self;
        id token = [r addChangeListener: ^(CBLReplicatorChange *change) {
            [wSelf verifyChange: change errorCode: 0 errorDomain: nil];
            if (change.status.activity == [when intValue]) {
                NSLog(@"***** Stop Replicator ******");
                [change.replicator stop];
            } else if (change.status.activity == kCBLReplicatorStopped) {
                [x fulfill];
            }
        }];

        NSLog(@"***** Start Replicator ******");
        [r start];
        [self waitForExpectations: @[x] timeout: 5.0];
        [r removeChangeListenerWithToken: token];

        // Add some delay:
        [NSThread sleepForTimeInterval: 0.1];
    }
}


// Runs -testStopContinuousReplicator over and over again indefinitely. (Disabled, obviously)
- (void) _testStopContinuousReplicatorForever {
    for (int i = 0; true; i++) {
        @autoreleasepool {
            Log(@"**** Begin iteration %d ****", i);
            @autoreleasepool {
                [self testStopContinuousReplicator];
            }
            Log(@"**** End iteration %d ****", i);
            fprintf(stderr, "\n\n");
            [self tearDown];
            [NSThread sleepForTimeInterval: 1.0];
            [self setUp];
        }
    }
}


- (void) testCleanupOfActiveReplicationsAfterDatabaseClose {
    // add a replicator to the DB
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation *x = [self expectationWithDescription: @"Replicator Close"];

    // add observer to check if replicators are stopped on DB close
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorStopped) {
            [x fulfill];
        }
    }];
    
    [r start];
    AssertEqual(self.db.activeReplications.count,(unsigned long)1);
    
    // Close Database - This should trigger a replication stop which should be caught by
    // replicator change listener
    NSError* error;
    [self.db close:&error];
    
    [self waitForExpectations: @[x] timeout: 7.0];
    AssertEqual(self.db.activeReplications.count,(unsigned long)0);
    
    [r removeChangeListenerWithToken: token];
    
}


- (void) testCleanupOfActiveReplicationsAfterDatabaseDelete {
    // add a replicator to the DB
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation *x = [self expectationWithDescription: @"Replicator Close"];
    
    // add observer to check if replicators are stopped on DB close
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorStopped) {
            [x fulfill];
         }
    }];
    
    [r start];
    
    // Confirm that one active replicator
    AssertEqual(self.db.activeReplications.count,(unsigned long)1);
    
    // Close Database - This should trigger a replication stop which should be caught by listener
    NSError* error;
    
    [self.db delete:&error];
  
    [self waitForExpectations: @[x] timeout: 7.0];
    AssertEqual(self.db.activeReplications.count,(unsigned long)0);

    [r removeChangeListenerWithToken: token];
}


- (void) testPushBlob {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 1u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 blobForKey:@"blob"], blob);
}


- (void) testPullBlob {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([otherDB saveDocument: doc1 error: &error]);
    AssertEqual(otherDB.count, 1u);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc1 = [self.db documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 blobForKey:@"blob"], blob);
}


#pragma mark - Sync Gateway Tests


- (void) testAuthenticationFailure {
    id target = [self remoteEndpointWithName: @"seekrit" secure: NO];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: CBLErrorHTTPAuthRequired errorDomain: CBLErrorDomain];
}


- (void) testAuthenticatedPull {
    id target = [self remoteEndpointWithName: @"seekrit" secure: NO];
    if (!target)
        return;
    id auth = [[CBLBasicAuthenticator alloc] initWithUsername: @"pupshaw" password: @"frank"];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull
                            continuous: NO authenticator: auth conflictResolver: nil];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) testPushBlobToSyncGateway {
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;

    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpeg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);

    if (![self eraseRemoteEndpoint: target])
        return;
    id config = [self configWithTarget: target type : kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestMissingHost {
    // Note: The replication doesn't fail with an error; because the unknown-host error is
    // considered transient, the replicator just stays offline and waits for a network change.
    // This causes the test to time out.
    timeout = 200;
    
    id target = [[CBLURLEndpoint alloc] initWithURL:[NSURL URLWithString:@"ws://foo.couchbase.com/db"]];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) testSelfSignedSSLFailure {
    id target = [self remoteEndpointWithName: @"scratch" secure: YES];
    if (!target)
        return;
    _pinServerCert = NO;    // without this, SSL handshake will fail
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: kCFURLErrorServerCertificateHasUnknownRoot errorDomain: NSURLErrorDomain];
}


- (void) testSelfSignedSSLPinned {
    id target = [self remoteEndpointWithName: @"scratch" secure: YES];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestContinuousPushNeverending {
    // NOTE: This test never stops even after the replication goes idle.
    // It can be used to test the response to connectivity issues like killing the remote server.
    [CBLDatabase setLogLevel: kCBLLogLevelVerbose domain: kCBLLogDomainNetwork];
    
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: YES];
    repl = [[CBLReplicator alloc] initWithConfig: config];
    [repl start];

    XCTestExpectation* x = [self expectationWithDescription: @"When pigs fly"];
    [self waitForExpectations: @[x] timeout: 1e9];
}


@end
