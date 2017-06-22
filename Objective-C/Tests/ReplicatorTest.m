//
//  ReplicatorTest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

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


- (CBLReplicatorConfiguration*) push: (BOOL)push pull: (BOOL)pull {
    CBLReplicatorConfiguration* c = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                          targetDatabase: otherDB];
    c.replicatorType = push && pull ? kCBLPushAndPull : (push ? kCBLPush : kCBLPull);
    return c;
}


- (CBLReplicatorConfiguration*) push: (BOOL)push pull: (BOOL)pull url: (NSString*)url {
    NSURL* u = [NSURL URLWithString: url];
    CBLReplicatorConfiguration* c = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                               targetURL: u];
    c.replicatorType = push && pull ? kCBLPushAndPull : (push ? kCBLPush : kCBLPull);
    return c;
}


- (void) run: (CBLReplicatorConfiguration*)config
   errorCode: (NSInteger)code
 errorDomain: (NSString*)errorDomain
{
    repl = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *x =
        [self expectationForNotification: kCBLReplicatorChangeNotification
                                  object: repl
                                 handler: ^BOOL(NSNotification *n)
    {
        CBLReplicatorStatus* status =  n.userInfo[kCBLReplicatorStatusUserInfoKey];
        NSError* error = n.userInfo[kCBLReplicatorErrorUserInfoKey];
        
        static const char* const kActivityNames[5] = { "stopped", "idle", "busy" };
        NSLog(@"---Status: %s (%llu / %llu), lastError = %@",
              kActivityNames[status.activity], status.progress.completed, status.progress.total,
              error.localizedDescription);
        
        if (status.activity == kCBLStopped) {
            if (code != 0) {
                AssertEqual(error.code, code);
                if (errorDomain)
                    AssertEqualObjects(error.domain, errorDomain);
            } else
                AssertNil(error);
            return YES;
        }
        return NO;
    }];
    [repl start];
    [self waitForExpectations: @[x] timeout: 5.0];
}


- (void) testBadURL {
    CBLReplicatorConfiguration* config = [self push: NO pull: YES url: @"blxp://localhost/db"];
    [self run: config errorCode: 15 errorDomain: @"LiteCore"];
}


- (void)testEmptyPush {
    CBLReplicatorConfiguration* config = [self push: YES pull: NO];
    [self run: config errorCode: 0 errorDomain: nil];
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

    CBLReplicatorConfiguration* config = [self push: NO pull: YES];
    [self run: config errorCode: 0 errorDomain: nil];

    AssertEqual(self.db.count, 2u);
    doc2 = [self.db documentWithID:@"doc2"];
    AssertEqualObjects([doc2 stringForKey:@"name"], @"Cat");
}


// These test are disabled because they require a password-protected database 'seekrit' to exist
// on localhost:4984, with a user 'pupshaw' whose password is 'frank'.

- (void) dontTestAuthenticationFailure {
    CBLReplicatorConfiguration* config = [self push: NO pull: YES url: @"blip://localhost:4984/seekrit"];
    [self run: config errorCode: 401 errorDomain: @"WebSocket"];
}


- (void) dontTestAuthenticatedPullHardcoded {
    CBLReplicatorConfiguration* config = [self push: NO pull: YES url: @"blip://pupshaw:frank@localhost:4984/seekrit"];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestAuthenticatedPull {
    CBLReplicatorConfiguration* config = [self push: NO pull: YES url: @"blip://localhost:4984/seekrit"];
    config.authenticator = [[CBLBasicAuthenticator alloc] initWithUsername: @"pupshaw" password: @"frank"];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestMissingHost {
    timeout = 200;
    CBLReplicatorConfiguration* config = [self push: NO pull: YES url: @"blip://foo.couchbase.com/db"];
    config.continuous = YES;
    [self run: config errorCode: 0 errorDomain: nil];
}


// This test assumes an SG is serving SSL at port 4994 with a self-signed cert.
- (void) dontTestSelfSignedSSLFailure {
    CBLReplicatorConfiguration* config = [self push: NO pull: YES url: @"blips://localhost:4994/beer"];
    [self run: config errorCode: kCFURLErrorServerCertificateHasUnknownRoot errorDomain: NSURLErrorDomain];
}


// This test assumes an SG is serving SSL at port 4994 with a self-signed cert equal to the one
// stored in the test resource SelfSigned.cer. (This is the same cert used in the 1.x unit tests.)
- (void) dontTestSelfSignedSSLPinned {
    NSString* path = [[NSBundle bundleForClass: [self class]] pathForResource: @"SelfSigned" ofType: @"cer"];
    NSData* certData = [NSData dataWithContentsOfFile: path];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert);
    CBLReplicatorConfiguration* config = [self push: NO pull: YES url: @"blips://localhost:4994/beer"];
    config.pinnedServerCertificate = cert;
    [self run: config errorCode: 0 errorDomain: nil];
}


@end
