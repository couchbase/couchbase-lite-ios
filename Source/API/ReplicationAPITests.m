//
//  ReplicationAPITests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/16/13.
//
//

#import "CouchbaseLite.h"
#import "CBLInternal.h"
#import "Test.h"


#if DEBUG


static void runReplication(CBLReplication* repl) {
    Log(@"Waiting for %@ to finish...", repl);
    bool started = false, done = false;
    [repl start];
    while (!done) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
        if (repl.running)
            started = true;
        if (started && (repl.mode == kCBLReplicationStopped ||
                        repl.mode == kCBLReplicationIdle))
            done = true;
    }
    Log(@"...replicator finished. mode=%d, progress %u/%u, error=%@",
        repl.mode, repl.completed, repl.total, repl.error);
}


TestCase(CreateReplicators) {
    NSURL* const fakeRemoteURL = [NSURL URLWithString: @"http://fake.fake/fakedb"];
    CBLManager* mgr = [CBLManager createEmptyAtTemporaryPath: @"CBL_ReplicatorTests"];
    NSError* error;
    CBLDatabase* db = [mgr createDatabaseNamed: @"db" error: &error];
    CAssert(db);

    // Create a replication:
    CAssertEqual(db.allReplications, @[]);
    CBLReplication* r1 = [db pushToURL: fakeRemoteURL];
    CAssert(r1);
    CAssertEqual(db.allReplications, @[r1]);
    CAssertEq([db pushToURL: fakeRemoteURL], r1);   // 2nd call returns same replicator instance

    // Check the replication's properties:
    CAssertEq(r1.localDatabase, db);
    CAssertEqual(r1.remoteURL, fakeRemoteURL);
    CAssert(!r1.pull);
    CAssert(!r1.persistent);
    CAssert(!r1.continuous);
    CAssert(!r1.create_target);
    CAssertNil(r1.filter);
    CAssertNil(r1.query_params);
    CAssertNil(r1.doc_ids);
    CAssertNil(r1.headers);

    // Check that the replication hasn't started running:
    CAssert(!r1.running);
    CAssertEq(r1.mode, kCBLReplicationStopped);
    CAssertEq(r1.completed, 0u);
    CAssertEq(r1.total, 0u);
    CAssertNil(r1.error);

    // Create another replication:
    CBLReplication* r2 = [db pullFromURL: fakeRemoteURL];
    CAssert(r2);
    CAssert(r2 != r1);
    CAssertEqual(db.allReplications, (@[r1, r2]));
    CAssertEq([db pullFromURL: fakeRemoteURL], r2);

    // Check the replication's properties:
    CAssertEq(r2.localDatabase, db);
    CAssertEqual(r2.remoteURL, fakeRemoteURL);
    CAssert(r2.pull);

    [mgr close];
}


TestCase(RunReplicatorWithError) {
    RequireTestCase(CreateReplicators);
    NSURL* const fakeRemoteURL = [NSURL URLWithString: @"http://couchbase.com/no_such_db"];
    CBLManager* mgr = [CBLManager createEmptyAtTemporaryPath: @"CBL_ReplicatorTests"];
    NSError* error;
    CBLDatabase* db = [mgr createDatabaseNamed: @"db" error: &error];
    CAssert(db);

    // Create a replication:
    CBLReplication* r1 = [db pullFromURL: fakeRemoteURL];
    CAssertNil(r1.document.properties);//TEMP
    runReplication(r1);

    // It should have failed with a 404:
    CAssertEq(r1.mode, kCBLReplicationStopped);
    CAssertEq(r1.completed, 0u);
    CAssertEq(r1.total, 0u);
    CAssertEqual(r1.error.domain, CBLHTTPErrorDomain);
    CAssertEq(r1.error.code, 404);
}


TestCase(API_Replicator) {
    RequireTestCase(CreateReplicators);
    RequireTestCase(RunReplicatorWithError);
}


#endif // DEBUG
