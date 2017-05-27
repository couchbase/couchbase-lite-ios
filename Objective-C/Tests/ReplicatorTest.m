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
    CBLReplicatorTarget* target = [CBLReplicatorTarget database: otherDB];
    return [self push: push pull: pull target: target];
}


- (CBLReplicatorConfiguration*) push: (BOOL)push pull: (BOOL)pull url: (NSString*)url {
    CBLReplicatorTarget* target = [CBLReplicatorTarget url: [NSURL URLWithString: url]];
    return [self push: push pull: pull target: target];
}


- (CBLReplicatorConfiguration*) push: (BOOL)push
                                pull: (BOOL)pull
                              target: (CBLReplicatorTarget*)target
{
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] init];
    config.database = self.db;
    config.target = target;
    config.replicatorType = push && pull ? kCBLPushAndPull : (push ? kCBLPush : kCBLPull);
    return config;
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
    config.options = @{@"auth": @{@"username": @"pupshaw", @"password": @"frank"}};
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestMissingHost {
    timeout = 200;
    CBLReplicatorConfiguration* config = [self push: NO pull: YES url: @"blip://foo.couchbase.com/db"];
    config.continuous = YES;
    [self run: config errorCode: 0 errorDomain: nil];
}

@end
