//
//  ReplicationAPITests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/16/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//

#import "CouchbaseLite.h"
#import "CBLInternal.h"
#import "Test.h"


#if DEBUG


// This db will get deleted and overwritten during every test.
#define kPushThenPullDBName @"cbl_replicator_pushpull"
#define kNDocuments 1000


static CBLDatabase* createEmptyManagerAndDb(void) {
    CBLManager* mgr = [CBLManager createEmptyAtTemporaryPath: @"CBL_ReplicatorTests"];
    NSError* error;
    CBLDatabase* db = [mgr databaseNamed: @"db" error: &error];
    CAssert(db);
    return db;
}


static void runReplication(CBLReplication* repl) {
    Log(@"Waiting for %@ to finish...", repl);
    bool started = false, done = false;
    [repl start];
    CFAbsoluteTime lastTime = 0;
    while (!done) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]])
            break;
        if (repl.running)
            started = true;
        if (started && (repl.mode == kCBLReplicationStopped ||
                        repl.mode == kCBLReplicationIdle))
            done = true;

        // Replication runs on a background thread, so the main runloop should not be blocked.
        // Make sure it's spinning in a timely manner:
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (lastTime > 0 && now-lastTime > 0.25)
            Warn(@"Runloop was blocked for %g sec", now-lastTime);
        lastTime = now;
    }
    Log(@"...replicator finished. mode=%d, progress %u/%u, error=%@",
        repl.mode, repl.completedChangesCount, repl.changesCount, repl.error);
}


TestCase(CreateReplicators) {
    NSURL* const fakeRemoteURL = [NSURL URLWithString: @"http://fake.fake/fakedb"];
    CBLDatabase* db = createEmptyManagerAndDb();

    // Create a replication:
    CAssertEqual(db.allReplications, @[]);
    CBLReplication* r1 = [db replicationToURL: fakeRemoteURL];
    CAssert(r1);
    CAssertEqual(db.allReplications, @[r1]);
    CAssertEq([db replicationToURL: fakeRemoteURL], r1);   // 2nd call returns same replicator instance

    // Check the replication's properties:
    CAssertEq(r1.localDatabase, db);
    CAssertEqual(r1.remoteURL, fakeRemoteURL);
    CAssert(!r1.pull);
    CAssert(!r1.persistent);
    CAssert(!r1.continuous);
    CAssert(!r1.createTarget);
    CAssertNil(r1.filter);
    CAssertNil(r1.filterParams);
    CAssertNil(r1.documentIDs);
    CAssertNil(r1.headers);

    // Check that the replication hasn't started running:
    CAssert(!r1.running);
    CAssertEq(r1.mode, kCBLReplicationStopped);
    CAssertEq(r1.completedChangesCount, 0u);
    CAssertEq(r1.changesCount, 0u);
    CAssertNil(r1.lastError);

    // Create another replication:
    CBLReplication* r2 = [db replicationFromURL: fakeRemoteURL];
    CAssert(r2);
    CAssert(r2 != r1);
    CAssertEqual(db.allReplications, (@[r1, r2]));
    CAssertEq([db replicationFromURL: fakeRemoteURL], r2);

    // Check the replication's properties:
    CAssertEq(r2.localDatabase, db);
    CAssertEqual(r2.remoteURL, fakeRemoteURL);
    CAssert(r2.pull);

    CBLReplication* r3 = [[CBLReplication alloc] initPullFromSourceURL: fakeRemoteURL
                                                            toDatabase: db];
    CAssert(r3 != r2);
    r3.documentIDs = @[@"doc1", @"doc2"];
    CBLStatus status;
    CBL_Replicator* repl = [db.manager replicatorWithProperties: r3.propertiesToSave
                                                         status: &status];
    AssertEqual(repl.docIDs, r3.documentIDs);
    [db.manager close];
}


TestCase(RunPushReplication) {

    RequireTestCase(CreateReplicators);
    NSURL* remoteDbURL = RemoteTestDBURL(kPushThenPullDBName);
    if (!remoteDbURL) {
        Warn(@"Skipping test RunPushReplication (no remote test DB URL)");
        return;
    }
    DeleteRemoteDB(remoteDbURL);

    Log(@"Creating %d documents...", kNDocuments);
    CBLDatabase* db = createEmptyManagerAndDb();
    [db inTransaction:^BOOL{
        for (int i = 1; i <= kNDocuments; i++) {
            @autoreleasepool {
                CBLDocument* doc = db[ $sprintf(@"doc-%d", i) ];
                NSError* error;
                [doc putProperties: @{@"index": @(i), @"bar": $false} error: &error];
                AssertNil(error);
            }
        }
        return YES;
    }];

    Log(@"Pushing...");
    CBLReplication* repl = [db replicationToURL: remoteDbURL];
    repl.createTarget = YES;
    runReplication(repl);
    AssertNil(repl.lastError);
    [db.manager close];
}


TestCase(RunPullReplication) {
    RequireTestCase(RunPushReplication);
    NSURL* remoteDbURL = RemoteTestDBURL(kPushThenPullDBName);
    if (!remoteDbURL) {
        Warn(@"Skipping test RunPullReplication (no remote test DB URL)");
        return;
    }
    CBLDatabase* db = createEmptyManagerAndDb();

    Log(@"Pulling...");
    CBLReplication* repl = [db replicationFromURL: remoteDbURL];
    runReplication(repl);
    AssertNil(repl.lastError);

    Log(@"Verifying documents...");
    for (int i = 1; i <= kNDocuments; i++) {
        CBLDocument* doc = db[ $sprintf(@"doc-%d", i) ];
        AssertEqual(doc[@"index"], @(i));
        AssertEqual(doc[@"bar"], $false);
    }
    [db.manager close];
}


TestCase(RunReplicationWithError) {
    RequireTestCase(CreateReplicators);
    NSURL* const fakeRemoteURL = [NSURL URLWithString: @"http://couchbase.com/no_such_db"];
    CBLDatabase* db = createEmptyManagerAndDb();

    // Create a replication:
    CBLReplication* r1 = [db replicationFromURL: fakeRemoteURL];
    runReplication(r1);

    // It should have failed with a 404:
    CAssertEq(r1.mode, kCBLReplicationStopped);
    CAssertEq(r1.completedChangesCount, 0u);
    CAssertEq(r1.changesCount, 0u);
    CAssertEqual(r1.lastError.domain, CBLHTTPErrorDomain);
    CAssertEq(r1.lastError.code, 404);

    [db.manager close];
}


TestCase(ReplicationChannelsProperty) {
    CBLDatabase* db = createEmptyManagerAndDb();
    NSURL* const fakeRemoteURL = [NSURL URLWithString: @"http://couchbase.com/no_such_db"];
    CBLReplication* r1 = [db replicationFromURL: fakeRemoteURL];

    CAssertNil(r1.channels);
    r1.filter = @"foo/bar";
    CAssertNil(r1.channels);
    r1.filterParams = @{@"a": @"b"};
    CAssertNil(r1.channels);

    r1.channels = nil;
    CAssertEqual(r1.filter, @"foo/bar");
    CAssertEqual(r1.filterParams, @{@"a": @"b"});

    r1.channels = @[@"NBC", @"MTV"];
    CAssertEqual(r1.channels, (@[@"NBC", @"MTV"]));
    CAssertEqual(r1.filter, @"sync_gateway/bychannel");
    CAssertEqual(r1.filterParams, @{@"channels": @"NBC,MTV"});

    r1.channels = nil;
    CAssertEqual(r1.filter, nil);
    CAssertEqual(r1.filterParams, nil);

    [db.manager close];
}


TestCase(API_Replicator) {
    RequireTestCase(CreateReplicators);
    RequireTestCase(RunReplicationWithError);
    RequireTestCase(ReplicationChannelsProperty);
    RequireTestCase(RunPushReplication);
}


#endif // DEBUG
