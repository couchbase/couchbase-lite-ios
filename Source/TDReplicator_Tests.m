//
//  TDPuller_Tests.m
//  TouchDB
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDPuller.h"
#import "TDPusher.h"
#import "TDReplicatorManager.h"
#import "TDServer.h"
#import "TDDatabase+Replication.h"
#import "TDDatabase+Insertion.h"
#import "TDBase64.h"
#import "TDInternal.h"
#import "Test.h"


#if DEBUG

// Change port to 59840 to test against TouchServ :)
#if TARGET_OS_IPHONE
#define kRemoteDBURLStr @"http://jens.local:5984/tdreplicator_test"
#else
#define kRemoteDBURLStr @"http://localhost:5984/tdreplicator_test"
#endif


static void deleteRemoteDB(void) {
    Log(@"Deleting %@", kRemoteDBURLStr);
    NSURL* url = [NSURL URLWithString: kRemoteDBURLStr];
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL: url
                                                       cachePolicy: NSURLRequestUseProtocolCachePolicy
                                                   timeoutInterval: 10.0];
    req.HTTPMethod = @"DELETE";
    NSURLResponse* response = nil;
    NSError* error = nil;
    [NSURLConnection sendSynchronousRequest: req returningResponse: &response error: &error];
    CAssert(error == nil || error.code == kTDStatusNotFound, @"Couldn't delete remote: %@", error);
}


static NSString* replic8(TDDatabase* db, NSString* urlStr, BOOL push,
                         NSString* lastSequence, NSString* filter) {
    NSURL* remote = [NSURL URLWithString: urlStr];
    TDReplicator* repl = [[[TDReplicator alloc] initWithDB: db remote: remote
                                                        push: push continuous: NO] autorelease];
    if (push)
        ((TDPusher*)repl).createTarget = YES;
    repl.filterName = filter;
    [repl start];
    
    CAssert(repl.running);
    Log(@"Waiting for replicator to finish...");
    while (repl.running) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
    }
    CAssert(!repl.running);
    CAssertNil(repl.error);
    Log(@"...replicator finished. lastSequence=%@", repl.lastSequence);
    return repl.lastSequence;
}


TestCase(TDPusher) {
    RequireTestCase(TDDatabase);
    TDDatabaseManager* server = [TDDatabaseManager createEmptyAtTemporaryPath: @"TDPusherTest"];
    TDDatabase* db = [server databaseNamed: @"db"];
    [db open];
    
    __block int filterCalls = 0;
    [db defineFilter: @"filter" asBlock: ^BOOL(TDRevision *revision) {
        Log(@"Test filter called on %@, properties = %@", revision, revision.properties);
        CAssert(revision.properties);
        ++filterCalls;
        return YES;
    }];
    
    deleteRemoteDB();

    // Create some documents:
    NSMutableDictionary* props = $mdict({@"_id", @"doc1"},
                                        {@"foo", $object(1)}, {@"bar", $false});
    TDStatus status;
    TDRevision* rev1 = [db putRevision: [TDRevision revisionWithProperties: props]
                        prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    
    [props setObject: rev1.revID forKey: @"_rev"];
    [props setObject: $true forKey: @"UPDATED"];
    TDRevision* rev2 = [db putRevision: [TDRevision revisionWithProperties: props]
                        prevRevisionID: rev1.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    
    props = $mdict({@"_id", @"doc2"},
                   {@"baz", $object(666)}, {@"fnord", $true});
    [db putRevision: [TDRevision revisionWithProperties: props]
                        prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
#pragma unused(rev2)
    
    // Push them to the remote:
    id lastSeq = replic8(db, kRemoteDBURLStr, YES, nil, @"filter");
    CAssertEqual(lastSeq, @"3");
    CAssertEq(filterCalls, 2);
    
    [db close];
    [server close];
}


TestCase(TDPuller) {
    RequireTestCase(TDPusher);
    TDDatabaseManager* server = [TDDatabaseManager createEmptyAtTemporaryPath: @"TDPullerTest"];
    TDDatabase* db = [server databaseNamed: @"db"];
    [db open];
    
    id lastSeq = replic8(db, kRemoteDBURLStr, NO, nil, nil);
    CAssert($equal(lastSeq, @"2") || $equal(lastSeq, @"3"), @"Unexpected lastSeq '%@'", lastSeq);
    
    CAssertEq(db.documentCount, 2u);
    CAssertEq(db.lastSequence, 3);
    
    replic8(db, kRemoteDBURLStr, NO, lastSeq, nil);
    CAssertEq(db.lastSequence, 3);
    
    TDRevision* doc = [db getDocumentWithID: @"doc1" revisionID: nil options: 0];
    CAssert(doc);
    CAssert([doc.revID hasPrefix: @"2-"]);
    CAssertEqual([doc.properties objectForKey: @"foo"], $object(1));
    
    doc = [db getDocumentWithID: @"doc2" revisionID: nil options: 0];
    CAssert(doc);
    CAssert([doc.revID hasPrefix: @"1-"]);
    CAssertEqual([doc.properties objectForKey: @"fnord"], $true);

    [db close];
    [server close];
}


TestCase(TDPuller_FromCouchApp) {
    /** This test case requires that there be an empty CouchApp installed on a local CouchDB server, in a database named "couchapp_helloworld". To keep the test from breaking for most people, I've disabled it unless you're me :) If you want to run this test, just delete the lines below. */
    if (!$equal(NSUserName(), @"snej")) {
        Log(@"Skipping TDPuller_FromCouchApp test");
        return;
    }
    
    RequireTestCase(TDPuller);
    TDDatabaseManager* server = [TDDatabaseManager createEmptyAtTemporaryPath: @"TDPuller_FromCouchApp"];
    TDDatabase* db = [server databaseNamed: @"couchapp_helloworld"];
    [db open];
    
    replic8(db, @"http://127.0.0.1:5984/couchapp_helloworld", NO, nil, nil);
    
    TDRevision* rev = [db getDocumentWithID: @"_design/helloworld" revisionID: nil options: kTDIncludeAttachments];
    NSDictionary* attachments = [rev.properties objectForKey: @"_attachments"];
    CAssertEq(attachments.count, 10u);
    [attachments enumerateKeysAndObjectsUsingBlock:^(NSString* name, NSDictionary* attachment, BOOL *stop) {
        NSData* data = [TDBase64 decode: [attachment objectForKey: @"data"]];
        Log(@"Attachment %@: %u bytes", name, data.length);
        CAssert(data);
        CAssertEq([data length], [[attachment objectForKey: @"length"] unsignedLongLongValue]);
    }];
    [db close];
    [server close];
}


TestCase(TDReplicatorManager) {
    TDDatabaseManager* server = [TDDatabaseManager createEmptyAtTemporaryPath: @"TDReplicatorManagerTest"];
    CAssert([server replicatorManager]);    // start the replicator
    TDDatabase* replicatorDb = [server databaseNamed: kTDReplicatorDatabaseName];
    CAssert(replicatorDb);
    CAssert([replicatorDb open]);
    
    // Try some bogus validation docs that will fail the validator function:
    TDRevision* rev = [TDRevision revisionWithProperties: $dict({@"source", @"foo"},
                                                                {@"target", $object(7)})];
#pragma unused (rev) // some of the 'rev=' assignments below are unnecessary
    TDStatus status;
    rev = [replicatorDb putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusForbidden);

    rev = [TDRevision revisionWithProperties: $dict({@"source", @"foo"},
                                                    {@"target", @"http://foo.com"},
                                                    {@"_internal", $true})];
    rev = [replicatorDb putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusForbidden);
    
    TDDatabase* sourceDB = [server databaseNamed: @"foo"];
    CAssert([sourceDB open]);

    // Now try a valid replication document:
    NSURL* remote = [NSURL URLWithString: @"http://localhost:5984/tdreplicator_test"];
    rev = [TDRevision revisionWithProperties: $dict({@"source", @"foo"},
                                                    {@"target", remote.absoluteString})];
    rev = [replicatorDb putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    
    // Get back the document and verify it's been updated with replicator properties:
    TDRevision* newRev = [replicatorDb getDocumentWithID: rev.docID revisionID: nil options: 0];
    Log(@"Updated doc = %@", newRev.properties);
    CAssert(!$equal(newRev.revID, rev.revID), @"Replicator doc wasn't updated");
    NSString* sessionID = [newRev.properties objectForKey: @"_replication_id"];
    CAssert([sessionID length] >= 10);
    CAssertEqual([newRev.properties objectForKey: @"_replication_state"], @"triggered");
    CAssert([[newRev.properties objectForKey: @"_replication_state_time"] longLongValue] >= 1000);
    
    // Check that a TDReplicator exists:
    TDReplicator* repl = [sourceDB activeReplicatorWithRemoteURL: remote push: YES];
    CAssert(repl);
    CAssertEqual(repl.sessionID, sessionID);
    CAssert(repl.running);
    
    // Delete the _replication_state property:
    NSMutableDictionary* updatedProps = [[newRev.properties mutableCopy] autorelease];
    [updatedProps removeObjectForKey: @"_replication_state"];
    rev = [TDRevision revisionWithProperties: updatedProps];
    rev = [replicatorDb putRevision: rev prevRevisionID: rev.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);

    // Get back the document and verify it's been updated with replicator properties:
    newRev = [replicatorDb getDocumentWithID: rev.docID revisionID: nil options: 0];
    Log(@"Updated doc = %@", newRev.properties);
    sessionID = [newRev.properties objectForKey: @"_replication_id"];
    CAssert([sessionID length] >= 10);
    CAssertEqual([newRev.properties objectForKey: @"_replication_state"], @"triggered");
    CAssert([[newRev.properties objectForKey: @"_replication_state_time"] longLongValue] >= 1000);
    
    // Check that this restarted the replicator:
    TDReplicator* newRepl = [sourceDB activeReplicatorWithRemoteURL: remote push: YES];
    CAssert(newRepl);
    CAssert(newRepl != repl);
    CAssertEqual(newRepl.sessionID, sessionID);
    CAssert(newRepl.running);

    // Now delete it:
    rev = [[[TDRevision alloc] initWithDocID: newRev.docID revID: newRev.revID deleted: YES] autorelease];
    rev = [replicatorDb putRevision: rev prevRevisionID: rev.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusOK);
    [server close];
}

#endif
