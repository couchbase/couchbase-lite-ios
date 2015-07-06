//
//  P2P_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 7/6/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLSyncListener.h"
#import "CBLManager+Internal.h"


#define kPort 59999
#define kListenerDBName @"listy"
#define kNDocuments 1000


@interface P2P_Tests : CBLTestCaseWithDB
@end


@implementation P2P_Tests
{
    CBLSyncListener* listener;
    CBLDatabase* listenerDB;
    NSURL* listenerDBURL;
}


- (void) setUp {
    [super setUp];

    dbmgr.replicatorClassName = @"CBLBlipReplicator";

    listenerDB = [dbmgr databaseNamed: kListenerDBName error: NULL];
    listenerDBURL = [NSURL URLWithString: $sprintf(@"ws://localhost:%d/%@", kPort, kListenerDBName)];

    listener = [[CBLSyncListener alloc] initWithManager: dbmgr port: kPort];
    // Wait for listener to start:
    [self keyValueObservingExpectationForObject: listener keyPath: @"port" expectedValue: @(kPort)];
    [listener start: NULL];
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
}


- (void) tearDown {
    [listener stop];
    [super tearDown];
}


- (void) testPush {
    [self createDocsIn: db];
    Log(@"Pushing...");
    CBLReplication* repl = [db createPushReplication: listenerDBURL];
    [self runReplication: repl expectedChangesCount: kNDocuments];
    [self verifyDocsIn: listenerDB];
}


- (void) testPull {
    [self createDocsIn: listenerDB];
    Log(@"Pulling...");
    CBLReplication* repl = [db createPullReplication: listenerDBURL];
    [self runReplication: repl expectedChangesCount: kNDocuments];
    [self verifyDocsIn: db];
}


- (void) createDocsIn: (CBLDatabase*)database {
    Log(@"Creating %d documents in %@...", kNDocuments, database.name);
    [database inTransaction:^BOOL{
        for (int i = 1; i <= kNDocuments; i++) {
            @autoreleasepool {
                CBLDocument* doc = database[ $sprintf(@"doc-%d", i) ];
                NSError* error;
                [doc putProperties: @{@"index": @(i), @"bar": $false} error: &error];
                AssertNil(error);
            }
        }
        return YES;
    }];
}

- (void) verifyDocsIn: (CBLDatabase*)database {
    for (int i = 1; i <= kNDocuments; i++) {
        CBLDocument* doc = database[ $sprintf(@"doc-%d", i) ];
        AssertEqual(doc.properties[@"index"], @(i));
        AssertEqual(doc.properties[@"bar"], $false);
    }
    AssertEq(database.documentCount, (unsigned)kNDocuments);
}


- (void) runReplication: (CBLReplication*)repl
   expectedChangesCount: (NSUInteger)expectedChangesCount
{
    [repl start];
    __block bool started = false;
    [self expectationForNotification: kCBLReplicationChangeNotification object: repl
                             handler: ^BOOL(NSNotification *n) {
                                 Log(@"Repl running=%d, status=%d", repl.running, repl.status);
                                 if (repl.running)
                                     started = true;
                                 if (repl.lastError)
                                     return true;
                                 return started && (repl.status == kCBLReplicationStopped ||
                                                    repl.status == kCBLReplicationIdle);
                             }];
    [self waitForExpectationsWithTimeout: 30.0 handler: nil];
    AssertNil(repl.lastError);
    if (expectedChangesCount > 0) {
        AssertEq(repl.changesCount, expectedChangesCount);
    }
}


@end
