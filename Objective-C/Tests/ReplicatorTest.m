//
//  ReplicatorTest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLReplicator+Internal.h"
#import "ConflictTest.h"


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


- (CBLReplicatorConfiguration*) configForPush: (BOOL)push
                                         pull: (BOOL)pull
                                   continuous: (BOOL)continuous
{
    CBLReplicatorConfiguration* c = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                          targetDatabase: otherDB];
    c.replicatorType = push && pull ? kCBLPushAndPull : (push ? kCBLPush : kCBLPull);
    c.continuous = continuous;
    return c;
}


- (CBLReplicatorConfiguration*) configForPush: (BOOL)push
                                         pull: (BOOL)pull
                                   continuous: (BOOL)continuous
                                          url: (NSString*)url
{
    NSURL* u = [NSURL URLWithString: url];
    CBLReplicatorConfiguration* c = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                               targetURL: u];
    c.replicatorType = push && pull ? kCBLPushAndPull : (push ? kCBLPush : kCBLPull);
    c.continuous = continuous;
    return c;
}


- (void) run: (CBLReplicatorConfiguration*)config
   errorCode: (NSInteger)errorCode
 errorDomain: (NSString*)errorDomain
{
    repl = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation *x = [self expectationWithDescription: @"Replicator Change"];
    __weak typeof(self) wSelf = self;
    id listener = [repl addChangeListener: ^(CBLReplicatorChange* change) {
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
    [self waitForExpectations: @[x] timeout: 7.0];
    [repl removeChangeListener: listener];
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


- (void) testBadURL {
    CBLReplicatorConfiguration* config = [self configForPush: NO pull: YES continuous: NO
                                                         url: @"blxp://localhost/db"];
    [self run: config errorCode: 15 errorDomain: @"LiteCore"];
}


- (void)testEmptyPush {
    CBLReplicatorConfiguration* config = [self configForPush: YES pull: NO continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) testPushDoc {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setObject: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    CBLReplicatorConfiguration* config = [self configForPush: YES pull: NO continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 stringForKey:@"name"], @"Tiger");
}


- (void) testPushDocContinuous {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setObject: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    CBLReplicatorConfiguration* config = [self configForPush: YES pull: NO continuous: YES];
    config.checkpointInterval = 1.0;
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 stringForKey:@"name"], @"Tiger");
}


- (void) testPullDoc {
    // For https://github.com/couchbase/couchbase-lite-core/issues/156
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);

    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setObject: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    CBLReplicatorConfiguration* config = [self configForPush: NO pull: YES continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];

    AssertEqual(self.db.count, 2u);
    CBLDocument* savedDoc2 = [self.db documentWithID:@"doc2"];
    AssertEqualObjects([savedDoc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullDocContinuous {
    // For https://github.com/couchbase/couchbase-lite-core/issues/156
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc1"];
    [doc1 setObject: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID:@"doc2"];
    [doc2 setObject: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    CBLReplicatorConfiguration* config = [self configForPush: NO pull: YES continuous: YES];
    config.checkpointInterval = 1.0;
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    CBLDocument* savedDoc2 = [self.db documentWithID: @"doc2"];
    AssertEqualObjects([savedDoc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullConflict {
    // Create a document and push it to otherDB:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setObject: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);

    CBLReplicatorConfiguration* config = [self configForPush: YES pull: NO continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];

    // Now make different changes in db and otherDB:
    doc1 = [[self.db documentWithID: @"doc"] toMutable];
    [doc1 setObject: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);

    CBLMutableDocument* doc2 = [[otherDB documentWithID: @"doc"] toMutable];
    Assert(doc2);
    [doc2 setObject: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    // Pull from otherDB, creating a conflict to resolve:
    config = [self configForPush: NO pull: YES continuous: NO];
    MergeThenTheirsWins* resolver = [MergeThenTheirsWins new];
    resolver.requireBaseRevision = true;
    config.conflictResolver = resolver;
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
    [doc1 setObject: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    [doc1 setObject: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);

    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc2 setObject: @"Tiger" forKey: @"species"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    [doc2 setObject: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    CBLReplicatorConfiguration* config = [self configForPush: NO pull: YES continuous: NO];
    config.conflictResolver = [MergeThenTheirsWins new];
    [self run: config errorCode: 0 errorDomain: nil];

    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertEqualObjects(savedDoc.toDictionary, (@{@"species": @"Tiger",
                                                 @"name": @"Hobbes",
                                                 @"pattern": @"striped"}));
}


- (void) testStopContinuousReplicator {
    [CBLDatabase setLogLevel: kCBLLogLevelDebug domain: kCBLLogDomainReplicator];
    
    CBLReplicatorConfiguration* config = [self configForPush: YES pull: YES continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];

    NSArray* stopWhen = @[@(kCBLReplicatorConnecting), @(kCBLReplicatorBusy),
                          @(kCBLReplicatorIdle), @(kCBLReplicatorIdle)];
    for (id when in stopWhen) {
        XCTestExpectation* x = [self expectationWithDescription: @"Replicator Change"];
        __weak typeof(self) wSelf = self;
        id listener = [r addChangeListener: ^(CBLReplicatorChange *change) {
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
        [r removeChangeListener: listener];

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


// These test are disabled because they require a password-protected database 'seekrit' to exist
// on localhost:4984, with a user 'pupshaw' whose password is 'frank'.

- (void) dontTestAuthenticationFailure {
    CBLReplicatorConfiguration* config = [self configForPush: NO pull: YES continuous: NO
                                                         url: @"blip://localhost:4984/seekrit"];
    [self run: config errorCode: 401 errorDomain: @"WebSocket"];
}


- (void) dontTestAuthenticatedPullHardcoded {
    CBLReplicatorConfiguration* config = [self configForPush: NO pull: YES continuous: NO
                                                         url: @"blip://pupshaw:frank@localhost:4984/seekrit"];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestAuthenticatedPull {
    CBLReplicatorConfiguration* config = [self configForPush: NO pull: YES continuous: NO
                                                         url: @"blip://localhost:4984/seekrit"];
    config.authenticator = [[CBLBasicAuthenticator alloc] initWithUsername: @"pupshaw" password: @"frank"];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestMissingHost {
    timeout = 200;
    CBLReplicatorConfiguration* config = [self configForPush: NO pull: YES continuous: NO
                                                url: @"blip://foo.couchbase.com/db"];
    config.continuous = YES;
    [self run: config errorCode: 0 errorDomain: nil];
}


// This test assumes an SG is serving SSL at port 4994 with a self-signed cert.
- (void) dontTestSelfSignedSSLFailure {
    CBLReplicatorConfiguration* config = [self configForPush: NO pull: YES continuous: NO
                                                         url: @"blips://localhost:4994/beer"];
    [self run: config errorCode: kCFURLErrorServerCertificateHasUnknownRoot errorDomain: NSURLErrorDomain];
}


// This test assumes an SG is serving SSL at port 4994 with a self-signed cert equal to the one
// stored in the test resource SelfSigned.cer. (This is the same cert used in the 1.x unit tests.)
- (void) dontTestSelfSignedSSLPinned {
    NSString* path = [[NSBundle bundleForClass: [self class]] pathForResource: @"SelfSigned" ofType: @"cer"];
    NSData* certData = [NSData dataWithContentsOfFile: path];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert);
    CBLReplicatorConfiguration* config = [self configForPush: NO pull: YES continuous: NO
                                                         url: @"blips://localhost:4994/beer"];
    config.pinnedServerCertificate = cert;
    [self run: config errorCode: 0 errorDomain: nil];
}


@end
