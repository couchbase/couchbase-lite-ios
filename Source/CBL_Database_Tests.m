//
//  CBL_Database_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.


#import "CBLDatabase.h"
#import "CBLDatabase+Attachments.h"
#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+LocalDocs.h"
#import "CBLDatabase+Replication.h"
#import "CBL_Attachment.h"
#import "CBL_Body.h"
#import "CBLRevision.h"
#import "CBLDatabaseChange.h"
#import "CBL_BlobStore.h"
#import "CBLBase64.h"
#import "CBLInternal.h"
#import "Test.h"
#import "GTMNSData+zlib.h"


#if DEBUG


static CBLDatabase* createDB(void) {
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"cbl_test.sqlite3"];
    CBLDatabase *db = [CBLDatabase createEmptyDBAtPath: path];
    CAssert([db open: nil]);
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


static CBL_Revision* putDoc(CBLDatabase* db, NSDictionary* props) {
    CBL_Revision* rev = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status;
    CBL_Revision* result = [db putRevision: rev
                           prevRevisionID: props[@"_rev"]
                            allowConflict: NO
                                   status: &status];
    CAssert(status < 300);
    CAssert(result.sequence > 0);
    CAssert(result.revID != nil);
    return result;
}


TestCase(CBL_Database_CRUD) {
    // Start with a fresh database in /tmp:
    CBLDatabase* db = createDB();
    
    NSString* privateUUID = db.privateUUID, *publicUUID = db.publicUUID;
    NSLog(@"DB private UUID = '%@', public = '%@'", privateUUID, publicUUID);
    CAssert(privateUUID.length >= 20, @"Invalid privateUUID: %@", privateUUID);
    CAssert(publicUUID.length >= 20, @"Invalid publicUUID: %@", publicUUID);
    
    // Make sure the database-changed notifications have the right data in them (see issue #93)
    id observer = [[NSNotificationCenter defaultCenter]
                   addObserverForName: CBL_DatabaseChangesNotification
                   object: db
                   queue: nil
                   usingBlock: ^(NSNotification* n) {
                       NSArray* changes = n.userInfo[@"changes"];
                       for (CBLDatabaseChange* change in changes) {
                           CBL_Revision* rev = change.addedRevision;
                           CAssert(rev);
                           CAssert(rev.docID);
                           CAssert(rev.revID);
                           CAssertEqual(rev[@"_id"], rev.docID);
                           CAssertEqual(rev[@"_rev"], rev.revID);
                       }
                   }];
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"foo", @1}, {@"bar", $false});
    CBL_Body* doc = [[CBL_Body alloc] initWithProperties: props];
    CBL_Revision* rev1 = [[CBL_Revision alloc] initWithBody: doc];
    CAssert(rev1);
    CBLStatus status;
    rev1 = [db putRevision: rev1 prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusCreated);
    Log(@"Created: %@", rev1);
    CAssert(rev1.docID.length >= 10);
    CAssert([rev1.revID hasPrefix: @"1-"]);
    
    // Read it back:
    CBL_Revision* readRev = [db getDocumentWithID: rev1.docID revisionID: nil];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Now update it:
    props = [readRev.properties mutableCopy];
    props[@"status"] = @"updated!";
    doc = [CBL_Body bodyWithProperties: props];
    CBL_Revision* rev2 = [[CBL_Revision alloc] initWithBody: doc];
    CBL_Revision* rev2Input = rev2;
    rev2 = [db putRevision: rev2 prevRevisionID: rev1.revID allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusCreated);
    Log(@"Updated: %@", rev2);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getDocumentWithID: rev2.docID revisionID: nil];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    CAssertNil([db putRevision: rev2Input prevRevisionID: rev1.revID allowConflict: NO status: &status]);
    CAssertEq(status, kCBLStatusConflict);
    
    // Check the changes feed, with and without filters:
    CBL_RevisionList* changes = [db changesSinceSequence: 0 options: NULL filter: NULL params: nil];
    Log(@"Changes = %@", changes);
    CAssertEq(changes.count, 1u);

    CBLFilterBlock filter = ^BOOL(CBLSavedRevision *revision, NSDictionary* params) {
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
    CBL_Revision* revD = [[CBL_Revision alloc] initWithDocID: rev2.docID revID: nil deleted: YES];
    CAssertEqual([db putRevision: revD prevRevisionID: nil allowConflict: NO status: &status], nil);
    CAssertEq(status, kCBLStatusConflict);
    revD = [db putRevision: revD prevRevisionID: rev2.revID allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(revD.docID, rev2.docID);
    CAssert([revD.revID hasPrefix: @"3-"]);
    
    // Delete nonexistent doc:
    CBL_Revision* revFake = [[CBL_Revision alloc] initWithDocID: @"fake" revID: nil deleted: YES];
    [db putRevision: revFake prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusNotFound);
    
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

    // Check the revision-history object (_revisions property):
    NSString* revDSuffix = [revD.revID substringFromIndex: 2];
    NSString* rev2Suffix = [rev2.revID substringFromIndex: 2];
    NSString* rev1Suffix = [rev1.revID substringFromIndex: 2];
    CAssertEqual(([db getRevisionHistoryDict: revD startingFromAnyOf: @[@"??", rev2.revID]]),
                 (@{@"ids": @[revDSuffix, rev2Suffix],
                    @"start": @3}));
    CAssertEqual(([db getRevisionHistoryDict: revD startingFromAnyOf: nil]),
                 (@{@"ids": @[revDSuffix, rev2Suffix, rev1Suffix],
                    @"start": @3}));

    // Compact the database:
    NSError* error;
    CAssert([db compact: &error]);

    // Make sure old rev is missing:
    CAssertNil([db getDocumentWithID: rev1.docID revisionID: rev1.revID]);

    CAssert([db close]);
    
    [[NSNotificationCenter defaultCenter] removeObserver: observer];
}


TestCase(CBL_Database_EmptyDoc) {
    // Test case for issue #44, which is caused by a bug in CBLJSON.
    CBLDatabase* db = createDB();
    CBL_Revision* rev = putDoc(db, $dict());
    CBLQueryOptions options = kDefaultCBLQueryOptions;
    options.includeDocs = YES;
    NSArray* keys = @[rev.docID];
    options.keys = keys;
    [db getAllDocs: &options]; // raises an exception :(
    CAssert([db close]);
}


TestCase(CBL_Database_DeleteWithProperties) {
    // Test case for issue #50.
    // Test that it's possible to delete a document by PUTting a revision with _deleted=true,
    // and that the saved deleted revision will preserve any extra properties.
    CBLDatabase* db = createDB();
    CBL_Revision* rev1 = putDoc(db, $dict({@"property", @"value"}));
    CBL_Revision* rev2 = putDoc(db, $dict({@"_id", rev1.docID},
                                        {@"_rev", rev1.revID},
                                        {@"_deleted", $true},
                                        {@"property", @"newvalue"}));
    CAssertNil([db getDocumentWithID: rev2.docID revisionID: nil]);
    CBL_Revision* readRev = [db getDocumentWithID: rev2.docID revisionID: rev2.revID];
    CAssert(readRev.deleted, @"PUTting a _deleted property didn't delete the doc");
    CAssertEqual(readRev.properties, $dict({@"_id", rev2.docID},
                                           {@"_rev", rev2.revID},
                                           {@"_deleted", $true},
                                           {@"property", @"newvalue"}));
    readRev = [db getDocumentWithID: rev2.docID revisionID: nil];
    CAssertNil(readRev);
    
    // Make sure it's possible to create the doc from scratch again:
    CBL_Revision* rev3 = putDoc(db, $dict({@"_id", rev1.docID}, {@"property", @"newvalue"}));
    CAssert([rev3.revID hasPrefix: @"3-"]);     // new rev is child of tombstone rev
    readRev = [db getDocumentWithID: rev2.docID revisionID: nil];
    CAssertEqual(readRev.revID, rev3.revID);
    CAssert([db close]);
}


TestCase(CBL_Database_DeleteAndRecreate) {
    // Test case for issue #205: Create a doc, delete it, create it again with the same content.
    CBLDatabase* db = createDB();
    CBL_Revision* rev1 = putDoc(db, $dict({@"_id", @"dock"}, {@"property", @"value"}));
    Log(@"Created: %@ -- %@", rev1, rev1.properties);
    CBL_Revision* rev2 = putDoc(db, $dict({@"_id", @"dock"}, {@"_rev", rev1.revID},
                     {@"_deleted", $true}));
    Log(@"Deleted: %@ -- %@", rev2, rev2.properties);
    CBL_Revision* rev3 = putDoc(db, $dict({@"_id", @"dock"}, {@"property", @"value"}));
    Log(@"Recreated: %@ -- %@", rev3, rev3.properties);
    CAssert([db close]);
}


static CBL_Revision* revBySettingProperties(CBL_Revision* rev, NSDictionary* properties) {
    CBL_MutableRevision* nuRev = rev.mutableCopy;
    nuRev.properties = properties;
    return nuRev;
}


TestCase(CBL_Database_Validation) {
    CBLDatabase* db = createDB();
    __block BOOL validationCalled = NO;
    [db setValidationNamed: @"hoopy" 
                 asBlock: ^BOOL(CBLSavedRevision *newRevision, id<CBLValidationContext> context)
    {
        CAssert(newRevision);
        CAssert(context);
        CAssert(newRevision.properties || newRevision.isDeletion);
        validationCalled = YES;
        BOOL hoopy = newRevision.isDeletion || newRevision[@"towel"] != nil;
        Log(@"--- Validating %@ --> %d", newRevision.properties, hoopy);
        if (!hoopy)
         [context setErrorMessage: @"Where's your towel?"];
        return hoopy;
    }];
    
    // POST a valid new document:
    NSMutableDictionary* props = $mdict({@"name", @"Zaphod Beeblebrox"}, {@"towel", @"velvet"});
    CBL_Revision* rev = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status;
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kCBLStatusCreated);
    
    // PUT a valid update:
    props[@"head_count"] = @3;
    rev = revBySettingProperties(rev, props);
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: rev.revID allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kCBLStatusCreated);
    
    // PUT an invalid update:
    [props removeObjectForKey: @"towel"];
    rev = revBySettingProperties(rev, props);
    validationCalled = NO;
#pragma unused (rev)  // tell analyzer to ignore dead stores below
    rev = [db putRevision: rev prevRevisionID: rev.revID allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kCBLStatusForbidden);
    
    // POST an invalid new document:
    props = $mdict({@"name", @"Vogon"}, {@"poetry", $true});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kCBLStatusForbidden);

    // PUT a valid new document with an ID:
    props = $mdict({@"_id", @"ford"}, {@"name", @"Ford Prefect"}, {@"towel", @"terrycloth"});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kCBLStatusCreated);
    CAssertEqual(rev.docID, @"ford");
    
    // DELETE a document:
    rev = [[CBL_Revision alloc] initWithDocID: rev.docID revID: rev.revID deleted: YES];
    CAssert(rev.deleted);
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID:  rev.revID allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusOK);
    CAssert(validationCalled);

    // PUT an invalid new document:
    props = $mdict({@"_id", @"petunias"}, {@"name", @"Pot of Petunias"});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, kCBLStatusForbidden);
    
    CAssert([db close]);
}


static void verifyHistory(CBLDatabase* db, CBL_Revision* rev, NSArray* history, bool afterCompact) {
    CBL_Revision* gotRev = [db getDocumentWithID: rev.docID revisionID: nil];
    CAssertEqual(gotRev, rev);
    CAssertEqual(gotRev.properties, rev.properties);
    
    NSArray* revHistory = [db getRevisionHistory: gotRev];
    CAssertEq(revHistory.count, history.count);
    for (NSUInteger i=0; i<history.count; i++) {
        CBL_Revision* hrev = revHistory[i];
        CAssertEqual(hrev.docID, rev.docID);
        CAssertEqual(hrev.revID, history[i]);
        CAssert(!hrev.deleted);
        CAssertEq(hrev.missing, i > 0);
    }
}


static CBLDatabaseChange* announcement(CBL_Revision* rev, CBL_Revision* winner) {
    return [[CBLDatabaseChange alloc] initWithAddedRevision: rev winningRevision: winner
                                              maybeConflict: NO source: nil];
}


TestCase(CBL_Database_RevTree) {
    RequireTestCase(CBL_Database_CRUD);
    // Start with a fresh database in /tmp:
    CBLDatabase* db = createDB();

    // Track the latest database-change notification that's posted:
    __block CBLDatabaseChange* change = nil;
    id observer = [[NSNotificationCenter defaultCenter]
                   addObserverForName: CBL_DatabaseChangesNotification
                   object: db
                   queue: nil
                   usingBlock: ^(NSNotification *n) {
                       NSArray* changes = n.userInfo[@"changes"];
                       CAssert(changes.count == 1, @"Multiple changes posted!");
                       CAssert(!change, @"Multiple notifications posted!");
                       change = changes[0];
                   }];

    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID" revID: @"4-foxy" deleted: NO];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"hi"});
    NSArray* history = @[rev.revID, @"3-thrice", @"2-too", @"1-won"];
    change = nil;
    CBLStatus status = [db forceInsert: rev revisionHistory: history source: nil];
    CAssertEq(status, kCBLStatusCreated);
    CAssertEq(db.documentCount, 1u);
    verifyHistory(db, rev, history, false);
    CAssertEqual(change, announcement(rev, rev));


    CBL_MutableRevision* conflict = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID" revID: @"5-epsilon" deleted: NO];
    conflict.properties = $dict({@"_id", conflict.docID}, {@"_rev", conflict.revID},
                                {@"message", @"yo"});
    NSArray* conflictHistory = @[conflict.revID, @"4-delta", @"3-gamma", @"2-too", @"1-won"];
    change = nil;
    status = [db forceInsert: conflict revisionHistory: conflictHistory source: nil];
    CAssertEq(status, kCBLStatusCreated);
    CAssertEq(db.documentCount, 1u);
    verifyHistory(db, conflict, conflictHistory, false);
    CAssertEqual(change, announcement(conflict, conflict));

    // Add an unrelated document:
    CBL_MutableRevision* other = [[CBL_MutableRevision alloc] initWithDocID: @"AnotherDocID" revID: @"1-ichi" deleted: NO];
    other.properties = $dict({@"language", @"jp"});
    change = nil;
    status = [db forceInsert: other revisionHistory: @[other.revID] source: nil];
    CAssertEq(status, kCBLStatusCreated);
    CAssertEqual(change, announcement(other, other));

    // Fetch one of those phantom revisions with no body:
    CBL_Revision* rev2 = [db getDocumentWithID: rev.docID revisionID: @"2-too"];
    CAssertNil(rev2);
    
    // Make sure no duplicate rows were inserted for the common revisions:
    CAssertEq(db.lastSequenceNumber, 8u);
    
    // Make sure the revision with the higher revID wins the conflict:
    CBL_Revision* current = [db getDocumentWithID: rev.docID revisionID: nil];
    CAssertEqual(current, conflict);

    // Check that the list of conflicts is accurate:
    CBL_RevisionList* conflictingRevs = [db getAllRevisionsOfDocumentID: rev.docID onlyCurrent: YES];
    CAssertEqual(conflictingRevs.allRevisions, (@[conflict, rev]));

    // Get the _changes feed and verify only the winner is in it:
    CBLChangesOptions options = kDefaultCBLChangesOptions;
    CBL_RevisionList* changes = [db changesSinceSequence: 0 options: &options filter: NULL params: nil];
    CAssertEqual(changes.allRevisions, (@[conflict, other]));
    options.includeConflicts = YES;
    changes = [db changesSinceSequence: 0 options: &options filter: NULL params: nil];
    CAssertEqual(changes.allRevisions, (@[rev, conflict, other]));

    // Verify that compaction leaves the document history:
    [db compact];
    verifyHistory(db, conflict, conflictHistory, true);

    // Delete the current winning rev, leaving the other one:
    CBL_Revision* del1 = [[CBL_Revision alloc] initWithDocID: conflict.docID revID: nil deleted: YES];
    change = nil;
    del1 = [db putRevision: del1 prevRevisionID: conflict.revID
             allowConflict: NO status: &status];
    CAssertEq(status, 200);
    current = [db getDocumentWithID: rev.docID revisionID: nil];
    CAssertEqual(current, rev);
    CAssertEqual(change, announcement(del1, rev));
    
    verifyHistory(db, rev, history, true);

    // Delete the remaining rev:
    CBL_Revision* del2 = [[CBL_Revision alloc] initWithDocID: rev.docID revID: nil deleted: YES];
    change = nil;
    del2 = [db putRevision: del2 prevRevisionID: rev.revID
             allowConflict: NO status: &status];
    CAssertEq(status, 200);
    current = [db getDocumentWithID: rev.docID revisionID: nil];
    CAssertEqual(current, nil);

    CBL_Revision* maxDel = CBLCompareRevIDs(del1.revID, del2.revID) > 0 ? del1 : nil;
    CAssertEqual(change, announcement(del2, maxDel));

    NSUInteger nPruned;
    CAssertEq([db pruneRevsToMaxDepth: 2 numberPruned: &nPruned], 200);
    CAssertEq(nPruned, 6u);
    CAssertEq([db pruneRevsToMaxDepth: 2 numberPruned: &nPruned], 200);
    CAssertEq(nPruned, 0u);

    [[NSNotificationCenter defaultCenter] removeObserver: observer];
    CAssert([db close]);
}


TestCase(CBL_Database_DeterministicRevIDs) {
    CBLDatabase* db = createDB();
    CBL_Revision* rev = putDoc(db, $dict({@"_id", @"mydoc"}, {@"key", @"value"}));
    NSString* revID = rev.revID;
    CAssert([db close]);

    db = createDB();
    rev = putDoc(db, $dict({@"_id", @"mydoc"}, {@"key", @"value"}));
    CAssertEqual(rev.revID, revID);
    CAssert([db close]);
}


TestCase(CBL_Database_DuplicateRev) {
    CBLDatabase* db = createDB();
    CBL_Revision* rev1 = putDoc(db, $dict({@"_id", @"mydoc"}, {@"key", @"value"}));
    
    NSDictionary* props = $dict({@"_id", @"mydoc"},
                                {@"_rev", rev1.revID},
                                {@"key", @"new-value"});
    CBL_Revision* rev2a = putDoc(db, props);

    CBL_Revision* rev2b = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status;
    rev2b = [db putRevision: rev2b
             prevRevisionID: rev1.revID
              allowConflict: YES
                     status: &status];
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(rev2b, rev2a);
    CAssert([db close]);
}


#pragma mark - ATTACHMENTS:


static void insertAttachment(CBLDatabase* db, NSData* blob,
                                 SequenceNumber sequence,
                                 NSString* name, NSString* type,
                                 CBLAttachmentEncoding encoding,
                                 UInt64 length, UInt64 encodedLength,
                                 unsigned revpos)
{
    CBL_Attachment* attachment = [[CBL_Attachment alloc] initWithName: name contentType: type];
    CAssert([db storeBlob: blob creatingKey: &attachment->blobKey], @"Failed to store blob");
    attachment->encoding = encoding;
    attachment->length = length;
    attachment->encodedLength = encodedLength;
    attachment->revpos = revpos;
    CAssertEq([db insertAttachment: attachment forSequence: sequence], kCBLStatusCreated);
    [db _setNoAttachments: NO forSequence: sequence];
}


TestCase(CBL_Database_Attachments) {
    RequireTestCase(CBL_Database_CRUD);
    // Start with a fresh database in /tmp:
    CBLDatabase* db = createDB();
    CBL_BlobStore* attachments = db.attachmentStore;

    CAssertEq(attachments.count, 0u);
    CAssertEqual(attachments.allKeys, @[]);
    
    // Add a revision and an attachment to it:
    CBL_Revision* rev1;
    CBLStatus status;
    rev1 = [db putRevision: [CBL_Revision revisionWithProperties:$dict({@"foo", @1},
                                                                       {@"bar", $false})]
            prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusCreated);
    CAssert(![db sequenceHasAttachments: rev1.sequence]);
    
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    insertAttachment(db, attach1,
                     rev1.sequence,
                     @"attach", @"text/plain",
                     kCBLAttachmentEncodingNone,
                     attach1.length,
                     0,
                     rev1.generation);
    
    NSString* type;
    CBLAttachmentEncoding encoding;
    CAssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: &encoding status: &status], attach1);
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(type, @"text/plain");
    CAssertEq(encoding, kCBLAttachmentEncodingNone);
    CAssert([db sequenceHasAttachments: rev1.sequence]);

    // Check the attachment dict:
    NSMutableDictionary* itemDict = $mdict({@"content_type", @"text/plain"},
                                           {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                           {@"length", @(27)},
                                           {@"stub", $true},
                                           {@"revpos", @1});
    NSDictionary* attachmentDict = $dict({@"attach", itemDict});
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: 0], attachmentDict);
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    CAssertEqual(gotRev1[@"_attachments"], attachmentDict);
    
    // Check the attachment dict, with attachments included:
    [itemDict removeObjectForKey: @"stub"];
    itemDict[@"data"] = [CBLBase64 encode: attach1];
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: kCBLIncludeAttachments], attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kCBLIncludeAttachments
                             status: &status];
    CAssertEqual(gotRev1[@"_attachments"], attachmentDict);
    
    // Add a second revision that doesn't update the attachment:
    CBL_Revision* rev2;
    rev2 = [db putRevision: [CBL_Revision revisionWithProperties:$dict({@"_id", rev1.docID},
                                                                      {@"foo", @2},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev1.revID allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusCreated);
    
    [db copyAttachmentNamed: @"attach" fromSequence: rev1.sequence toSequence: rev2.sequence];

    // Add a third revision of the same document:
    CBL_Revision* rev3;
    rev3 = [db putRevision: [CBL_Revision revisionWithProperties:$dict({@"_id", rev2.docID},
                                                                      {@"foo", @2},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev2.revID allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusCreated);
    
    NSData* attach2 = [@"<html>And this is attach2</html>" dataUsingEncoding: NSUTF8StringEncoding];
    insertAttachment(db, attach2,
                     rev3.sequence,
                     @"attach", @"text/html",
                     kCBLAttachmentEncodingNone,
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
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(type, @"text/plain");
    CAssertEq(encoding, kCBLAttachmentEncodingNone);
    
    // Check the 3rd revision's attachment:
    CAssertEqual([db getAttachmentForSequence: rev3.sequence
                                        named: @"attach"
                                         type: &type
                                     encoding: &encoding
                                       status: &status], attach2);
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(type, @"text/html");
    CAssertEq(encoding, kCBLAttachmentEncodingNone);
    
    // Examine the attachment store:
    CAssertEq(attachments.count, 2u);
    NSSet* expected = [NSSet setWithObjects: [CBL_BlobStore keyDataForBlob: attach1],
                                             [CBL_BlobStore keyDataForBlob: attach2], nil];
    CAssertEqual([NSSet setWithArray: attachments.allKeys], expected);
    
    CAssertEq([db compact], kCBLStatusOK);  // This clears the body of the first revision
    CAssertEq(attachments.count, 1u);
    CAssertEqual(attachments.allKeys, @[[CBL_BlobStore keyDataForBlob: attach2]]);
    CAssert([db close]);
}


static CBL_BlobStoreWriter* blobForData(CBLDatabase* db, NSData* data) {
    CBL_BlobStoreWriter* blob = db.attachmentWriter;
    [blob appendData: data];
    [blob finish];
    return blob;
}


TestCase(CBL_Database_PutAttachment) {
    RequireTestCase(CBL_Database_Attachments);
    // Start with a fresh database in /tmp:
    CBLDatabase* db = createDB();
    
    // Put a revision that includes an _attachments dict:
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSString* base64 = [CBLBase64 encode: attach1];
    NSDictionary* attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                           {@"data", base64})});
    NSDictionary* props = $dict({@"foo", @1},
                                {@"bar", $false},
                                {@"_attachments", attachmentDict});
    CBL_Revision* rev1;
    CBLStatus status;
    rev1 = [db putRevision: [CBL_Revision revisionWithProperties: props]
            prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusCreated);

    CAssertEqual(rev1[@"_attachments"], $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                                {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                                                {@"length", @(27)},
                                                                {@"stub", $true},
                                                                {@"revpos", @1})}));

    // Examine the attachment store:
    CAssertEq(db.attachmentStore.count, 1u);
    
    // Get the revision:
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    attachmentDict = gotRev1[@"_attachments"];
    CAssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                         {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                                         {@"length", @(27)},
                                                         {@"stub", $true},
                                                         {@"revpos", @1})}));
    
    // Update the attachment directly:
    NSData* attachv2 = [@"Replaced body of attach" dataUsingEncoding: NSUTF8StringEncoding];
    [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                    type: @"application/foo"
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev1.docID revID: nil
                  status: &status];
    CAssertEq(status, kCBLStatusConflict);
    [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                    type: @"application/foo"
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev1.docID revID: @"1-bogus"
                  status: &status];
    CAssertEq(status, kCBLStatusConflict);
    CBL_Revision* rev2 = [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                                        type: @"application/foo"
                                   encoding: kCBLAttachmentEncodingNone
                                    ofDocID: rev1.docID revID: rev1.revID
                                     status: &status];
    CAssertEq(status, kCBLStatusCreated);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssertEq(rev2.generation, 2u);

    // Get the updated revision:
    CBL_Revision* gotRev2 = [db getDocumentWithID: rev2.docID revisionID: rev2.revID];
    attachmentDict = gotRev2[@"_attachments"];
    CAssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"application/foo"},
                                                         {@"digest", @"sha1-mbT3208HI3PZgbG4zYWbDW2HsPk="},
                                                         {@"length", @(23)},
                                                         {@"stub", $true},
                                                         {@"revpos", @2})}));

    NSData* gotAttach = [db getAttachmentForSequence: gotRev2.sequence named: @"attach"
                                                type: NULL encoding: NULL status: &status];
    CAssertEqual(gotAttach, attachv2);
    
    // Delete the attachment:
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev2.docID revID: rev2.revID
                  status: &status];
    CAssertEq(status, kCBLStatusAttachmentNotFound);
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: @"nosuchdoc" revID: @"nosuchrev"
                  status: &status];
    CAssertEq(status, kCBLStatusNotFound);
    CBL_Revision* rev3 = [db updateAttachment: @"attach" body: nil type: nil
                                   encoding: kCBLAttachmentEncodingNone
                                    ofDocID: rev2.docID revID: rev2.revID
                                     status: &status];
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(rev3.docID, rev2.docID);
    CAssertEq(rev3.generation, 3u);
    
    // Get the updated revision:
    CBL_Revision* gotRev3 = [db getDocumentWithID: rev3.docID revisionID: rev3.revID];
    CAssertNil([gotRev3.properties objectForKey: @"_attachments"]);
    CAssert([db close]);
}


TestCase(CBL_Database_EncodedAttachment) {
    RequireTestCase(CBL_Database_Attachments);
    // Start with a fresh database in /tmp:
    CBLDatabase* db = createDB();

    // Add a revision and an attachment to it:
    CBL_Revision* rev1;
    CBLStatus status;
    rev1 = [db putRevision: [CBL_Revision revisionWithProperties:$dict({@"foo", @1},
                                                                     {@"bar", $false})]
            prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusCreated);
    
    NSData* attach1 = [@"Encoded! Encoded!Encoded! Encoded! Encoded! Encoded! Encoded! Encoded!"
                            dataUsingEncoding: NSUTF8StringEncoding];
    NSData* encoded = [NSData gtm_dataByGzippingData: attach1];
    insertAttachment(db, encoded,
                     rev1.sequence,
                     @"attach", @"text/plain",
                     kCBLAttachmentEncodingGZIP,
                     attach1.length,
                     encoded.length,
                     rev1.generation);
    
    // Read the attachment without decoding it:
    NSString* type;
    CBLAttachmentEncoding encoding;
    CAssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: &encoding status: &status], encoded);
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(type, @"text/plain");
    CAssertEq(encoding, kCBLAttachmentEncodingGZIP);
    
    // Read the attachment, decoding it:
    CAssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: NULL status: &status], attach1);
    CAssertEq(status, kCBLStatusOK);
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
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    CAssertEqual(gotRev1[@"_attachments"], attachmentDict);

    // Check the attachment dict with encoded data:
    itemDict[@"data"] = [CBLBase64 encode: encoded];
    [itemDict removeObjectForKey: @"stub"];
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence
                                          options: kCBLIncludeAttachments | kCBLLeaveAttachmentsEncoded],
                 attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kCBLIncludeAttachments | kCBLLeaveAttachmentsEncoded
                             status: &status];
    CAssertEqual(gotRev1[@"_attachments"], attachmentDict);

    // Check the attachment dict with data:
    itemDict[@"data"] = [CBLBase64 encode: attach1];
    [itemDict removeObjectForKey: @"encoding"];
    [itemDict removeObjectForKey: @"encoded_length"];
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: kCBLIncludeAttachments], attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kCBLIncludeAttachments
                             status: &status];
    CAssertEqual(gotRev1[@"_attachments"], attachmentDict);
    CAssert([db close]);
}


TestCase(CBL_Database_StubOutAttachmentsBeforeRevPos) {
    NSDictionary* hello = $dict({@"revpos", @1}, {@"follows", $true});
    NSDictionary* goodbye = $dict({@"revpos", @2}, {@"data", @"squeeee"});
    NSDictionary* attachments = $dict({@"hello", hello}, {@"goodbye", goodbye});
    
    CBL_MutableRevision* rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 3 attachmentsFollow: NO];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"stub", $true})})}));
    
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 2 attachmentsFollow: NO];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", goodbye})}));
    
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 1 attachmentsFollow: NO];
    CAssertEqual(rev.properties, $dict({@"_attachments", attachments}));
    
    // Now test the "follows" mode:
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 3 attachmentsFollow: YES];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"stub", $true})})}));

    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 2 attachmentsFollow: YES];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"follows", $true})})}));
    
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 1 attachmentsFollow: YES];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"follows", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"follows", $true})})}));
}


#pragma mark - MISC.:


TestCase(CBL_Database_ReplicatorSequences) {
    RequireTestCase(CBL_Database_CRUD);
    CBLDatabase* db = createDB();
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
    CAssert([db close]);
}


TestCase(CBL_Database_LocalDocs) {
    // Start with a fresh database in /tmp:
    CBLDatabase* db = createDB();
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"_id", @"_local/doc1"},
                                        {@"foo", @1}, {@"bar", $false});
    CBL_Body* doc = [[CBL_Body alloc] initWithProperties: props];
    CBL_Revision* rev1 = [[CBL_Revision alloc] initWithBody: doc];
    CBLStatus status;
    rev1 = [db putLocalRevision: rev1 prevRevisionID: nil status: &status];
    CAssertEq(status, kCBLStatusCreated);
    Log(@"Created: %@", rev1);
    CAssertEqual(rev1.docID, @"_local/doc1");
    CAssert([rev1.revID hasPrefix: @"1-"]);
    
    // Read it back:
    CBL_Revision* readRev = [db getLocalDocumentWithID: rev1.docID revisionID: nil];
    CAssert(readRev != nil);
    CAssertEqual(readRev[@"_id"], rev1.docID);
    CAssertEqual(readRev[@"_rev"], rev1.revID);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Now update it:
    props = [readRev.properties mutableCopy];
    props[@"status"] = @"updated!";
    doc = [CBL_Body bodyWithProperties: props];
    CBL_Revision* rev2 = [[CBL_Revision alloc] initWithBody: doc];
    CBL_Revision* rev2Input = rev2;
    rev2 = [db putLocalRevision: rev2 prevRevisionID: rev1.revID status: &status];
    CAssertEq(status, kCBLStatusCreated);
    Log(@"Updated: %@", rev2);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getLocalDocumentWithID: rev2.docID revisionID: nil];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    CAssertNil([db putLocalRevision: rev2Input prevRevisionID: rev1.revID status: &status]);
    CAssertEq(status, kCBLStatusConflict);
    
    // Delete it:
    CBL_Revision* revD = [[CBL_Revision alloc] initWithDocID: rev2.docID revID: nil deleted: YES];
    CAssertEqual([db putLocalRevision: revD prevRevisionID: nil status: &status], nil);
    CAssertEq(status, kCBLStatusConflict);
    revD = [db putLocalRevision: revD prevRevisionID: rev2.revID status: &status];
    CAssertEq(status, kCBLStatusOK);
    
    // Delete nonexistent doc:
    CBL_Revision* revFake = [[CBL_Revision alloc] initWithDocID: @"_local/fake" revID: nil deleted: YES];
    [db putLocalRevision: revFake prevRevisionID: nil status: &status];
    CAssertEq(status, kCBLStatusNotFound);
    
    // Read it back (should fail):
    readRev = [db getLocalDocumentWithID: revD.docID revisionID: nil];
    CAssertNil(readRev);
    
    CAssert([db close]);
}


TestCase(CBL_Database_FindMissingRevisions) {
    CBLDatabase* db = createDB();
    CBL_Revision* doc1r1 = putDoc(db, $dict({@"_id", @"11111"}, {@"key", @"one"}));
    CBL_Revision* doc2r1 = putDoc(db, $dict({@"_id", @"22222"}, {@"key", @"two"}));
    putDoc(db, $dict({@"_id", @"33333"}, {@"key", @"three"}));
    putDoc(db, $dict({@"_id", @"44444"}, {@"key", @"four"}));
    putDoc(db, $dict({@"_id", @"55555"}, {@"key", @"five"}));

    CBL_Revision* doc1r2 = putDoc(db, $dict({@"_id", @"11111"}, {@"_rev", doc1r1.revID}, {@"key", @"one+"}));
    CBL_Revision* doc2r2 = putDoc(db, $dict({@"_id", @"22222"}, {@"_rev", doc2r1.revID}, {@"key", @"two+"}));
    
    putDoc(db, $dict({@"_id", @"11111"}, {@"_rev", doc1r2.revID}, {@"_deleted", $true}));
    
    // Now call -findMissingRevisions:
    CBL_Revision* revToFind1 = [[CBL_Revision alloc] initWithDocID: @"11111" revID: @"3-bogus" deleted: NO];
    CBL_Revision* revToFind2 = [[CBL_Revision alloc] initWithDocID: @"22222" revID: doc2r2.revID deleted: NO];
    CBL_Revision* revToFind3 = [[CBL_Revision alloc] initWithDocID: @"99999" revID: @"9-huh" deleted: NO];
    CBL_RevisionList* revs = [[CBL_RevisionList alloc] initWithArray: @[revToFind1, revToFind2, revToFind3]];
    CAssert([db findMissingRevisions: revs]);
    CAssertEqual(revs.allRevisions, (@[revToFind1, revToFind3]));
    
    // Check the possible ancestors:
    BOOL hasAtt;
    CAssertEqual([db getPossibleAncestorRevisionIDs: revToFind1 limit: 0 hasAttachment: &hasAtt],
                 (@[doc1r2.revID, doc1r1.revID]));
    CAssertEq(hasAtt, NO);
    CAssertEqual([db getPossibleAncestorRevisionIDs: revToFind1 limit: 1 hasAttachment: &hasAtt],
                 (@[doc1r2.revID]));
    CAssertEq(hasAtt, NO);
    CAssertEqual([db getPossibleAncestorRevisionIDs: revToFind3 limit: 0 hasAttachment: &hasAtt],
                 nil);
    CAssertEq(hasAtt, NO);
    CAssert([db close]);
}


TestCase(CBL_Database_Purge) {
    CBLDatabase* db = createDB();
    CBL_Revision* rev1 = putDoc(db, $dict({@"_id", @"doc"}, {@"key", @"1"}));
    CBL_Revision* rev2 = putDoc(db, $dict({@"_id", @"doc"}, {@"_rev", rev1.revID}, {@"key", @"2"}));
    CBL_Revision* rev3 = putDoc(db, $dict({@"_id", @"doc"}, {@"_rev", rev2.revID}, {@"key", @"3"}));

    // Try to purge rev2, which should fail since it's not a leaf:
    NSDictionary* toPurge = $dict({@"doc", @[rev2.revID]});
    NSDictionary* result;
    CAssertEq([db purgeRevisions: toPurge result: &result], kCBLStatusOK);
    CAssertEqual(result, $dict({@"doc", @[]}));
    CAssertEq([result[@"doc"] count], 0u);

    // Purge rev3:
    toPurge = $dict({@"doc", @[rev3.revID]});
    CAssertEq([db purgeRevisions: toPurge result: &result], kCBLStatusOK);
    CAssertEqual([result allKeys], @[@"doc"]);
    NSSet* purged = [NSSet setWithArray: result[@"doc"]];
    NSSet* expectedPurged = [NSSet setWithObjects: rev1.revID, rev2.revID, rev3.revID, nil];
    CAssertEqual(purged, expectedPurged);

    CBL_RevisionList* remainingRevs = [db getAllRevisionsOfDocumentID: @"doc" onlyCurrent: NO];
    CAssertEq(remainingRevs.count, 0u);
    CAssert([db close]);
}


TestCase(CBLDatabase) {
    RequireTestCase(CBL_Database_CRUD);
    RequireTestCase(CBL_Database_DeleteWithProperties);
    RequireTestCase(CBL_Database_RevTree);
    RequireTestCase(CBL_Database_LocalDocs);
    RequireTestCase(CBL_Database_FindMissingRevisions);
    RequireTestCase(CBL_Database_Purge);
    RequireTestCase(CBL_Database_ReplicatorSequences);
    RequireTestCase(CBL_Database_Attachments);
    RequireTestCase(CBL_Database_PutAttachment);
    RequireTestCase(CBL_Database_EncodedAttachment);
    RequireTestCase(CBL_Database_StubOutAttachmentsBeforeRevPos);
}


#endif //DEBUG
