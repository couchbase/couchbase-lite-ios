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


#import <TouchDB/TDDatabase.h>
#import "TDDatabase+Attachments.h"
#import "TDDatabase+Insertion.h"
#import "TDDatabase+LocalDocs.h"
#import "TDDatabase+Replication.h"
#import "TDAttachment.h"
#import "TDBody.h"
#import <TouchDB/TDRevision.h>
#import "TDBlobStore.h"
#import "TDBase64.h"
#import "TDInternal.h"
#import "Test.h"
#import "GTMNSData+zlib.h"


#if DEBUG


static TDDatabase* createDB(void) {
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"touchdb_test.sqlite3"];
    TDDatabase *db = [TDDatabase createEmptyDBAtPath: path];
    CAssert([db open]);
    return db;
}


static NSDictionary* userProperties(NSDictionary* dict) {
    NSMutableDictionary* user = $mdict();
    for (NSString* key in dict) {
        if (![key hasPrefix: @"_"])
            user[key] = dict[key];
    }
    return user;
}


static TDRevision* putDoc(TDDatabase* db, NSDictionary* props) {
    TDRevision* rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status;
    TDRevision* result = [db putRevision: rev
                          prevRevisionID: props[@"_rev"]
                           allowConflict: NO
                                  status: &status];
    CAssert(status < 300);
    return result;
}


TestCase(TDDatabase_CRUD) {
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    
    NSString* privateUUID = db.privateUUID, *publicUUID = db.publicUUID;
    NSLog(@"DB private UUID = '%@', public = '%@'", privateUUID, publicUUID);
    CAssert(privateUUID.length >= 20, @"Invalid privateUUID: %@", privateUUID);
    CAssert(publicUUID.length >= 20, @"Invalid publicUUID: %@", publicUUID);
    
    // Make sure the database-changed notifications have the right data in them (see issue #93)
    id observer = [[NSNotificationCenter defaultCenter]
                   addObserverForName: TDDatabaseChangeNotification
                   object: db
                   queue: nil
                   usingBlock: ^(NSNotification* n) {
                       TDRevision* rev = (n.userInfo)[@"rev"];
                       CAssert(rev);
                       CAssert(rev.docID);
                       CAssert(rev.revID);
                       CAssertEqual(rev[@"_id"], rev.docID);
                       CAssertEqual(rev[@"_rev"], rev.revID);
                   }];
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"foo", @1}, {@"bar", $false});
    TDBody* doc = [[[TDBody alloc] initWithProperties: props] autorelease];
    TDRevision* rev1 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    CAssert(rev1);
    TDStatus status;
    rev1 = [db putRevision: rev1 prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    Log(@"Created: %@", rev1);
    CAssert(rev1.docID.length >= 10);
    CAssert([rev1.revID hasPrefix: @"1-"]);
    
    // Read it back:
    TDRevision* readRev = [db getDocumentWithID: rev1.docID revisionID: nil];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Now update it:
    props = [[readRev.properties mutableCopy] autorelease];
    props[@"status"] = @"updated!";
    doc = [TDBody bodyWithProperties: props];
    TDRevision* rev2 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    TDRevision* rev2Input = rev2;
    rev2 = [db putRevision: rev2 prevRevisionID: rev1.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    Log(@"Updated: %@", rev2);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getDocumentWithID: rev2.docID revisionID: nil];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    CAssertNil([db putRevision: rev2Input prevRevisionID: rev1.revID allowConflict: NO status: &status]);
    CAssertEq(status, kTDStatusConflict);
    
    // Check the changes feed, with and without filters:
    TDRevisionList* changes = [db changesSinceSequence: 0 options: NULL filter: NULL params: nil];
    Log(@"Changes = %@", changes);
    CAssertEq(changes.count, 1u);

    TDFilterBlock filter = ^BOOL(TDRevision *revision, NSDictionary* params) {
        NSString* status = params[@"status"];
        return [revision[@"status"] isEqual: status];
    };
    
    changes = [db changesSinceSequence: 0 options: NULL
                                filter: filter params: $dict({@"status", @"updated!"})];
    CAssertEq(changes.count, 1u);
    
    changes = [db changesSinceSequence: 0 options: NULL
                                filter: filter params: $dict({@"status", @"not updated!"})];
    CAssertEq(changes.count, 0u);
        
    // Delete it:
    TDRevision* revD = [[[TDRevision alloc] initWithDocID: rev2.docID revID: nil deleted: YES] autorelease];
    CAssertEq([db putRevision: revD prevRevisionID: nil allowConflict: NO status: &status], nil);
    CAssertEq(status, kTDStatusConflict);
    revD = [db putRevision: revD prevRevisionID: rev2.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(revD.docID, rev2.docID);
    CAssert([revD.revID hasPrefix: @"3-"]);
    
    // Delete nonexistent doc:
    TDRevision* revFake = [[[TDRevision alloc] initWithDocID: @"fake" revID: nil deleted: YES] autorelease];
    [db putRevision: revFake prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusNotFound);
    
    // Read it back (should fail):
    readRev = [db getDocumentWithID: revD.docID revisionID: nil];
    CAssertNil(readRev);
    
    // Check the changes feed again after the deletion:
    changes = [db changesSinceSequence: 0 options: NULL filter: NULL params: nil];
    Log(@"Changes = %@", changes);
    CAssertEq(changes.count, 1u);
    
    NSArray* history = [db getRevisionHistory: revD];
    Log(@"History = %@", history);
    CAssertEqual(history, (@[revD, rev2, rev1]));

    // Compact the database:
    CAssert([db compact] == kTDStatusOK);

    // Make sure old rev is missing:
    CAssertNil([db getDocumentWithID: rev1.docID revisionID: rev1.revID]);

    CAssert([db close]);
    
    [[NSNotificationCenter defaultCenter] removeObserver: observer];
}


TestCase(TDDatabase_EmptyDoc) {
    // Test case for issue #44, which is caused by a bug in TDJSON.
    TDDatabase* db = createDB();
    TDRevision* rev = putDoc(db, $dict());
    TDQueryOptions options = kDefaultTDQueryOptions;
    options.includeDocs = YES;
    [db getDocsWithIDs: @[rev.docID] options: &options]; // raises an exception :(
}


TestCase(TDDatabase_DeleteWithProperties) {
    // Test case for issue #50.
    // Test that it's possible to delete a document by PUTting a revision with _deleted=true,
    // and that the saved deleted revision will preserve any extra properties.
    TDDatabase* db = createDB();
    TDRevision* rev1 = putDoc(db, $dict({@"property", @"value"}));
    TDRevision* rev2 = putDoc(db, $dict({@"_id", rev1.docID},
                                        {@"_rev", rev1.revID},
                                        {@"_deleted", $true},
                                        {@"property", @"newvalue"}));
    CAssertNil([db getDocumentWithID: rev2.docID revisionID: nil]);
    TDRevision* readRev = [db getDocumentWithID: rev2.docID revisionID: rev2.revID];
    CAssert(readRev.deleted, @"PUTting a _deleted property didn't delete the doc");
    CAssertEqual(readRev.properties, $dict({@"_id", rev2.docID},
                                           {@"_rev", rev2.revID},
                                           {@"_deleted", $true},
                                           {@"property", @"newvalue"}));
}


TestCase(TDDatabase_Validation) {
    TDDatabase* db = createDB();
    __block BOOL validationCalled = NO;
    [db defineValidation: @"hoopy" 
                 asBlock: ^BOOL(TDRevision *newRevision, id<TDValidationContext> context)
    {
        CAssert(newRevision);
        CAssert(context);
        CAssert(newRevision.properties || newRevision.deleted);
        validationCalled = YES;
        BOOL hoopy = newRevision.deleted || newRevision[@"towel"] != nil;
        Log(@"--- Validating %@ --> %d", newRevision.properties, hoopy);
        if (!hoopy)
         [context setErrorMessage: @"Where's your towel?"];
        return hoopy;
    }];
    
    // POST a valid new document:
    NSMutableDictionary* props = $mdict({@"name", @"Zaphod Beeblebrox"}, {@"towel", @"velvet"});
    TDRevision* rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status;
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kTDStatusCreated);
    
    // PUT a valid update:
    props[@"head_count"] = @3;
    rev.properties = props;
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: rev.revID allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kTDStatusCreated);
    
    // PUT an invalid update:
    [props removeObjectForKey: @"towel"];
    rev.properties = props;
    validationCalled = NO;
#pragma unused (rev)  // tell analyzer to ignore dead stores below
    rev = [db putRevision: rev prevRevisionID: rev.revID allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kTDStatusForbidden);
    
    // POST an invalid new document:
    props = $mdict({@"name", @"Vogon"}, {@"poetry", $true});
    rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kTDStatusForbidden);

    // PUT a valid new document with an ID:
    props = $mdict({@"_id", @"ford"}, {@"name", @"Ford Prefect"}, {@"towel", @"terrycloth"});
    rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kTDStatusCreated);
    CAssertEqual(rev.docID, @"ford");
    
    // DELETE a document:
    rev = [[[TDRevision alloc] initWithDocID: rev.docID revID: rev.revID deleted: YES] autorelease];
    CAssert(rev.deleted);
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID:  rev.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssert(validationCalled);

    // PUT an invalid new document:
    props = $mdict({@"_id", @"petunias"}, {@"name", @"Pot of Petunias"});
    rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kTDStatusForbidden);
    
    CAssert([db close]);
}


static void verifyHistory(TDDatabase* db, TDRevision* rev, NSArray* history, bool afterCompact) {
    TDRevision* gotRev = [db getDocumentWithID: rev.docID revisionID: nil];
    CAssertEqual(gotRev, rev);
    CAssertEqual(gotRev.properties, rev.properties);
    
    NSArray* revHistory = [db getRevisionHistory: gotRev];
    CAssertEq(revHistory.count, history.count);
    for (NSUInteger i=0; i<history.count; i++) {
        TDRevision* hrev = revHistory[i];
        CAssertEqual(hrev.docID, rev.docID);
        CAssertEqual(hrev.revID, history[i]);
        CAssert(!hrev.deleted);
        CAssertEq(hrev.missing, i > 0);
    }
}


TestCase(TDDatabase_RevTree) {
    RequireTestCase(TDDatabase_CRUD);
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();

    // Track the latest database-change notification that's posted:
    __block NSDictionary* noteInfo = nil;
    id observer = [[NSNotificationCenter defaultCenter]
                   addObserverForName: TDDatabaseChangeNotification
                   object: db
                   queue: nil
                   usingBlock: ^(NSNotification *n) {
                       CAssert(!noteInfo, @"Multiple notifications posted!");
                       noteInfo = n.userInfo;
                   }];

    TDRevision* rev = [[[TDRevision alloc] initWithDocID: @"MyDocID" revID: @"4-foxy" deleted: NO] autorelease];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"hi"});
    NSArray* history = @[rev.revID, @"3-thrice", @"2-too", @"1-won"];
    noteInfo = nil;
    TDStatus status = [db forceInsert: rev revisionHistory: history source: nil];
    CAssertEq(status, kTDStatusCreated);
    CAssertEq(db.documentCount, 1u);
    verifyHistory(db, rev, history, false);
    CAssertEqual(noteInfo, (@{ @"rev" : rev, @"winner": rev }));


    TDRevision* conflict = [[[TDRevision alloc] initWithDocID: @"MyDocID" revID: @"5-epsilon" deleted: NO] autorelease];
    conflict.properties = $dict({@"_id", conflict.docID}, {@"_rev", conflict.revID},
                                {@"message", @"yo"});
    NSArray* conflictHistory = @[conflict.revID, @"4-delta", @"3-gamma", @"2-too", @"1-won"];
    noteInfo = nil;
    status = [db forceInsert: conflict revisionHistory: conflictHistory source: nil];
    CAssertEq(status, kTDStatusCreated);
    CAssertEq(db.documentCount, 1u);
    verifyHistory(db, conflict, conflictHistory, false);
    CAssertEqual(noteInfo, (@{ @"rev" : conflict, @"winner": conflict }));

    // Add an unrelated document:
    TDRevision* other = [[[TDRevision alloc] initWithDocID: @"AnotherDocID" revID: @"1-ichi" deleted: NO] autorelease];
    other.properties = $dict({@"language", @"jp"});
    noteInfo = nil;
    status = [db forceInsert: other revisionHistory: @[other.revID] source: nil];
    CAssertEq(status, kTDStatusCreated);
    CAssertEqual(noteInfo, (@{ @"rev" : other, @"winner": other }));

    // Fetch one of those phantom revisions with no body:
    TDRevision* rev2 = [db getDocumentWithID: rev.docID revisionID: @"2-too"];
    CAssertNil(rev2);
    
    // Make sure no duplicate rows were inserted for the common revisions:
    CAssertEq(db.lastSequence, 8u);
    
    // Make sure the revision with the higher revID wins the conflict:
    TDRevision* current = [db getDocumentWithID: rev.docID revisionID: nil];
    CAssertEqual(current, conflict);

    // Check that the list of conflicts is accurate:
    TDRevisionList* conflictingRevs = [db getAllRevisionsOfDocumentID: rev.docID onlyCurrent: YES];
    CAssertEqual(conflictingRevs.allRevisions, (@[conflict, rev]));

    // Get the _changes feed and verify only the winner is in it:
    TDChangesOptions options = kDefaultTDChangesOptions;
    TDRevisionList* changes = [db changesSinceSequence: 0 options: &options filter: NULL params: nil];
    CAssertEqual(changes.allRevisions, (@[conflict, other]));
    options.includeConflicts = YES;
    changes = [db changesSinceSequence: 0 options: &options filter: NULL params: nil];
    CAssertEqual(changes.allRevisions, (@[rev, conflict, other]));

    // Verify that compaction leaves the document history:
    [db compact];
    verifyHistory(db, conflict, conflictHistory, true);

    // Delete the current winning rev, leaving the other one:
    TDRevision* del1 = [[[TDRevision alloc] initWithDocID: conflict.docID revID: nil deleted: YES] autorelease];
    noteInfo = nil;
    del1 = [db putRevision: del1 prevRevisionID: conflict.revID
             allowConflict: NO status: &status];
    CAssertEq(status, 200);
    current = [db getDocumentWithID: rev.docID revisionID: nil];
    CAssertEqual(current, rev);
    CAssertEqual(noteInfo, (@{ @"rev" : del1, @"winner": rev }));
    
    verifyHistory(db, rev, history, true);

    // Delete the remaining rev:
    TDRevision* del2 = [[[TDRevision alloc] initWithDocID: rev.docID revID: nil deleted: YES] autorelease];
    noteInfo = nil;
    del2 = [db putRevision: del2 prevRevisionID: rev.revID
             allowConflict: NO status: &status];
    CAssertEq(status, 200);
    current = [db getDocumentWithID: rev.docID revisionID: nil];
    CAssertEq(current, nil);

    TDRevision* maxDel = TDCompareRevIDs(del1.revID, del2.revID) > 0 ? del1 : nil;
    CAssertEqual(noteInfo, (@{ @"rev" : del2, @"winner": maxDel }));

    [[NSNotificationCenter defaultCenter] removeObserver: observer];
}


TestCase(TDDatabase_DeterministicRevIDs) {
    TDDatabase* db = createDB();
    TDRevision* rev = putDoc(db, $dict({@"_id", @"mydoc"}, {@"key", @"value"}));
    NSString* revID = rev.revID;
    [db close];
    
    db = createDB();
    rev = putDoc(db, $dict({@"_id", @"mydoc"}, {@"key", @"value"}));
    CAssertEqual(rev.revID, revID);
}


TestCase(TDDatabase_DuplicateRev) {
    TDDatabase* db = createDB();
    TDRevision* rev1 = putDoc(db, $dict({@"_id", @"mydoc"}, {@"key", @"value"}));
    
    NSDictionary* props = $dict({@"_id", @"mydoc"},
                                {@"_rev", rev1.revID},
                                {@"key", @"new-value"});
    TDRevision* rev2a = putDoc(db, props);

    TDRevision* rev2b = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status;
    rev2b = [db putRevision: rev2b
             prevRevisionID: rev1.revID
              allowConflict: YES
                     status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rev2b, rev2a);
}


#pragma mark - ATTACHMENTS:


static void insertAttachment(TDDatabase* db, NSData* blob,
                                 SequenceNumber sequence,
                                 NSString* name, NSString* type,
                                 TDAttachmentEncoding encoding,
                                 UInt64 length, UInt64 encodedLength,
                                 unsigned revpos)
{
    TDAttachment* attachment = [[TDAttachment alloc] initWithName: name contentType: type];
    [attachment autorelease];
    CAssert([db storeBlob: blob creatingKey: &attachment->blobKey], @"Failed to store blob");
    attachment->encoding = encoding;
    attachment->length = length;
    attachment->encodedLength = encodedLength;
    attachment->revpos = revpos;
    CAssertEq([db insertAttachment: attachment forSequence: sequence], kTDStatusCreated);
}


TestCase(TDDatabase_Attachments) {
    RequireTestCase(TDDatabase_CRUD);
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    TDBlobStore* attachments = db.attachmentStore;

    CAssertEq(attachments.count, 0u);
    CAssertEqual(attachments.allKeys, @[]);
    
    // Add a revision and an attachment to it:
    TDRevision* rev1;
    TDStatus status;
    rev1 = [db putRevision: [TDRevision revisionWithProperties:$dict({@"foo", @1},
                                                                     {@"bar", $false})]
            prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    insertAttachment(db, attach1,
                     rev1.sequence,
                     @"attach", @"text/plain",
                     kTDAttachmentEncodingNone,
                     attach1.length,
                     0,
                     rev1.generation);
    
    NSString* type;
    TDAttachmentEncoding encoding;
    CAssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: &encoding status: &status], attach1);
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(type, @"text/plain");
    CAssertEq(encoding, kTDAttachmentEncodingNone);
    
    // Check the attachment dict:
    NSMutableDictionary* itemDict = $mdict({@"content_type", @"text/plain"},
                                           {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                           {@"length", @(27)},
                                           {@"stub", $true},
                                           {@"revpos", @1});
    NSDictionary* attachmentDict = $dict({@"attach", itemDict});
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: 0], attachmentDict);
    TDRevision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    CAssertEqual(gotRev1[@"_attachments"], attachmentDict);
    
    // Check the attachment dict, with attachments included:
    [itemDict removeObjectForKey: @"stub"];
    itemDict[@"data"] = [TDBase64 encode: attach1];
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: kTDIncludeAttachments], attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kTDIncludeAttachments
                             status: &status];
    CAssertEqual(gotRev1[@"_attachments"], attachmentDict);
    
    // Add a second revision that doesn't update the attachment:
    TDRevision* rev2;
    rev2 = [db putRevision: [TDRevision revisionWithProperties:$dict({@"_id", rev1.docID},
                                                                      {@"foo", @2},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev1.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    
    [db copyAttachmentNamed: @"attach" fromSequence: rev1.sequence toSequence: rev2.sequence];

    // Add a third revision of the same document:
    TDRevision* rev3;
    rev3 = [db putRevision: [TDRevision revisionWithProperties:$dict({@"_id", rev2.docID},
                                                                      {@"foo", @2},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev2.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    
    NSData* attach2 = [@"<html>And this is attach2</html>" dataUsingEncoding: NSUTF8StringEncoding];
    insertAttachment(db, attach2,
                     rev3.sequence,
                     @"attach", @"text/html",
                     kTDAttachmentEncodingNone,
                     attach2.length,
                     0,
                     rev2.generation);
    
    // Check the 2nd revision's attachment:
    type = nil;
    CAssertEqual([db getAttachmentForSequence: rev2.sequence
                                        named: @"attach"
                                         type: &type
                                     encoding: &encoding
                                       status: &status], attach1);
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(type, @"text/plain");
    CAssertEq(encoding, kTDAttachmentEncodingNone);
    
    // Check the 3rd revision's attachment:
    CAssertEqual([db getAttachmentForSequence: rev3.sequence
                                        named: @"attach"
                                         type: &type
                                     encoding: &encoding
                                       status: &status], attach2);
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(type, @"text/html");
    CAssertEq(encoding, kTDAttachmentEncodingNone);
    
    // Examine the attachment store:
    CAssertEq(attachments.count, 2u);
    NSSet* expected = [NSSet setWithObjects: [TDBlobStore keyDataForBlob: attach1],
                                             [TDBlobStore keyDataForBlob: attach2], nil];
    CAssertEqual([NSSet setWithArray: attachments.allKeys], expected);
    
    CAssertEq([db compact], kTDStatusOK);  // This clears the body of the first revision
    CAssertEq(attachments.count, 1u);
    CAssertEqual(attachments.allKeys, @[[TDBlobStore keyDataForBlob: attach2]]);
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
    NSDictionary* props = $dict({@"foo", @1},
                                {@"bar", $false},
                                {@"_attachments", attachmentDict});
    TDRevision* rev1;
    TDStatus status;
    rev1 = [db putRevision: [TDRevision revisionWithProperties: props]
            prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);

    // Examine the attachment store:
    CAssertEq(db.attachmentStore.count, 1u);
    
    // Get the revision:
    TDRevision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    attachmentDict = gotRev1[@"_attachments"];
    CAssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                         {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                                         {@"length", @(27)},
                                                         {@"stub", $true},
                                                         {@"revpos", @1})}));
    
    // Update the attachment directly:
    NSData* attachv2 = [@"Replaced body of attach" dataUsingEncoding: NSUTF8StringEncoding];
    [db updateAttachment: @"attach" body: attachv2 type: @"application/foo"
                encoding: kTDAttachmentEncodingNone
                 ofDocID: rev1.docID revID: nil
                  status: &status];
    CAssertEq(status, kTDStatusConflict);
    [db updateAttachment: @"attach" body: attachv2 type: @"application/foo"
                encoding: kTDAttachmentEncodingNone
                 ofDocID: rev1.docID revID: @"1-bogus"
                  status: &status];
    CAssertEq(status, kTDStatusConflict);
    TDRevision* rev2 = [db updateAttachment: @"attach" body: attachv2 type: @"application/foo"
                                   encoding: kTDAttachmentEncodingNone
                                    ofDocID: rev1.docID revID: rev1.revID
                                     status: &status];
    CAssertEq(status, kTDStatusCreated);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssertEq(rev2.generation, 2u);

    // Get the updated revision:
    TDRevision* gotRev2 = [db getDocumentWithID: rev2.docID revisionID: rev2.revID];
    attachmentDict = gotRev2[@"_attachments"];
    CAssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"application/foo"},
                                                         {@"digest", @"sha1-mbT3208HI3PZgbG4zYWbDW2HsPk="},
                                                         {@"length", @(23)},
                                                         {@"stub", $true},
                                                         {@"revpos", @2})}));
    
    // Delete the attachment:
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                encoding: kTDAttachmentEncodingNone
                 ofDocID: rev2.docID revID: rev2.revID
                  status: &status];
    CAssertEq(status, kTDStatusAttachmentNotFound);
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                encoding: kTDAttachmentEncodingNone
                 ofDocID: @"nosuchdoc" revID: @"nosuchrev"
                  status: &status];
    CAssertEq(status, kTDStatusNotFound);
    TDRevision* rev3 = [db updateAttachment: @"attach" body: nil type: nil
                                   encoding: kTDAttachmentEncodingNone
                                    ofDocID: rev2.docID revID: rev2.revID
                                     status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rev3.docID, rev2.docID);
    CAssertEq(rev3.generation, 3u);
    
    // Get the updated revision:
    TDRevision* gotRev3 = [db getDocumentWithID: rev3.docID revisionID: rev3.revID];
    CAssertNil([gotRev3.properties objectForKey: @"_attachments"]);
}


TestCase(TDDatabase_EncodedAttachment) {
    RequireTestCase(TDDatabase_Attachments);
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();

    // Add a revision and an attachment to it:
    TDRevision* rev1;
    TDStatus status;
    rev1 = [db putRevision: [TDRevision revisionWithProperties:$dict({@"foo", @1},
                                                                     {@"bar", $false})]
            prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusCreated);
    
    NSData* attach1 = [@"Encoded! Encoded!Encoded! Encoded! Encoded! Encoded! Encoded! Encoded!"
                            dataUsingEncoding: NSUTF8StringEncoding];
    NSData* encoded = [NSData gtm_dataByGzippingData: attach1];
    insertAttachment(db, encoded,
                     rev1.sequence,
                     @"attach", @"text/plain",
                     kTDAttachmentEncodingGZIP,
                     attach1.length,
                     encoded.length,
                     rev1.generation);
    
    // Read the attachment without decoding it:
    NSString* type;
    TDAttachmentEncoding encoding;
    CAssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: &encoding status: &status], encoded);
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(type, @"text/plain");
    CAssertEq(encoding, kTDAttachmentEncodingGZIP);
    
    // Read the attachment, decoding it:
    CAssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: NULL status: &status], attach1);
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(type, @"text/plain");
    
    // Check the stub attachment dict:
    NSMutableDictionary* itemDict = $mdict({@"content_type", @"text/plain"},
                                           {@"digest", @"sha1-fhfNE/UKv/wgwDNPtNvG5DN/5Bg="},
                                           {@"length", @(70)},
                                           {@"encoding", @"gzip"},
                                           {@"encoded_length", @(37)},
                                           {@"stub", $true},
                                           {@"revpos", @1});
    NSDictionary* attachmentDict = $dict({@"attach", itemDict});
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: 0], attachmentDict);
    TDRevision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    CAssertEqual(gotRev1[@"_attachments"], attachmentDict);

    // Check the attachment dict with encoded data:
    itemDict[@"data"] = [TDBase64 encode: encoded];
    [itemDict removeObjectForKey: @"stub"];
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence
                                          options: kTDIncludeAttachments | kTDLeaveAttachmentsEncoded],
                 attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kTDIncludeAttachments | kTDLeaveAttachmentsEncoded
                             status: &status];
    CAssertEqual(gotRev1[@"_attachments"], attachmentDict);

    // Check the attachment dict with data:
    itemDict[@"data"] = [TDBase64 encode: attach1];
    [itemDict removeObjectForKey: @"encoding"];
    [itemDict removeObjectForKey: @"encoded_length"];
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: kTDIncludeAttachments], attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kTDIncludeAttachments
                             status: &status];
    CAssertEqual(gotRev1[@"_attachments"], attachmentDict);
}


TestCase(TDDatabase_StubOutAttachmentsBeforeRevPos) {
    NSDictionary* hello = $dict({@"revpos", @1}, {@"follows", $true});
    NSDictionary* goodbye = $dict({@"revpos", @2}, {@"data", @"squeeee"});
    NSDictionary* attachments = $dict({@"hello", hello}, {@"goodbye", goodbye});
    
    TDRevision* rev = [TDRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: 3 attachmentsFollow: NO];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"stub", $true})})}));
    
    rev = [TDRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: 2 attachmentsFollow: NO];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", goodbye})}));
    
    rev = [TDRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: 1 attachmentsFollow: NO];
    CAssertEqual(rev.properties, $dict({@"_attachments", attachments}));
    
    // Now test the "follows" mode:
    rev = [TDRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: 3 attachmentsFollow: YES];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"stub", $true})})}));

    rev = [TDRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: 2 attachmentsFollow: YES];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"follows", $true})})}));
    
    rev = [TDRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: 1 attachmentsFollow: YES];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"follows", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"follows", $true})})}));
    
}


#pragma mark - MISC.:


TestCase(TDDatabase_ReplicatorSequences) {
    RequireTestCase(TDDatabase_CRUD);
    TDDatabase* db = createDB();
    CAssertNil([db lastSequenceWithCheckpointID: @"pull"]);
    [db setLastSequence: @"lastpull" withCheckpointID: @"pull"];
    CAssertEqual([db lastSequenceWithCheckpointID: @"pull"], @"lastpull");
    CAssertNil([db lastSequenceWithCheckpointID: @"push"]);
    [db setLastSequence: @"newerpull" withCheckpointID: @"pull"];
    CAssertEqual([db lastSequenceWithCheckpointID: @"pull"], @"newerpull");
    CAssertNil([db lastSequenceWithCheckpointID: @"push"]);
    [db setLastSequence: @"lastpush" withCheckpointID: @"push"];
    CAssertEqual([db lastSequenceWithCheckpointID: @"pull"], @"newerpull");
    CAssertEqual([db lastSequenceWithCheckpointID: @"push"], @"lastpush");
}


TestCase(TDDatabase_LocalDocs) {
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"_id", @"_local/doc1"},
                                        {@"foo", @1}, {@"bar", $false});
    TDBody* doc = [[[TDBody alloc] initWithProperties: props] autorelease];
    TDRevision* rev1 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    TDStatus status;
    rev1 = [db putLocalRevision: rev1 prevRevisionID: nil status: &status];
    CAssertEq(status, kTDStatusCreated);
    Log(@"Created: %@", rev1);
    CAssertEqual(rev1.docID, @"_local/doc1");
    CAssert([rev1.revID hasPrefix: @"1-"]);
    
    // Read it back:
    TDRevision* readRev = [db getLocalDocumentWithID: rev1.docID revisionID: nil];
    CAssert(readRev != nil);
    CAssertEqual(readRev[@"_id"], rev1.docID);
    CAssertEqual(readRev[@"_rev"], rev1.revID);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Now update it:
    props = [[readRev.properties mutableCopy] autorelease];
    props[@"status"] = @"updated!";
    doc = [TDBody bodyWithProperties: props];
    TDRevision* rev2 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    TDRevision* rev2Input = rev2;
    rev2 = [db putLocalRevision: rev2 prevRevisionID: rev1.revID status: &status];
    CAssertEq(status, kTDStatusCreated);
    Log(@"Updated: %@", rev2);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getLocalDocumentWithID: rev2.docID revisionID: nil];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    CAssertNil([db putLocalRevision: rev2Input prevRevisionID: rev1.revID status: &status]);
    CAssertEq(status, kTDStatusConflict);
    
    // Delete it:
    TDRevision* revD = [[[TDRevision alloc] initWithDocID: rev2.docID revID: nil deleted: YES] autorelease];
    CAssertEq([db putLocalRevision: revD prevRevisionID: nil status: &status], nil);
    CAssertEq(status, kTDStatusConflict);
    revD = [db putLocalRevision: revD prevRevisionID: rev2.revID status: &status];
    CAssertEq(status, kTDStatusOK);
    
    // Delete nonexistent doc:
    TDRevision* revFake = [[[TDRevision alloc] initWithDocID: @"_local/fake" revID: nil deleted: YES] autorelease];
    [db putLocalRevision: revFake prevRevisionID: nil status: &status];
    CAssertEq(status, kTDStatusNotFound);
    
    // Read it back (should fail):
    readRev = [db getLocalDocumentWithID: revD.docID revisionID: nil];
    CAssertNil(readRev);
    
    CAssert([db close]);
}


TestCase(TDDatabase_FindMissingRevisions) {
    TDDatabase* db = createDB();
    TDRevision* doc1r1 = putDoc(db, $dict({@"_id", @"11111"}, {@"key", @"one"}));
    TDRevision* doc2r1 = putDoc(db, $dict({@"_id", @"22222"}, {@"key", @"two"}));
    putDoc(db, $dict({@"_id", @"33333"}, {@"key", @"three"}));
    putDoc(db, $dict({@"_id", @"44444"}, {@"key", @"four"}));
    putDoc(db, $dict({@"_id", @"55555"}, {@"key", @"five"}));

    TDRevision* doc1r2 = putDoc(db, $dict({@"_id", @"11111"}, {@"_rev", doc1r1.revID}, {@"key", @"one+"}));
    TDRevision* doc2r2 = putDoc(db, $dict({@"_id", @"22222"}, {@"_rev", doc2r1.revID}, {@"key", @"two+"}));
    
    putDoc(db, $dict({@"_id", @"11111"}, {@"_rev", doc1r2.revID}, {@"_deleted", $true}));
    
    // Now call -findMissingRevisions:
    TDRevision* revToFind1 = [[[TDRevision alloc] initWithDocID: @"11111" revID: @"3-bogus" deleted: NO] autorelease];
    TDRevision* revToFind2 = [[[TDRevision alloc] initWithDocID: @"22222" revID: doc2r2.revID deleted: NO] autorelease];
    TDRevision* revToFind3 = [[[TDRevision alloc] initWithDocID: @"99999" revID: @"9-huh" deleted: NO] autorelease];
    TDRevisionList* revs = [[[TDRevisionList alloc] initWithArray: @[revToFind1, revToFind2, revToFind3]] autorelease];
    CAssert([db findMissingRevisions: revs]);
    CAssertEqual(revs.allRevisions, (@[revToFind1, revToFind3]));
    
    // Check the possible ancestors:
    CAssertEqual([db getPossibleAncestorRevisionIDs: revToFind1 limit: 0],
                 (@[doc1r2.revID, doc1r1.revID]));
    CAssertEqual([db getPossibleAncestorRevisionIDs: revToFind1 limit: 1],
                 (@[doc1r2.revID]));
    CAssertEqual([db getPossibleAncestorRevisionIDs: revToFind3 limit: 0], nil);
    
}


TestCase(TDDatabase_Purge) {
    TDDatabase* db = createDB();
    TDRevision* rev1 = putDoc(db, $dict({@"_id", @"doc"}, {@"key", @"1"}));
    TDRevision* rev2 = putDoc(db, $dict({@"_id", @"doc"}, {@"_rev", rev1.revID}, {@"key", @"2"}));
    TDRevision* rev3 = putDoc(db, $dict({@"_id", @"doc"}, {@"_rev", rev2.revID}, {@"key", @"3"}));

    // Try to purge rev2, which should fail since it's not a leaf:
    NSDictionary* toPurge = $dict({@"doc", @[rev2.revID]});
    NSDictionary* result;
    CAssertEq([db purgeRevisions: toPurge result: &result], kTDStatusOK);
    CAssertEqual(result, $dict({@"doc", @[]}));
    CAssertEq([result[@"doc"] count], 0u);

    // Purge rev3:
    toPurge = $dict({@"doc", @[rev3.revID]});
    CAssertEq([db purgeRevisions: toPurge result: &result], kTDStatusOK);
    CAssertEqual([result allKeys], @[@"doc"]);
    NSSet* purged = [NSSet setWithArray: result[@"doc"]];
    NSSet* expectedPurged = [NSSet setWithObjects: rev1.revID, rev2.revID, rev3.revID, nil];
    CAssertEqual(purged, expectedPurged);

    TDRevisionList* remainingRevs = [db getAllRevisionsOfDocumentID: @"doc" onlyCurrent: NO];
    CAssertEq(remainingRevs.count, 0u);
}


TestCase(TDDatabase) {
    RequireTestCase(TDDatabase_CRUD);
    RequireTestCase(TDDatabase_DeleteWithProperties);
    RequireTestCase(TDDatabase_RevTree);
    RequireTestCase(TDDatabase_Attachments);
    RequireTestCase(TDDatabase_PutAttachment);
    RequireTestCase(TDDatabase_EncodedAttachment);
    RequireTestCase(TDDatabase_StubOutAttachmentsBeforeRevPos);
    RequireTestCase(TDDatabase_ReplicatorSequences);
    RequireTestCase(TDDatabase_LocalDocs);
    RequireTestCase(TDDatabase_FindMissingRevisions);
    RequireTestCase(TDDatabase_Purge);
}


#endif //DEBUG
