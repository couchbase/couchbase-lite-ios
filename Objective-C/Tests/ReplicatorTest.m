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


- (CBLReplicatorConfiguration*) push: (BOOL)push pull: (BOOL)pull continuous: (BOOL)continuous {
    CBLReplicatorConfiguration* c = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                          targetDatabase: otherDB];
    c.replicatorType = push && pull ? kCBLPushAndPull : (push ? kCBLPush : kCBLPull);
    c.continuous = continuous;
    return c;
}


- (CBLReplicatorConfiguration*) push: (BOOL)push pull: (BOOL)pull continuous: (BOOL)continuous
                                 url: (NSString*)url {
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
        if (config.continuous && change.status.activity == kCBLIdle
                    && change.status.progress.completed == change.status.progress.total) {
            [strongSelf->repl stop];
        }
        if (change.status.activity == kCBLStopped) {
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
    
    static const char* const kActivityNames[5] = { "stopped", "idle", "busy" };
    NSLog(@"---Status: %s (%llu / %llu), lastError = %@",
          kActivityNames[s.activity], s.progress.completed, s.progress.total,
          s.error.localizedDescription);
    
    if (s.activity == kCBLStopped) {
        if (code != 0) {
            AssertEqual(s.error.code, code);
            if (domain)
                AssertEqualObjects(s.error.domain, domain);
        } else
            AssertNil(s.error);
    }
}


- (void) testBadURL {
    CBLReplicatorConfiguration* config = [self push: NO pull: YES continuous: NO
                                                url: @"blxp://localhost/db"];
    [self run: config errorCode: 15 errorDomain: @"LiteCore"];
}


- (void)testEmptyPush {
    CBLReplicatorConfiguration* config = [self push: YES pull: NO continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) testPushDoc {
    NSError* error;
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID:@"doc1"];
    [doc1 setObject: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLDocument* doc2 = [[CBLDocument alloc] initWithID:@"doc2"];
    [doc2 setObject: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    CBLReplicatorConfiguration* config = [self push: YES pull: NO continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    doc2 = [otherDB documentWithID:@"doc1"];
    AssertEqualObjects([doc2 stringForKey:@"name"], @"Tiger");
}


- (void) testPushDocContinuous {
    NSError* error;
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID:@"doc1"];
    [doc1 setObject: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLDocument* doc2 = [[CBLDocument alloc] initWithID:@"doc2"];
    [doc2 setObject: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    CBLReplicatorConfiguration* config = [self push: YES pull: NO continuous: YES];
    config.checkpointInterval = 1.0;
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    doc2 = [otherDB documentWithID:@"doc1"];
    AssertEqualObjects([doc2 stringForKey:@"name"], @"Tiger");
}


- (void) testPullDoc {
    // For https://github.com/couchbase/couchbase-lite-core/issues/156
    NSError* error;
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID:@"doc1"];
    [doc1 setObject: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);

    CBLDocument* doc2 = [[CBLDocument alloc] initWithID:@"doc2"];
    [doc2 setObject: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    CBLReplicatorConfiguration* config = [self push: NO pull: YES continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];

    AssertEqual(self.db.count, 2u);
    doc2 = [self.db documentWithID:@"doc2"];
    AssertEqualObjects([doc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullDocContinuous {
    // For https://github.com/couchbase/couchbase-lite-core/issues/156
    NSError* error;
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID:@"doc1"];
    [doc1 setObject: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLDocument* doc2 = [[CBLDocument alloc] initWithID:@"doc2"];
    [doc2 setObject: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    CBLReplicatorConfiguration* config = [self push: NO pull: YES continuous: YES];
    config.checkpointInterval = 1.0;
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    doc2 = [self.db documentWithID:@"doc2"];
    AssertEqualObjects([doc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullConflict {
    // Create a document and push it to otherDB:
    NSError* error;
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID:@"doc"];
    [doc1 setObject: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);

    CBLReplicatorConfiguration* config = [self push: YES pull: NO continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];

    // Now make different changes in db and otherDB:
    doc1 = [self.db documentWithID: @"doc"];
    [doc1 setObject: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);

    CBLDocument* doc2 = [otherDB documentWithID: @"doc"];
    Assert(doc2);
    [doc2 setObject: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    // Pull from otherDB, creating a conflict to resolve:
    config = [self push: NO pull: YES continuous: NO];
    MergeThenTheirsWins* resolver = [MergeThenTheirsWins new];
    resolver.requireBaseRevision = true;
    config.conflictResolver = resolver;
    [self run: config errorCode: 0 errorDomain: nil];

    // Check that it was resolved:
    AssertEqual(self.db.count, 1u);
    doc1 = [self.db documentWithID:@"doc"];
    AssertEqualObjects(doc1.toDictionary, (@{@"species": @"Tiger",
                                             @"name": @"Hobbes",
                                             @"pattern": @"striped"}));
}


- (void) testPullConflictNoBaseRevision {
    // Create the conflicting docs separately in each database. They have the same base revID
    // because the contents are identical, but because the db never pushed revision 1, it doesn't
    // think it needs to preserve its body; so when it pulls a conflict, there won't be a base
    // revision for the resolver.
    NSError* error;
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID:@"doc"];
    [doc1 setObject: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    [doc1 setObject: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);

    CBLDocument* doc2 = [[CBLDocument alloc] initWithID:@"doc"];
    [doc2 setObject: @"Tiger" forKey: @"species"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    [doc2 setObject: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    CBLReplicatorConfiguration* config = [self push: NO pull: YES continuous: NO];
    config.conflictResolver = [MergeThenTheirsWins new];
    [self run: config errorCode: 0 errorDomain: nil];

    AssertEqual(self.db.count, 1u);
    doc1 = [self.db documentWithID:@"doc"];
    AssertEqualObjects(doc1.toDictionary, (@{@"species": @"Tiger",
                                             @"name": @"Hobbes",
                                             @"pattern": @"striped"}));
}


// These test are disabled because they require a password-protected database 'seekrit' to exist
// on localhost:4984, with a user 'pupshaw' whose password is 'frank'.

- (void) dontTestAuthenticationFailure {
    CBLReplicatorConfiguration* config = [self push: NO pull: YES continuous: NO
                                                url: @"blip://localhost:4984/seekrit"];
    [self run: config errorCode: 401 errorDomain: @"WebSocket"];
}


- (void) dontTestAuthenticatedPullHardcoded {
    CBLReplicatorConfiguration* config = [self push: NO pull: YES continuous: NO
                                                url: @"blip://pupshaw:frank@localhost:4984/seekrit"];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestAuthenticatedPull {
    CBLReplicatorConfiguration* config = [self push: NO pull: YES continuous: NO
                                                url: @"blip://localhost:4984/seekrit"];
    config.authenticator = [[CBLBasicAuthenticator alloc] initWithUsername: @"pupshaw" password: @"frank"];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestMissingHost {
    timeout = 200;
    CBLReplicatorConfiguration* config = [self push: NO pull: YES continuous: NO
                                                url: @"blip://foo.couchbase.com/db"];
    config.continuous = YES;
    [self run: config errorCode: 0 errorDomain: nil];
}


// This test assumes an SG is serving SSL at port 4994 with a self-signed cert.
- (void) dontTestSelfSignedSSLFailure {
    CBLReplicatorConfiguration* config = [self push: NO pull: YES continuous: NO
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
    CBLReplicatorConfiguration* config = [self push: NO pull: YES continuous: NO
                                                url: @"blips://localhost:4994/beer"];
    config.pinnedServerCertificate = cert;
    [self run: config errorCode: 0 errorDomain: nil];
}


@end
