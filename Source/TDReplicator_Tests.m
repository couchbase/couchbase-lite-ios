//
//  TDReplicator_Tests.m
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
#import "TD_Server.h"
#import "TD_Database+Replication.h"
#import "TD_Database+Insertion.h"
#import "TDOAuth1Authorizer.h"
#import "TDBase64.h"
#import "TDInternal.h"
#import "Test.h"
#import "MYURLUtils.h"


#if DEBUG

// Change port to 59840 to test against TouchServ :)
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
#define kRemoteDBURLStr @"http://jens.local:5984/tdreplicator_test"
#else
#define kRemoteDBURLStr @"http://127.0.0.1:5984/tdreplicator_test"
#endif


static id<TDAuthorizer> authorizer(void) {
#if 1
    return nil;
#else
    NSURLCredential* cred = [NSURLCredential credentialWithUser: @"XXXX" password: @"XXXX"
                                                    persistence:NSURLCredentialPersistenceNone];
    return [[[TDBasicAuthorizer alloc] initWithCredential: cred] autorelease];
#endif
}


static void deleteRemoteDB(void) {
    Log(@"Deleting %@", kRemoteDBURLStr);
    NSURL* url = [NSURL URLWithString: kRemoteDBURLStr];
    __block NSError* error = nil;
    __block BOOL finished = NO;
    TDRemoteRequest* request = [[TDRemoteRequest alloc] initWithMethod: @"DELETE"
                                                                   URL: url
                                                                  body: nil
                                                        requestHeaders: nil
                                                          onCompletion:
        ^(id result, NSError *err) {
            finished = YES;
            error = err;
        }
                                ];
    request.authorizer = authorizer();
    [request start];
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10];
    while (!finished && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                                 beforeDate: timeout])
        ;
    CAssert(error == nil || error.code == kTDStatusNotFound, @"Couldn't delete remote: %@", error);
}


static NSString* replic8(TD_Database* db, NSString* urlStr, BOOL push, NSString* filter) {
    NSURL* remote = [NSURL URLWithString: urlStr];
    TDReplicator* repl = [[TDReplicator alloc] initWithDB: db remote: remote
                                                        push: push continuous: NO];
    if (push)
        ((TDPusher*)repl).createTarget = YES;
    repl.filterName = filter;
    repl.authorizer = authorizer();
    [repl start];
    
    CAssert(repl.running);
    Log(@"Waiting for replicator to finish...");
    while (repl.running || repl.savingCheckpoint) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
    }
    CAssert(!repl.running);
    CAssert(!repl.savingCheckpoint);
    CAssertNil(repl.error);
    Log(@"...replicator finished. lastSequence=%@", repl.lastSequence);
    return repl.lastSequence;
}


TestCase(TDPusher) {
    RequireTestCase(TD_Database);
    TD_DatabaseManager* server = [TD_DatabaseManager createEmptyAtTemporaryPath: @"TDPusherTest"];
    TD_Database* db = [server databaseNamed: @"db"];
    [db open];
    
    __block int filterCalls = 0;
    [db defineFilter: @"filter" asBlock: ^BOOL(TD_Revision *revision, NSDictionary* params) {
        Log(@"Test filter called with params = %@", params);
        Log(@"Rev = %@, properties = %@", revision, revision.properties);
        CAssert(revision.properties);
        ++filterCalls;
        return YES;
    }];
    
    deleteRemoteDB();

    // Create some documents:
    NSMutableDictionary* props = $mdict({@"_id", @"doc1"},
                                        {@"foo", @1}, {@"bar", $false});
    TDStatus status;
    TD_Revision* rev1 = [db putRevision: [TD_Revision revisionWithProperties: props]
                        prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    
    props[@"_rev"] = rev1.revID;
    props[@"UPDATED"] = $true;
    TD_Revision* rev2 = [db putRevision: [TD_Revision revisionWithProperties: props]
                        prevRevisionID: rev1.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    
    props = $mdict({@"_id", @"doc2"},
                   {@"baz", @(666)}, {@"fnord", $true});
    [db putRevision: [TD_Revision revisionWithProperties: props]
                        prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
#pragma unused(rev2)
    
    // Push them to the remote:
    id lastSeq = replic8(db, kRemoteDBURLStr, YES, @"filter");
    CAssertEqual(lastSeq, @"3");
    CAssertEq(filterCalls, 2);
    
    [db close];
    [server close];
}


TestCase(TDPuller) {
    RequireTestCase(TDPusher);
    TD_DatabaseManager* server = [TD_DatabaseManager createEmptyAtTemporaryPath: @"TDPullerTest"];
    TD_Database* db = [server databaseNamed: @"db"];
    [db open];
    
    id lastSeq = replic8(db, kRemoteDBURLStr, NO, nil);
    CAssertEqual(lastSeq, @"2");
    
    CAssertEq(db.documentCount, 2u);
    CAssertEq(db.lastSequence, 3);
    
    // Replicate again; should complete but add no revisions:
    Log(@"Second replication, should get no more revs:");
    replic8(db, kRemoteDBURLStr, NO, nil);
    CAssertEq(db.lastSequence, 3);
    
    TD_Revision* doc = [db getDocumentWithID: @"doc1" revisionID: nil];
    CAssert(doc);
    CAssert([doc.revID hasPrefix: @"2-"]);
    CAssertEqual(doc[@"foo"], @1);
    
    doc = [db getDocumentWithID: @"doc2" revisionID: nil];
    CAssert(doc);
    CAssert([doc.revID hasPrefix: @"1-"]);
    CAssertEqual(doc[@"fnord"], $true);

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
    TD_DatabaseManager* server = [TD_DatabaseManager createEmptyAtTemporaryPath: @"TDPuller_FromCouchApp"];
    TD_Database* db = [server databaseNamed: @"couchapp_helloworld"];
    [db open];
    
    replic8(db, @"http://127.0.0.1:5984/couchapp_helloworld", NO, nil);

    TDStatus status;
    TD_Revision* rev = [db getDocumentWithID: @"_design/helloworld" revisionID: nil options: kTDIncludeAttachments status: &status];
    NSDictionary* attachments = rev[@"_attachments"];
    CAssertEq(attachments.count, 10u);
    for (NSString* name in attachments) { 
        NSDictionary* attachment = attachments[name];
        NSData* data = [TDBase64 decode: attachment[@"data"]];
        Log(@"Attachment %@: %u bytes", name, (unsigned)data.length);
        CAssert(data);
        CAssertEq([data length], [attachment[@"length"] unsignedLongLongValue]);
    }
    [db close];
    [server close];
}


TestCase(TDReplicatorManager) {
    RequireTestCase(ParseReplicatorProperties);
    TD_DatabaseManager* server = [TD_DatabaseManager createEmptyAtTemporaryPath: @"TDReplicatorManagerTest"];
    CAssert([server replicatorManager]);    // start the replicator
    TD_Database* replicatorDb = [server databaseNamed: kTDReplicatorDatabaseName];
    CAssert(replicatorDb);
    CAssert([replicatorDb open]);
    
    // Try some bogus validation docs that will fail the validator function:
    TD_Revision* rev = [TD_Revision revisionWithProperties: $dict({@"source", @"foo"},
                                                                {@"target", @7})];
#pragma unused (rev) // some of the 'rev=' assignments below are unnecessary
    TDStatus status;
    rev = [replicatorDb putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusForbidden);

    rev = [TD_Revision revisionWithProperties: $dict({@"source", @"foo"},
                                                    {@"target", @"http://foo.com"},
                                                    {@"_internal", $true})];  // <--illegal prop
    rev = [replicatorDb putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusForbidden);
    
    TD_Database* sourceDB = [server databaseNamed: @"foo"];
    CAssert([sourceDB open]);

    // Now try a valid replication document:
    NSURL* remote = [NSURL URLWithString: @"http://localhost:5984/tdreplicator_test"];
    rev = [TD_Revision revisionWithProperties: $dict({@"source", @"foo"},
                                                    {@"target", remote.absoluteString})];
    rev = [replicatorDb putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    
    // Get back the document and verify it's been updated with replicator properties:
    TD_Revision* newRev = [replicatorDb getDocumentWithID: rev.docID revisionID: nil];
    Log(@"Updated doc = %@", newRev.properties);
    CAssert(!$equal(newRev.revID, rev.revID), @"Replicator doc wasn't updated");
    NSString* sessionID = newRev[@"_replication_id"];
    CAssert([sessionID length] >= 10);
    CAssertEqual(newRev[@"_replication_state"], @"triggered");
    CAssert([newRev[@"_replication_state_time"] longLongValue] >= 1000);
    
    // Check that a TDReplicator exists:
    TDReplicator* repl = [sourceDB activeReplicatorWithRemoteURL: remote push: YES];
    CAssert(repl);
    CAssertEqual(repl.sessionID, sessionID);
    CAssert(repl.running);
    
    // Delete the _replication_state property:
    NSMutableDictionary* updatedProps = [newRev.properties mutableCopy];
    [updatedProps removeObjectForKey: @"_replication_state"];
    rev = [TD_Revision revisionWithProperties: updatedProps];
    rev = [replicatorDb putRevision: rev prevRevisionID: rev.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);

    // Get back the document and verify it's been updated with replicator properties:
    newRev = [replicatorDb getDocumentWithID: rev.docID revisionID: nil];
    Log(@"Updated doc = %@", newRev.properties);
    sessionID = newRev[@"_replication_id"];
    CAssert([sessionID length] >= 10);
    CAssertEqual(newRev[@"_replication_state"], @"triggered");
    CAssert([newRev[@"_replication_state_time"] longLongValue] >= 1000);
    
    // Check that this restarted the replicator:
    TDReplicator* newRepl = [sourceDB activeReplicatorWithRemoteURL: remote push: YES];
    CAssert(newRepl);
    CAssert(newRepl != repl);
    CAssertEqual(newRepl.sessionID, sessionID);
    CAssert(newRepl.running);

    // Now delete the database, and check that the replication doc is deleted too:
    CAssert([server deleteDatabaseNamed: @"foo"]);
    CAssertNil([replicatorDb getDocumentWithID: rev.docID revisionID: nil]);
    
    [server close];
}


TestCase(ParseReplicatorProperties) {
    TD_DatabaseManager* dbManager = [TD_DatabaseManager createEmptyAtTemporaryPath: @"TDReplicatorManagerTest"];
    TDReplicatorManager* replManager = [dbManager replicatorManager];
    TD_Database* localDB = [dbManager databaseNamed: @"foo"];

    TD_Database* db = nil;
    NSURL* remote = nil;
    BOOL isPush = NO, createTarget = NO;
    NSDictionary* headers = nil;
    
    NSDictionary* props;
    props = $dict({@"source", @"foo"},
                  {@"target", @"http://example.com"},
                  {@"create_target", $true});
    CAssertEq(200, [replManager parseReplicatorProperties: props
                                               toDatabase: &db
                                                   remote: &remote
                                                   isPush: &isPush
                                             createTarget: &createTarget
                                                  headers: &headers
                                               authorizer: NULL]);
    CAssertEq(db, localDB);
    CAssertEqual(remote, $url(@"http://example.com"));
    CAssertEq(isPush, YES);
    CAssertEq(createTarget, YES);
    CAssertEqual(headers, nil);
    
    props = $dict({@"source", @"touchdb:///foo"},
                  {@"target", @"foo"});
    CAssertEq(200, [replManager parseReplicatorProperties: props
                                               toDatabase: &db
                                                   remote: &remote
                                                   isPush: &isPush
                                             createTarget: &createTarget
                                                  headers: &headers
                                               authorizer: NULL]);
    CAssertEq(db, localDB);
    CAssertEqual(remote, $url(@"touchdb:///foo"));
    CAssertEq(isPush, NO);
    CAssertEq(createTarget, NO);
    CAssertEqual(headers, nil);
    
    NSDictionary* oauthDict = $dict({@"consumer_secret", @"consumer_secret"},
                                    {@"consumer_key", @"consumer_key"},
                                    {@"token_secret", @"token_secret"},
                                    {@"token", @"token"});
    props = $dict({@"source", $dict({@"url", @"http://example.com"},
                                    {@"headers", $dict({@"Excellence", @"Most"})},
                                    {@"auth", $dict({@"oauth", oauthDict})})},
                  {@"target", @"foo"});
    id<TDAuthorizer> authorizer = nil;
    CAssertEq(200, [replManager parseReplicatorProperties: props
                                               toDatabase: &db
                                                   remote: &remote
                                                   isPush: &isPush
                                             createTarget: &createTarget
                                                  headers: &headers
                                               authorizer: &authorizer]);
    CAssertEq(db, localDB);
    CAssertEqual(remote, $url(@"http://example.com"));
    CAssertEq(isPush, NO);
    CAssertEq(createTarget, NO);
    CAssertEqual(headers, $dict({@"Excellence", @"Most"}));
    CAssert([authorizer isKindOfClass: [TDOAuth1Authorizer class]]);
    
    [dbManager close];
}

#endif
