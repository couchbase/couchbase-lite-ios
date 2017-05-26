//
//  ReplicationTest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

@interface ReplicationTest : CBLTestCase <CBLReplicationDelegate>
@end


@implementation ReplicationTest
{
    CBLDatabase* otherDB;
    CBLReplication* repl;
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


- (void) push: (BOOL)push pull: (BOOL)pull {
    repl = [self.db replicationWithDatabase: otherDB];
    [self runReplicationWithPush: push pull: pull];
}


- (void) push: (BOOL)push pull: (BOOL)pull URL: (NSString*)urlStr {
    repl = [self.db replicationWithURL: [NSURL URLWithString: urlStr]];
    [self runReplicationWithPush: push pull: pull];
}


- (void) runReplicationWithPush: (BOOL)push pull: (BOOL)pull {
    Assert(repl);
    repl.push = push;
    repl.pull = pull;
    repl.delegate = self;
    XCTestExpectation *x = [self expectationForNotification: kCBLReplicationStatusChangeNotification
                                                     object: repl
                                                    handler: ^BOOL(NSNotification *n)
    {
        return repl.status.activity == kCBLStopped;
    }];
    [repl start];
    [self waitForExpectations: @[x] timeout: timeout];
}


- (void) replication: (CBLReplication*)replication
     didChangeStatus: (CBLReplicationStatus)status
{
    static const char* const kActivityNames[5] = {
        "stopped", "offline", "connecting", "idle", "busy"
    };
    NSLog(@"---Status: %s (%llu / %llu), lastError = %@",
          kActivityNames[status.activity], status.progress.completed, status.progress.total,
          replication.lastError.localizedDescription);
}


- (void) replication: (CBLReplication*)replication
    didStopWithError: (nullable NSError*)error
{
    NSLog(@"---Stopped with error: %@", error);
}



- (void) testBadURL {
    repl = [self.db replicationWithURL: [NSURL URLWithString: @"blxp://localhost/db"]];
    [self runReplicationWithPush: NO pull: YES];
    Assert(repl.lastError.code != 0);   //TODO: Get a real error code for this
}


- (void)testEmptyPush {
    [self push: YES pull: NO];
    AssertNil(repl.lastError);
}


// These test are disabled because they require a password-protected database 'seekrit' to exist
// on localhost:4984, with a user 'pupshaw' whose password is 'frank'.

- (void) dontTestAuthenticationFailure {
    repl = [self.db replicationWithURL: [NSURL URLWithString: @"blip://localhost:4984/seekrit"]];
    [self runReplicationWithPush: NO pull: YES];
    AssertEqualObjects(repl.lastError.domain, @"WebSocket");
    AssertEqual(repl.lastError.code, 401);
}


- (void) dontTestAuthenticatedPullHardcoded {
    repl = [self.db replicationWithURL: [NSURL URLWithString: @"blip://pupshaw:frank@localhost:4984/seekrit"]];
    [self runReplicationWithPush: NO pull: YES];
    AssertNil(repl.lastError);
}


- (void) dontTestAuthenticatedPull {
    repl = [self.db replicationWithURL: [NSURL URLWithString: @"blip://localhost:4984/seekrit"]];
    repl.options = @{@"auth": @{@"username": @"pupshaw", @"password": @"frank"}};
    [self runReplicationWithPush: NO pull: YES];
    AssertNil(repl.lastError);
}


- (void) dontTestMissingHost {
    repl = [self.db replicationWithURL: [NSURL URLWithString: @"blip://foo.couchbase.com/db"]];
    repl.continuous = true;
    timeout = 200;
    [self runReplicationWithPush: NO pull: YES];
    AssertNil(repl.lastError);
}

@end
