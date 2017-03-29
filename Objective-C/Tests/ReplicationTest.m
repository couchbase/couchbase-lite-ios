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
    BOOL _stopped;
}


- (void)setUp {
    [super setUp];
    otherDB = [self openDBNamed: @"otherdb"];
}


- (void) push: (BOOL)push pull: (BOOL)pull {
    repl = [self.db replicationWithDatabase: otherDB];
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
    [self waitForExpectations: @[x] timeout: 5.0];
}


- (void) replication: (CBLReplication*)replication
     didChangeStatus: (CBLReplicationStatus)status
{
    NSLog(@"replication:didChangestatus:");
}


- (void) replication: (CBLReplication*)replication
    didStopWithError: (nullable NSError*)error
{
    NSLog(@"replication:didStopWithError:");
}



- (void)testEmptyPush {
    [self push: YES pull: NO];
}

@end
