//
//  ReplicatorTest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLReplicator+Internal.h"
#import "CBLDatabase+Internal.h"
#import "ConflictTest.h"

#define kCBLEnableSyncGatewayTest NO
#define kCBLSyncGatewayTestHost @"localhost"

@interface ReplicatorTest : CBLTestCase
@end


@implementation ReplicatorTest
{
    CBLDatabase* otherDB;
    CBLReplicator* repl;
    NSTimeInterval timeout;
    BOOL _stopped;
}


- (void) setUp {
    [super setUp];

    timeout = 5.0;
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
    CBLReplicatorConfiguration* c =
    [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                  target: target
                                                   block:
     ^(CBLReplicatorConfigurationBuilder* builder) {
         builder.replicatorType = type;
         builder.continuous = continuous;
         builder.authenticator = authenticator;
         if (resolver)
             builder.conflictResolver = resolver;
     }];
    
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


- (void) eraseRemoteDB: (NSURL*)url {
    // Post to /db/_flush is supported by Sync Gateway 1.1, but not by CouchDB
    NSURLComponents* comp = [NSURLComponents componentsWithURL: url resolvingAgainstBaseURL: YES];
    comp.port = ([url.scheme isEqualToString: @"http"]) ? @4985 : @4995;
    comp.path = [comp.path stringByAppendingPathComponent: @"_flush"];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: comp.URL];
    request.HTTPMethod = @"POST";
    
    XCTestExpectation* x = [self expectationWithDescription: @"Complete Request"];
    NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest: request
                                                                 completionHandler:
                                  ^(NSData *data, NSURLResponse *response, NSError *error)
    {
        NSLog(@"Deleting %@, status = %ld, error: = %@", url,
              (long)((NSHTTPURLResponse*)response).statusCode, error);
        if (!error)
            [x fulfill];
    }];
    [task resume];
    [self waitForExpectations: @[x] timeout: 10.0];
}


- (CBLURLEndpoint*) remoteEndpointWithName: (NSString*)dbName secure: (BOOL)secure {
    return [[CBLURLEndpoint alloc] initWithHost: kCBLSyncGatewayTestHost
                                           port: (secure ? 4994 : 4984)
                                           path: dbName
                                         secure: secure];
}


- (void)testEmptyPush {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorPush continuous: NO];
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
    id config = [self configWithTarget: target type: kCBLReplicatorPush continuous: NO];
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
    id config = [self configWithTarget: target type: kCBLReplicatorPush continuous: YES];
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
    id config = [self configWithTarget: target type: kCBLReplicatorPull continuous: NO];
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
    id config = [self configWithTarget: target type: kCBLReplicatorPull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    CBLDocument* savedDoc2 = [self.db documentWithID: @"doc2"];
    AssertEqualObjects([savedDoc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullConflict {
    // Create a document and push it to otherDB:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);

    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type :kCBLReplicatorPush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];

    // Now make different changes in db and otherDB:
    doc1 = [[self.db documentWithID: @"doc"] toMutable];
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);

    CBLMutableDocument* doc2 = [[otherDB documentWithID: @"doc"] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    // Pull from otherDB, creating a conflict to resolve:
    MergeThenTheirsWins* resolver = [MergeThenTheirsWins new];
    resolver.requireBaseRevision = true;
    config = [self configWithTarget: target type: kCBLReplicatorPull continuous: NO
                   conflictResolver: resolver];
    [self run: config errorCode: 0 errorDomain: nil];

    // Check that it was resolved:
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertEqualObjects(savedDoc.toDictionary, (@{@"species": @"Tiger",
                                                 @"name": @"Hobbes",
                                                 @"pattern": @"striped"}));
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
    id config = [self configWithTarget: target type :kCBLReplicatorPull continuous: NO
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
    id config = [self configWithTarget: target type: kCBLReplicatorPushAndPull continuous: YES];
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
    id config = [self configWithTarget: target type: kCBLReplicatorPull continuous: YES];
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
    id config = [self configWithTarget: target type: kCBLReplicatorPull continuous: YES];
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
    id config = [self configWithTarget: target type: kCBLReplicatorPush continuous: NO];
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
    id config = [self configWithTarget: target type: kCBLReplicatorPull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc1 = [self.db documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 blobForKey:@"blob"], blob);
}

// The following tests are disabled by default as they require Sync Gateway.
// To enable, set the kCBLEnableSyncGatewayTest to YES.
// To start Sync Gateway, please follow the instructions in
// <couchbase-lite-ios>/vendor/couchbase-lite-core/Replicator/tests/data/README.


- (void) testAuthenticationFailure {
    if (!kCBLEnableSyncGatewayTest)
        return;
    
    id target = [self remoteEndpointWithName: @"seekrit" secure: NO];
    id config = [self configWithTarget: target type: kCBLReplicatorPull continuous: NO];
    [self run: config errorCode: 401 errorDomain: @"WebSocket"];
}


- (void) testAuthenticatedPull {
    if (!kCBLEnableSyncGatewayTest)
        return;
    
    id target = [self remoteEndpointWithName: @"seekrit" secure: NO];
    id auth = [[CBLBasicAuthenticator alloc] initWithUsername: @"pupshaw" password: @"frank"];
    id config = [self configWithTarget: target type: kCBLReplicatorPull
                            continuous: NO authenticator: auth conflictResolver: nil];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) failTestPushBlobToSyncGateway {
    if (!kCBLEnableSyncGatewayTest)
        return;
    
    [self eraseRemoteDB: [NSURL URLWithString: @"http://localhost:4984/scratch"]];
    
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    id config = [self configWithTarget: target type : kCBLReplicatorPush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestMissingHost {
    if (!kCBLEnableSyncGatewayTest)
        return;
    
    timeout = 200;
    id target = [[CBLURLEndpoint alloc] initWithHost: @"foo.couchbase.com" port: 0 path: @"db" secure: NO];
    id config = [self configWithTarget: target type: kCBLReplicatorPull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
}


// This test assumes an SG is serving SSL at port 4994 with a self-signed cert.
- (void) testSelfSignedSSLFailure {
    if (!kCBLEnableSyncGatewayTest)
        return;
    
    id target = [self remoteEndpointWithName: @"beer" secure: YES];
    id config = [self configWithTarget: target type: kCBLReplicatorPull continuous: NO];
    [self run: config errorCode: kCFURLErrorServerCertificateHasUnknownRoot errorDomain: NSURLErrorDomain];
}


// This test assumes an SG is serving SSL at port 4994 with a self-signed cert equal to the one
// stored in the test resource SelfSigned.cer. (This is the same cert used in the 1.x unit tests.)
- (void) testSelfSignedSSLPinned {
    if (!kCBLEnableSyncGatewayTest)
        return;
    
    NSData* certData = [self dataFromResource: @"SelfSigned" ofType: @"cer"];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert);
    
    id target = [self remoteEndpointWithName: @"beer" secure: YES];
    id config = [self configWithTarget: target type: kCBLReplicatorPull continuous: NO];
    config = [[CBLReplicatorConfiguration alloc] initWithConfig: config block: ^(CBLReplicatorConfigurationBuilder* builder) {
        builder.pinnedServerCertificate = cert;
    }];
    [self run: config errorCode: 0 errorDomain: nil];
}


@end
