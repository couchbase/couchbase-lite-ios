//
//  TDDatabase_Tests.m
//  TouchDB
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.


#import "TDDatabase.h"
#import "TDBody.h"
#import "TDRevision.h"
#import "TDBlobStore.h"
#import "TDBase64.h"
#import "TDInternal.h"
#import "Test.h"



#if DEBUG


NSString* kPath = @"/tmp/touchdb_test.sqlite3";


static TDDatabase* createDB(void) {
    TDDatabase *db = [TDDatabase createEmptyDBAtPath: kPath];
    CAssert([db open]);
    return db;
}


static NSDictionary* userProperties(NSDictionary* dict) {
    NSMutableDictionary* user = $mdict();
    for (NSString* key in dict) {
        if (![key hasPrefix: @"_"])
            [user setObject: [dict objectForKey: key] forKey: key];
    }
    return user;
}

TestCase(TDDatabase_CRUD) {
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"foo", $object(1)}, {@"bar", $false});
    TDBody* doc = [[[TDBody alloc] initWithProperties: props] autorelease];
    TDRevision* rev1 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    TDStatus status;
    rev1 = [db putRevision: rev1 prevRevisionID: nil status: &status];
    CAssertEq(status, 201);
    Log(@"Created: %@", rev1);
    CAssert(rev1.docID.length >= 10);
    CAssert([rev1.revID hasPrefix: @"1-"]);
    
    // Read it back:
    TDRevision* readRev = [db getDocumentWithID: rev1.docID revisionID: nil options: 0];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Now update it:
    props = [[readRev.properties mutableCopy] autorelease];
    [props setObject: @"updated!" forKey: @"status"];
    doc = [TDBody bodyWithProperties: props];
    TDRevision* rev2 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    TDRevision* rev2Input = rev2;
    rev2 = [db putRevision: rev2 prevRevisionID: rev1.revID status: &status];
    CAssertEq(status, 201);
    Log(@"Updated: %@", rev2);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getDocumentWithID: rev2.docID revisionID: nil options: 0];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    CAssertNil([db putRevision: rev2Input prevRevisionID: rev1.revID status: &status]);
    CAssertEq(status, 409);
    
    // Check the changes feed, with and without filters:
    TDRevisionList* changes = [db changesSinceSequence: 0 options: NULL filter: NULL];
    Log(@"Changes = %@", changes);
    CAssertEq(changes.count, 1u);
    
    changes = [db changesSinceSequence: 0 options: NULL filter:^BOOL(TDRevision *revision) {
        return [[revision.properties objectForKey: @"status"] isEqual: @"updated!"];
    }];
    CAssertEq(changes.count, 1u);
    
    changes = [db changesSinceSequence: 0 options: NULL filter:^BOOL(TDRevision *revision) {
        return [[revision.properties objectForKey: @"status"] isEqual: @"not updated!"];
    }];
    CAssertEq(changes.count, 0u);
        
    // Delete it:
    TDRevision* revD = [[[TDRevision alloc] initWithDocID: rev2.docID revID: nil deleted: YES] autorelease];
    CAssertEq([db putRevision: revD prevRevisionID: nil status: &status], nil);
    CAssertEq(status, 409);
    revD = [db putRevision: revD prevRevisionID: rev2.revID status: &status];
    CAssertEq(status, 200);
    CAssertEqual(revD.docID, rev2.docID);
    CAssert([revD.revID hasPrefix: @"3-"]);
    
    // Delete nonexistent doc:
    TDRevision* revFake = [[[TDRevision alloc] initWithDocID: @"fake" revID: nil deleted: YES] autorelease];
    [db putRevision: revFake prevRevisionID: nil status: &status];
    CAssertEq(status, 404);
    
    // Read it back (should fail):
    readRev = [db getDocumentWithID: revD.docID revisionID: nil options: 0];
    CAssertNil(readRev);
    
    // Check the changes feed again after the deletion:
    changes = [db changesSinceSequence: 0 options: NULL filter: NULL];
    Log(@"Changes = %@", changes);
    CAssertEq(changes.count, 1u);
    
    NSArray* history = [db getRevisionHistory: revD];
    Log(@"History = %@", history);
    CAssertEqual(history, $array(revD, rev2, rev1));
    
    CAssert([db close]);
}


static void verifyHistory(TDDatabase* db, TDRevision* rev, NSArray* history) {
    TDRevision* gotRev = [db getDocumentWithID: rev.docID revisionID: nil options: 0];
    CAssertEqual(gotRev, rev);
    CAssertEqual(gotRev.properties, rev.properties);
    
    NSArray* revHistory = [db getRevisionHistory: gotRev];
    CAssertEq(revHistory.count, history.count);
    for (NSUInteger i=0; i<history.count; i++) {
        TDRevision* hrev = [revHistory objectAtIndex: i];
        CAssertEqual(hrev.docID, rev.docID);
        CAssertEqual(hrev.revID, [history objectAtIndex: i]);
        CAssert(!hrev.deleted);
    }
}


TestCase(TDDatabase_RevTree) {
    RequireTestCase(TDDatabase_CRUD);
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    
    TDRevision* rev = [[[TDRevision alloc] initWithDocID: @"MyDocID" revID: @"4-foxy" deleted: NO] autorelease];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"hi"});
    NSArray* history = $array(rev.revID, @"3-thrice", @"2-too", @"1-won");
    TDStatus status = [db forceInsert: rev revisionHistory: history source: nil];
    CAssertEq(status, 201);
    CAssertEq(db.documentCount, 1u);
    verifyHistory(db, rev, history);
    
    TDRevision* conflict = [[[TDRevision alloc] initWithDocID: @"MyDocID" revID: @"5-epsilon" deleted: NO] autorelease];
    conflict.properties = $dict({@"_id", conflict.docID}, {@"_rev", conflict.revID},
                                {@"message", @"yo"});
    history = $array(conflict.revID, @"4-delta", @"3-gamma", @"2-too", @"1-won");
    status = [db forceInsert: conflict revisionHistory: history source: nil];
    CAssertEq(status, 201);
    CAssertEq(db.documentCount, 1u);
    verifyHistory(db, conflict, history);
    
    // Add an unrelated document:
    TDRevision* other = [[[TDRevision alloc] initWithDocID: @"AnotherDocID" revID: @"1-ichi" deleted: NO] autorelease];
    other.properties = $dict({@"language", @"jp"});
    status = [db forceInsert: other revisionHistory: $array(other.revID) source: nil];
    CAssertEq(status, 201);
    
    // Fetch one of those phantom revisions with no body:
    TDRevision* rev2 = [db getDocumentWithID: rev.docID revisionID: @"2-too" options: 0];
    CAssertEqual(rev2.docID, rev.docID);
    CAssertEqual(rev2.revID, @"2-too");
    //CAssertEqual(rev2.body, nil);
    
    // Make sure no duplicate rows were inserted for the common revisions:
    CAssertEq(db.lastSequence, 8u);
    
    // Make sure the revision with the higher revID wins the conflict:
    TDRevision* current = [db getDocumentWithID: rev.docID revisionID: nil options: 0];
    CAssertEqual(current, conflict);
    
    // Get the _changes feed and verify only the winner is in it:
    TDChangesOptions options = kDefaultTDChangesOptions;
    TDRevisionList* changes = [db changesSinceSequence: 0 options: &options filter: NULL];
    CAssertEqual(changes.allRevisions, $array(conflict, other));
    options.includeConflicts = YES;
    changes = [db changesSinceSequence: 0 options: &options filter: NULL];
    CAssertEqual(changes.allRevisions, $array(rev, conflict, other));
}


TestCase(TDDatabase_Attachments) {
    RequireTestCase(TDDatabase_CRUD);
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    TDBlobStore* attachments = db.attachmentStore;

    CAssertEq(attachments.count, 0u);
    CAssertEqual(attachments.allKeys, $array());
    
    // Add a revision and an attachment to it:
    TDRevision* rev1;
    TDStatus status;
    rev1 = [db putRevision: [TDRevision revisionWithProperties:$dict({@"foo", $object(1)},
                                                                     {@"bar", $false})]
            prevRevisionID: nil status: &status];
    CAssertEq(status, 201);
    
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    CAssert([db insertAttachment: attach1 forSequence: rev1.sequence
                           named: @"attach" type: @"text/plain"
                          revpos: rev1.generation]);
    
    NSString* type;
    CAssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type status: &status], attach1);
    CAssertEq(status, 200);
    CAssertEqual(type, @"text/plain");
    
    // Check the attachment dict:
    NSMutableDictionary* itemDict = $mdict({@"content_type", @"text/plain"},
                                           {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                           {@"length", $object(27)},
                                           {@"stub", $true},
                                           {@"revpos", $object(1)});
    NSDictionary* attachmentDict = $dict({@"attach", itemDict});
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence withContent: NO], attachmentDict);
    TDRevision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                                options: 0];
    CAssertEqual([gotRev1.properties objectForKey: @"_attachments"], attachmentDict);
    
    // Check the attachment dict, with attachments included:
    [itemDict removeObjectForKey: @"stub"];
    [itemDict setObject: [TDBase64 encode: attach1] forKey: @"data"];
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence withContent: YES], attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kTDIncludeAttachments];
    CAssertEqual([gotRev1.properties objectForKey: @"_attachments"], attachmentDict);
    
    // Add a second revision that doesn't update the attachment:
    TDRevision* rev2;
    rev2 = [db putRevision: [TDRevision revisionWithProperties:$dict({@"_id", rev1.docID},
                                                                      {@"foo", $object(2)},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev1.revID status: &status];
    CAssertEq(status, 201);
    
    [db copyAttachmentNamed: @"attach" fromSequence: rev1.sequence toSequence: rev2.sequence];

    // Add a third revision of the same document:
    TDRevision* rev3;
    rev3 = [db putRevision: [TDRevision revisionWithProperties:$dict({@"_id", rev2.docID},
                                                                      {@"foo", $object(2)},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev2.revID status: &status];
    CAssertEq(status, 201);
    
    NSData* attach2 = [@"<html>And this is attach2</html>" dataUsingEncoding: NSUTF8StringEncoding];
    CAssert([db insertAttachment: attach2 forSequence: rev3.sequence
                           named: @"attach" type: @"text/html" revpos: rev2.generation]);
    
    // Check the 2nd revision's attachment:
    type = nil;
    CAssertEqual([db getAttachmentForSequence: rev2.sequence
                                        named: @"attach"
                                         type: &type
                                       status: &status], attach1);
    CAssertEq(status, 200);
    CAssertEqual(type, @"text/plain");
    
    // Check the 3rd revision's attachment:
    CAssertEqual([db getAttachmentForSequence: rev3.sequence
                                        named: @"attach"
                                         type: &type
                                       status: &status], attach2);
    CAssertEq(status, 200);
    CAssertEqual(type, @"text/html");
    
    // Examine the attachment store:
    CAssertEq(attachments.count, 2u);
    NSSet* expected = [NSSet setWithObjects: [TDBlobStore keyDataForBlob: attach1],
                                             [TDBlobStore keyDataForBlob: attach2], nil];
    CAssertEqual([NSSet setWithArray: attachments.allKeys], expected);
    
    CAssertEq([db compact], 200);  // This clears the body of the first revision
    CAssertEq(attachments.count, 1u);
    CAssertEqual(attachments.allKeys, $array([TDBlobStore keyDataForBlob: attach2]));
}


TestCase(TDDatabase_PutAttachment) {
    RequireTestCase(TDDatabase_Attachments);
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    
    // Put a revision that includes an _attachments dict:
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSString* base64 = [TDBase64 encode: attach1];
    NSDictionary* attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                           {@"data", base64})});
    NSDictionary* props = $dict({@"foo", $object(1)},
                                {@"bar", $false},
                                {@"_attachments", attachmentDict});
    TDRevision* rev1;
    TDStatus status;
    rev1 = [db putRevision: [TDRevision revisionWithProperties: props]
            prevRevisionID: nil status: &status];
    CAssertEq(status, 201);

    // Examine the attachment store:
    CAssertEq(db.attachmentStore.count, 1u);
    
    // Get the revision:
    TDRevision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                                options: 0];
    attachmentDict = [gotRev1.properties objectForKey: @"_attachments"];
    CAssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                         {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                                         {@"length", $object(27)},
                                                         {@"stub", $true},
                                                         {@"revpos", $object(1)})}));
    
    // Update the attachment directly:
    NSData* attachv2 = [@"Replaced body of attach" dataUsingEncoding: NSUTF8StringEncoding];
    [db updateAttachment: @"attach" body: attachv2 type: @"application/foo"
                 ofDocID: rev1.docID revID: nil
                  status: &status];
    CAssertEq(status, 409);
    [db updateAttachment: @"attach" body: attachv2 type: @"application/foo"
                 ofDocID: rev1.docID revID: @"1-bogus"
                  status: &status];
    CAssertEq(status, 409);
    TDRevision* rev2 = [db updateAttachment: @"attach" body: attachv2 type: @"application/foo"
                                    ofDocID: rev1.docID revID: rev1.revID
                                     status: &status];
    CAssertEq(status, 201);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssertEq(rev2.generation, 2u);

    // Get the updated revision:
    TDRevision* gotRev2 = [db getDocumentWithID: rev2.docID revisionID: rev2.revID
                                        options: 0];
    attachmentDict = [gotRev2.properties objectForKey: @"_attachments"];
    CAssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"application/foo"},
                                                         {@"digest", @"sha1-mbT3208HI3PZgbG4zYWbDW2HsPk="},
                                                         {@"length", $object(23)},
                                                         {@"stub", $true},
                                                         {@"revpos", $object(2)})}));
    
    // Delete the attachment:
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                 ofDocID: rev2.docID revID: rev2.revID
                  status: &status];
    CAssertEq(status, 404);
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                 ofDocID: @"nosuchdoc" revID: @"nosuchrev"
                  status: &status];
    CAssertEq(status, 404);
    TDRevision* rev3 = [db updateAttachment: @"attach" body: nil type: nil
                                    ofDocID: rev2.docID revID: rev2.revID
                                     status: &status];
    CAssertEq(status, 200);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssertEq(rev2.generation, 2u);
    
    // Get the updated revision:
    TDRevision* gotRev3 = [db getDocumentWithID: rev3.docID revisionID: rev3.revID
                                        options: 0];
    CAssertNil([gotRev3.properties objectForKey: @"_attachments"]);
}


TestCase(TDDatabase_ReplicatorSequences) {
    RequireTestCase(TDDatabase_CRUD);
    TDDatabase* db = createDB();
    NSURL* remote = [NSURL URLWithString: @"http://iriscouch.com/"];
    CAssertNil([db lastSequenceWithRemoteURL: remote push: NO]);
    CAssertNil([db lastSequenceWithRemoteURL: remote push: YES]);
    [db setLastSequence: @"lastpull" withRemoteURL: remote push: NO];
    CAssertEqual([db lastSequenceWithRemoteURL: remote push: NO], @"lastpull");
    CAssertNil([db lastSequenceWithRemoteURL: remote push: YES]);
    [db setLastSequence: @"newerpull" withRemoteURL: remote push: NO];
    CAssertEqual([db lastSequenceWithRemoteURL: remote push: NO], @"newerpull");
    CAssertNil([db lastSequenceWithRemoteURL: remote push: YES]);
    [db setLastSequence: @"lastpush" withRemoteURL: remote push: YES];
    CAssertEqual([db lastSequenceWithRemoteURL: remote push: NO], @"newerpull");
    CAssertEqual([db lastSequenceWithRemoteURL: remote push: YES], @"lastpush");
}


TestCase(TDDatabase) {
    RequireTestCase(TDDatabase_CRUD);
    RequireTestCase(TDDatabase_RevTree);
    RequireTestCase(TDDatabase_Attachments);
    RequireTestCase(TDDatabase_PutAttachment);
    RequireTestCase(TDDatabase_ReplicatorSequences);
}


#endif //DEBUG
