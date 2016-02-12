//
//  DatabaseInternal_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/22/14.
//
//

#import "CBLTestCase.h"
#import "CBLDatabase.h"
#import "CBLDatabase+Attachments.h"
#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+Replication.h"
#import "CBL_Storage.h"
#import "CBLDatabaseUpgrade.h"
#import "CBL_Attachment.h"
#import "CBL_Body.h"
#import "CBLRevision.h"
#import "CBLDatabaseChange.h"
#import "CBL_BlobStore.h"
#import "CBLBase64.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "CBLGZip.h"


static NSDictionary* userProperties(NSDictionary* dict) {
    NSMutableDictionary* user = $mdict();
    for (NSString* key in dict) {
        if (![key hasPrefix: @"_"])
            user[key] = dict[key];
    }
    return user;
}


@interface DatabaseInternal_Tests : CBLTestCaseWithDB
@end


@implementation DatabaseInternal_Tests


- (CBL_Revision*) putDoc: (NSDictionary*) props {
    CBL_Revision* rev = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status;
    NSError* error;
    CBL_Revision* result = [db putRevision: [rev mutableCopy]
                            prevRevisionID: props[@"_rev"]
                             allowConflict: NO
                                    status: &status
                                     error: &error];
    Assert(status < 300, @"Status %d from putRevision: (reason: %@)",
           status, error.localizedFailureReason);
    Assert(result.revID != nil);
    return result;
}


- (void) test01_CRUD {
    NSString* privateUUID = db.privateUUID, *publicUUID = db.publicUUID;
    NSLog(@"DB private UUID = '%@', public = '%@'", privateUUID, publicUUID);
    Assert(privateUUID.length >= 20, @"Invalid privateUUID: %@", privateUUID);
    Assert(publicUUID.length >= 20, @"Invalid publicUUID: %@", publicUUID);
    
    // Make sure the database-changed notifications have the right data in them (see issue #93)
    id observer = [[NSNotificationCenter defaultCenter]
                   addObserverForName: CBL_DatabaseChangesNotification
                   object: db
                   queue: nil
                   usingBlock: ^(NSNotification* n) {
                       NSArray* changes = n.userInfo[@"changes"];
                       for (CBLDatabaseChange* change in changes) {
                           CBL_Revision* rev = change.addedRevision;
                           Assert(rev);
                           Assert(rev.docID);
                           Assert(rev.revID);
                       }
                   }];

    // Get a nonexistent document:
    CBLStatus status;
    AssertNil([db getDocumentWithID: @"nonexistent" revisionID: nil withBody: YES status: &status]);
    AssertEq(status, kCBLStatusNotFound);
    
    // Create a document:
    NSError* error;
    NSMutableDictionary* props = $mdict({@"foo", @1}, {@"bar", $false});
    CBL_Body* doc = [[CBL_Body alloc] initWithProperties: props];
    CBL_Revision* rev1 = [[CBL_Revision alloc] initWithBody: doc];
    Assert(rev1);
    rev1 = [db putRevision: [rev1 mutableCopy] prevRevisionID: nil allowConflict: NO
                    status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
    Log(@"Created: %@", rev1);
    Assert(rev1.docID.length >= 10);
    Assert([rev1.revID hasPrefix: @"1-"]);
    
    // Read it back:
    CBL_Revision* readRev = [db getDocumentWithID: rev1.docID revisionID: nil];
    Assert(readRev != nil);
    AssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Now update it:
    props = [readRev.properties mutableCopy];
    props[@"status"] = @"updated!";
    doc = [CBL_Body bodyWithProperties: props];
    CBL_Revision* rev2 = [[CBL_Revision alloc] initWithBody: doc];
    CBL_Revision* rev2Input = rev2;
    rev2 = [db putRevision: [rev2 mutableCopy] prevRevisionID: rev1.revID allowConflict: NO
                    status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
    Log(@"Updated: %@", rev2);
    AssertEqual(rev2.docID, rev1.docID);
    Assert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getDocumentWithID: rev2.docID revisionID: nil];
    Assert(readRev != nil);
    AssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    AssertNil([db putRevision: [rev2Input mutableCopy] prevRevisionID: rev1.revID allowConflict: NO
                       status: &status error: &error]);
    AssertEq(status, kCBLStatusConflict);
    AssertEq(error.code, kCBLStatusConflict);

    // Check the changes feed, with and without filters:
    CBL_RevisionList* changes = [db changesSinceSequence: 0 options: NULL filter: NULL params: nil status: &status];
    Log(@"Changes = %@", changes);
    AssertEq(changes.count, 1u);

    CBLFilterBlock filter = ^BOOL(CBLSavedRevision *revision, NSDictionary* params) {
        NSString* status = params[@"status"];
        return [revision[@"status"] isEqual: status];
    };
    
    changes = [db changesSinceSequence: 0 options: NULL
                                filter: filter params: $dict({@"status", @"updated!"}) status: &status];
    AssertEq(changes.count, 1u);
    
    changes = [db changesSinceSequence: 0 options: NULL
                                filter: filter params: $dict({@"status", @"not updated!"}) status: &status];
    AssertEq(changes.count, 0u);
        
    // Delete it:
    error = nil;
    CBL_Revision* revD = [[CBL_Revision alloc] initWithDocID: rev2.docID revID: nil deleted: YES];
    AssertEqual([db putRevision: [revD mutableCopy] prevRevisionID: nil allowConflict: NO
                         status: &status error: &error], nil);
    AssertEq(status, kCBLStatusConflict);

    error = nil;
    revD = [db putRevision: [revD mutableCopy] prevRevisionID: rev2.revID allowConflict: NO
                    status: &status error: &error];
    AssertEq(status, kCBLStatusOK);
    AssertNil(error);
    AssertEqual(revD.docID, rev2.docID);
    Assert([revD.revID hasPrefix: @"3-"]);

    // Read the deletion revision:
    readRev = [db getDocumentWithID: revD.docID revisionID: revD.revID];
    Assert(readRev);
    Assert(readRev.deleted);
    AssertEqual(readRev.revID, revD.revID);

    // Delete nonexistent doc:
    error = nil;
    CBL_Revision* revFake = [[CBL_Revision alloc] initWithDocID: @"fake" revID: nil deleted: YES];
    [db putRevision: [revFake mutableCopy] prevRevisionID: nil allowConflict: NO
             status: &status error: &error];
    AssertEq(status, kCBLStatusNotFound);
    AssertEq(error.code, kCBLStatusNotFound);

    // Read it back (should fail):
    readRev = [db getDocumentWithID: revD.docID revisionID: nil];
    AssertNil(readRev);
    
    // Check the changes feed again after the deletion:
    changes = [db changesSinceSequence: 0 options: NULL filter: NULL params: nil status: &status];
    Log(@"Changes = %@", changes);
    AssertEq(changes.count, 1u);
    
    NSArray* history = [db getRevisionHistory: revD backToRevIDs: nil];
    Log(@"History = %@", history);
    AssertEqual(history, (@[revD, rev2, rev1]));

    // Check the revision-history object (_revisions property):
    NSString* revDSuffix = [revD.revID substringFromIndex: 2];
    NSString* rev2Suffix = [rev2.revID substringFromIndex: 2];
    NSString* rev1Suffix = [rev1.revID substringFromIndex: 2];
    history = [db getRevisionHistory: revD backToRevIDs: @[@"??", rev2.revID]];
    AssertEqual([CBLDatabase makeRevisionHistoryDict: history],
                 (@{@"ids": @[revDSuffix, rev2Suffix],
                    @"start": @3}));
    history = [db getRevisionHistory: revD backToRevIDs: nil];
    AssertEqual([CBLDatabase makeRevisionHistoryDict: history],
                 (@{@"ids": @[revDSuffix, rev2Suffix, rev1Suffix],
                    @"start": @3}));

    // Read rev 1 again:
    readRev = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    Assert(readRev != nil);
    AssertEqual(userProperties(readRev.properties), userProperties(rev1.properties));

    // Compact the database:
    error = nil;
    Assert([db compact: &error]);

    // Make sure old rev is missing:
    AssertNil([db getDocumentWithID: rev1.docID revisionID: rev1.revID]);

    [[NSNotificationCenter defaultCenter] removeObserver: observer];
}


- (void) test02_EmptyDoc {
    // Test case for issue #44, which is caused by a bug in CBLJSON.
    CBL_Revision* rev = [self putDoc: $dict()];
    CBLQueryOptions *options = [CBLQueryOptions new];
    options->includeDocs = YES;
    NSArray* keys = @[rev.docID];
    options.keys = keys;
    CBLStatus status;
    NSEnumerator* iterator = [db getAllDocs: options status: &status];
    Assert(iterator);
    while (iterator.nextObject) {
    }
}


- (void) test02_ExpectedRevIDs {
    // It's not strictly required that revisions always generate the same revIDs, but it helps
    // prevent false conflicts when two peers make the same change to the same parent revision.
    CBL_Revision* rev1 = [self putDoc: $dict({@"_id", @"doc"}, {@"property", @"value"})];
    AssertEqual(rev1.revID, @"1-0f9219c8f699b156f1f86242b0c8e350");
    CBL_Revision* rev2 = [self putDoc: $dict({@"_id", rev1.docID},
                                             {@"_rev", rev1.revID},
                                             {@"property", @"newvalue"})];
    AssertEqual(rev2.revID, @"2-59284737f6f209344495057ac5007606");
    CBL_Revision* rev3 = [self putDoc: $dict({@"_id", rev2.docID},
                                             {@"_rev", rev2.revID},
                                             {@"_deleted", @YES})];
    AssertEqual(rev3.revID, @"3-fff64159f36e69ecaf4395e153efe969");
}


- (void) test03_DeleteWithProperties {
    // Test case for issue #50.
    // Test that it's possible to delete a document by PUTting a revision with _deleted=true,
    // and that the saved deleted revision will preserve any extra properties.
    CBL_Revision* rev1 = [self putDoc: $dict({@"property", @"value"})];
    CBL_Revision* rev2 = [self putDoc: $dict({@"_id", rev1.docID},
                                        {@"_rev", rev1.revID},
                                        {@"_deleted", $true},
                                        {@"property", @"newvalue"})];
    AssertNil([db getDocumentWithID: rev2.docID revisionID: nil]);
    CBL_Revision* readRev = [db getDocumentWithID: rev2.docID revisionID: rev2.revID];
    Assert(readRev.deleted, @"PUTting a _deleted property didn't delete the doc");
    AssertEqual(readRev.properties, $dict({@"_id", rev2.docID},
                                           {@"_rev", rev2.revID},
                                           {@"_deleted", $true},
                                           {@"property", @"newvalue"}));
    readRev = [db getDocumentWithID: rev2.docID revisionID: nil];
    AssertNil(readRev);
    
    // Make sure it's possible to create the doc from scratch again:
    CBL_Revision* rev3 = [self putDoc: $dict({@"_id", rev1.docID}, {@"property", @"newvalue"})];
    Assert([rev3.revID hasPrefix: @"3-"]);     // new rev is child of tombstone rev
    readRev = [db getDocumentWithID: rev2.docID revisionID: nil];
    AssertEqual(readRev.revID, rev3.revID);
}


- (void) test04_DeleteAndRecreate {
    // Test case for issue #205: Create a doc, delete it, create it again with the same content.
    CBL_Revision* rev1 = [self putDoc: $dict({@"_id", @"dock"}, {@"property", @"value"})];
    Log(@"Created: %@ -- %@", rev1, rev1.properties);
    CBL_Revision* rev2 = [self putDoc: $dict({@"_id", @"dock"}, {@"_rev", rev1.revID},
                     {@"_deleted", $true})];
    Log(@"Deleted: %@ -- %@", rev2, rev2.properties);
    CBL_Revision* rev3 = [self putDoc: $dict({@"_id", @"dock"}, {@"property", @"value"})];
    Log(@"Recreated: %@ -- %@", rev3, rev3.properties);
}


static CBL_Revision* revBySettingProperties(CBL_Revision* rev, NSDictionary* properties) {
    CBL_MutableRevision* nuRev = rev.mutableCopy;
    nuRev.properties = properties;
    return nuRev;
}


- (void) test05_Validation {
    __block BOOL validationCalled = NO;
    __block NSString* expectedParentRevID = nil;
    __weak DatabaseInternal_Tests* weakSelf = self;
    [db setValidationNamed: @"hoopy" 
                 asBlock: ^void(CBLRevision *newRevision, id<CBLValidationContext> context)
    {
        DatabaseInternal_Tests* self = weakSelf; // avoid warning about ref cycles from Assert
        Assert(newRevision);
        Assert(context);
        Assert(newRevision.properties || newRevision.isDeletion);
        validationCalled = YES;
        BOOL hoopy = newRevision.isDeletion || newRevision[@"towel"] != nil;
        Log(@"--- Validating %@ --> %d", newRevision.properties, hoopy);
        if (!hoopy)
            [context rejectWithMessage: @"Where's your towel?"];
        AssertEqual(newRevision.parentRevisionID, expectedParentRevID);
    }];
    
    // POST a valid new document:
    NSMutableDictionary* props = $mdict({@"name", @"Zaphod Beeblebrox"}, {@"towel", @"velvet"});
    CBL_Revision* rev = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status;
    NSError* error;
    validationCalled = NO;
    expectedParentRevID = nil;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: nil allowConflict: NO
                   status: &status error: &error];
    Assert(validationCalled);
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);

    // PUT a valid update:
    props[@"head_count"] = @3;
    rev = revBySettingProperties(rev, props);
    validationCalled = NO;
    expectedParentRevID = rev.revID;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: rev.revID allowConflict: NO
                   status: &status error: &error];
    Assert(validationCalled);
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);

    // PUT an invalid update:
    [props removeObjectForKey: @"towel"];
    rev = revBySettingProperties(rev, props);
    validationCalled = NO;
    expectedParentRevID = rev.revID;
#pragma unused(rev)
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: rev.revID allowConflict: NO
                   status: &status error: &error];
    Assert(validationCalled);
    AssertEq(status, kCBLStatusForbidden);
    AssertEq(error.code, kCBLStatusForbidden);
    AssertEqual(error.localizedDescription, @"403 Where's your towel?");


    // POST an invalid new document:
    props = $mdict({@"name", @"Vogon"}, {@"poetry", $true});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    validationCalled = NO;
    expectedParentRevID = nil;
    error = nil;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: nil allowConflict: NO
                   status: &status error: &error];
    Assert(validationCalled);
    AssertEq(status, kCBLStatusForbidden);
    AssertEq(error.code, kCBLStatusForbidden);
    AssertEqual(error.localizedDescription, @"403 Where's your towel?");

    // PUT a valid new document with an ID:
    props = $mdict({@"_id", @"ford"}, {@"name", @"Ford Prefect"}, {@"towel", @"terrycloth"});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    validationCalled = NO;
    error = nil;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: nil allowConflict: NO
                   status: &status error: &error];
    Assert(validationCalled);
    expectedParentRevID = nil;
    AssertEq(status, kCBLStatusCreated);
    AssertEqual(rev.docID, @"ford");
    AssertNil(error);
    
    // DELETE a document:
    rev = [[CBL_Revision alloc] initWithDocID: rev.docID revID: rev.revID deleted: YES];
    Assert(rev.deleted);
    validationCalled = NO;
    expectedParentRevID = rev.revID;
    error = nil;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: rev.revID allowConflict: NO
                   status: &status error: &error];
    AssertEq(status, kCBLStatusOK);
    Assert(validationCalled);
    AssertNil(error);

    // PUT an invalid new document:
    props = $mdict({@"_id", @"petunias"}, {@"name", @"Pot of Petunias"});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    validationCalled = NO;
    expectedParentRevID = nil;
    error = nil;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: nil allowConflict: NO
                   status: &status error: &error];
    Assert(validationCalled);
    AssertEq(status, kCBLStatusForbidden);
    AssertEq(error.code, kCBLStatusForbidden);
    AssertEqual(error.localizedDescription, @"403 Where's your towel?");
}


- (void) verifyRev: (CBL_Revision*)rev
           history: (NSArray*)history
          existing: (unsigned)nExistingRevs
{
    CBL_Revision* gotRev = [db getDocumentWithID: rev.docID revisionID: nil];
    AssertEqual(gotRev, rev);
    AssertEqual(gotRev.properties, rev.properties);
    
    NSArray* revHistory = [db getRevisionHistory: gotRev backToRevIDs: nil];
    AssertEq(revHistory.count, history.count);
    for (unsigned i=0; i<history.count; i++) {
        CBL_Revision* hrev = revHistory[i];
        AssertEqual(hrev.docID, rev.docID);
        AssertEqual(hrev.revID, history[i]);
        Assert(!hrev.deleted);

        BOOL expectedMissing = i > 0 && (history.count - i) > nExistingRevs;
        Assert(hrev.missing == expectedMissing, @"hrev[%d].missing = %d, should be %d", i, hrev.missing, expectedMissing);
    }
}


static CBLDatabaseChange* announcement(CBLDatabase* db, CBL_Revision* rev, CBL_Revision* winner) {
    [db getRevisionSequence: rev];
    return [[CBLDatabaseChange alloc] initWithAddedRevision: rev winningRevisionID: winner.revID
                                                 inConflict: NO source: nil];
}


- (void) test06_RevTree {
    RequireTestCase(CRUD);

    // Track the latest database-change notification that's posted:
    __block CBLDatabaseChange* change = nil;
    id observer = [[NSNotificationCenter defaultCenter]
                   addObserverForName: CBL_DatabaseChangesNotification
                   object: db
                   queue: nil
                   usingBlock: ^(NSNotification *n) {
                       NSArray* changes = n.userInfo[@"changes"];
                       Assert(changes.count == 1, @"Multiple changes posted!");
                       Assert(!change, @"Multiple notifications posted!");
                       change = changes[0];
                   }];

    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID" revID: @"4-4444" deleted: NO];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"hi"});
    CBL_Revision* revAgain = [rev copy];
    NSArray* history = @[rev.revID, @"3-3333", @"2-2222", @"1-1111"];
    change = nil;
    NSError* error;
    CBLStatus status = [db forceInsert: rev revisionHistory: history source: nil error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
    AssertEq(db.documentCount, 1u);
    [self verifyRev: rev history: history existing: 0];
    AssertEqual(change, announcement(db, rev, rev));
    Assert(!change.inConflict);

    // No-op forceInsert: of already-existing revision:
    SequenceNumber lastSeq = db.lastSequenceNumber;
    status = [db forceInsert: revAgain revisionHistory: history source: nil error: &error];
    AssertEq(status, kCBLStatusOK);
    AssertNil(error);
    AssertEq(db.lastSequenceNumber, lastSeq);

    CBL_MutableRevision* conflict = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID" revID: @"5-5555" deleted: NO];
    conflict.properties = $dict({@"_id", conflict.docID}, {@"_rev", conflict.revID},
                                {@"message", @"yo"});
    NSArray* conflictHistory = @[conflict.revID, @"4-4545", @"3-3030", @"2-2222", @"1-1111"];
    change = nil;
    status = [db forceInsert: conflict revisionHistory: conflictHistory source: nil error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
    AssertEq(db.documentCount, 1u);
    [self verifyRev: conflict history: conflictHistory existing: 0];
    AssertEqual(change, announcement(db, conflict, conflict));
    Assert(change.inConflict);

    // Add an unrelated document:
    CBL_MutableRevision* other = [[CBL_MutableRevision alloc] initWithDocID: @"AnotherDocID" revID: @"1-1010" deleted: NO];
    other.properties = $dict({@"language", @"jp"});
    change = nil;
    status = [db forceInsert: other revisionHistory: @[other.revID] source: nil error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
    AssertEqual(change, announcement(db, other, other));
    Assert(!change.inConflict);

    // Fetch one of those phantom revisions with no body:
    CBL_Revision* rev2 = [db getDocumentWithID: rev.docID revisionID: @"2-2222"];
    AssertNil(rev2);

    // Make sure no duplicate rows were inserted for the common revisions:
    // (SQLite storage assigns sequences to inserted ancestor revs, while ForestDB doesn't)
    AssertEq(db.lastSequenceNumber, (self.isSQLiteDB ? 8u : 3u));
    
    // Make sure the revision with the higher revID wins the conflict:
    CBL_Revision* current = [db getDocumentWithID: rev.docID revisionID: nil];
    AssertEqual(current, conflict);

    // Check that the list of conflicts is accurate:
    CBL_RevisionList* conflictingRevs = [db.storage getAllRevisionsOfDocumentID: rev.docID onlyCurrent: YES];
    AssertEqual(conflictingRevs.allRevisions, (@[conflict, rev]));

    // Get the _changes feed and verify only the winner is in it:
    CBLChangesOptions options = kDefaultCBLChangesOptions;
    CBL_RevisionList* changes = [db changesSinceSequence: 0 options: &options filter: NULL params: nil status: &status];
    AssertEqual(changes.allRevisions, (@[conflict, other]));
    options.includeConflicts = YES;
    changes = [db changesSinceSequence: 0 options: &options filter: NULL params: nil status: &status];
    // Ordering of conflicting revs isn't significant (and will be different with SQLite vs ForestDB)
    Assert(([changes.allRevisions isEqual: @[conflict, rev, other]]
         || [changes.allRevisions isEqual: @[rev, conflict, other]]));

    // Verify that compaction leaves the document history:
    Assert([db compact: NULL]);
    [self verifyRev: conflict history: conflictHistory existing: 0];

    // Delete the current winning rev, leaving the other one:
    CBL_Revision* del1 = [[CBL_Revision alloc] initWithDocID: conflict.docID revID: nil deleted: YES];
    change = nil;
    del1 = [db putRevision: [del1 mutableCopy] prevRevisionID: conflict.revID
             allowConflict: NO status: &status error: &error];
    AssertEq(status, 200);
    AssertNil(error);
    current = [db getDocumentWithID: rev.docID revisionID: nil];
    AssertEqual(current, rev);
    AssertEqual(change, announcement(db, del1, rev));
    
    [self verifyRev: rev history: history existing: 0];

    // Delete the remaining rev:
    CBL_Revision* del2 = [[CBL_Revision alloc] initWithDocID: rev.docID revID: nil deleted: YES];
    change = nil;
    del2 = [db putRevision: [del2 mutableCopy] prevRevisionID: rev.revID
             allowConflict: NO status: &status error: &error];
    AssertEq(status, 200);
    AssertNil(error);
    current = [db getDocumentWithID: rev.docID revisionID: nil];
    AssertEqual(current, nil);

    CBL_Revision* maxDel = CBLCompareRevIDs(del1.revID, del2.revID) > 0 ? del1 : nil;
    AssertEqual(change, announcement(db, del2, maxDel));
    Assert(!change.inConflict);

    [[NSNotificationCenter defaultCenter] removeObserver: observer];
}


- (void) test07_RevTreeConflict {
    RequireTestCase(RevTree);

    // Track the latest database-change notification that's posted:
    __block CBLDatabaseChange* change = nil;
    id observer = [[NSNotificationCenter defaultCenter]
     addObserverForName: CBL_DatabaseChangesNotification
     object: db
     queue: nil
     usingBlock: ^(NSNotification *n) {
         NSArray* changes = n.userInfo[@"changes"];
         Assert(changes.count == 1, @"Multiple changes posted!");
         Assert(!change, @"Multiple notifications posted!");
         change = changes[0];
     }];

    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID" revID: @"1-1111" deleted: NO];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"hi"});
    NSArray* history = @[rev.revID];
    change = nil;
    NSError* error;
    CBLStatus status = [db forceInsert: rev revisionHistory: history source: nil error: &error];
    AssertEq(status, 201);
    AssertNil(error);
    AssertEq(db.documentCount, 1u);
    Assert(!change.inConflict);
    [self verifyRev: rev history: history existing: 0];
    AssertEqual(change, announcement(db, rev, rev));

    rev = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID" revID: @"4-4444" deleted: NO];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"hi"});
    history = @[rev.revID, @"3-3333", @"2-2222", @"1-1111"];
    change = nil;
    status = [db forceInsert: rev revisionHistory: history source: nil error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
    AssertEq(db.documentCount, 1u);
    Assert(!change.inConflict);
    [self verifyRev: rev history: history existing: 1];
    AssertEqual(change, announcement(db, rev, rev));

    [[NSNotificationCenter defaultCenter] removeObserver: observer];
}


- (void) test08_DeterministicRevIDs {
    CBL_Revision* rev = [self putDoc: $dict({@"_id", @"mydoc"}, {@"key", @"value"})];
    NSString* revID = rev.revID;
    [self eraseTestDB];
    rev = [self putDoc: $dict({@"_id", @"mydoc"}, {@"key", @"value"})];
    AssertEqual(rev.revID, revID);
}


// Adding an identical revision to one that already exists should succeed with status 200.
- (void) test09_DuplicateRev {
    CBL_Revision* rev1 = [self putDoc: $dict({@"_id", @"mydoc"}, {@"key", @"value"})];

    NSDictionary* props = $dict({@"_id", @"mydoc"},
                                {@"_rev", rev1.revID},
                                {@"key", @"new-value"});
    CBL_Revision* rev2a = [self putDoc: props];

    CBL_Revision* rev2b = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status;
    NSError* error;
    rev2b = [db putRevision: [rev2b mutableCopy]
             prevRevisionID: rev1.revID
              allowConflict: YES
                     status: &status
                      error: &error];
    AssertEq(status, kCBLStatusOK);
    AssertNil(error);
    AssertEqual(rev2b, rev2a);
}


#pragma mark - MISC.:


- (void) test16_ReplicatorSequences {
    RequireTestCase(CRUD);
    AssertNil([db lastSequenceWithCheckpointID: @"pull"]);
    [db setLastSequence: @"lastpull" withCheckpointID: @"pull"];
    AssertEqual([db lastSequenceWithCheckpointID: @"pull"], @"lastpull");
    AssertNil([db lastSequenceWithCheckpointID: @"push"]);
    [db setLastSequence: @"newerpull" withCheckpointID: @"pull"];
    AssertEqual([db lastSequenceWithCheckpointID: @"pull"], @"newerpull");
    AssertNil([db lastSequenceWithCheckpointID: @"push"]);
    [db setLastSequence: @"lastpush" withCheckpointID: @"push"];
    AssertEqual([db lastSequenceWithCheckpointID: @"pull"], @"newerpull");
    AssertEqual([db lastSequenceWithCheckpointID: @"push"], @"lastpush");
}


- (void) test17_LocalDocs {
    // Create a document:
    NSMutableDictionary* props = $mdict({@"_id", @"_local/doc1"},
                                        {@"foo", @1}, {@"bar", $false});
    CBL_Body* doc = [[CBL_Body alloc] initWithProperties: props];
    CBL_Revision* rev1 = [[CBL_Revision alloc] initWithBody: doc];
    CBLStatus status;
    rev1 = [db.storage putLocalRevision: rev1 prevRevisionID: nil obeyMVCC: YES status: &status];
    AssertEq(status, kCBLStatusCreated);
    Log(@"Created: %@", rev1);
    AssertEqual(rev1.docID, @"_local/doc1");
    Assert([rev1.revID hasPrefix: @"1-"]);
    
    // Read it back:
    CBL_Revision* readRev = [db.storage getLocalDocumentWithID: rev1.docID revisionID: nil];
    Assert(readRev != nil);
    AssertEqual(readRev[@"_id"], rev1.docID);
    AssertEqual(readRev[@"_rev"], rev1.revID);
    AssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Now update it:
    props = [readRev.properties mutableCopy];
    props[@"status"] = @"updated!";
    doc = [CBL_Body bodyWithProperties: props];
    CBL_Revision* rev2 = [[CBL_Revision alloc] initWithBody: doc];
    CBL_Revision* rev2Input = rev2;
    rev2 = [db.storage putLocalRevision: rev2 prevRevisionID: rev1.revID obeyMVCC: YES status: &status];
    AssertEq(status, kCBLStatusCreated);
    Log(@"Updated: %@", rev2);
    AssertEqual(rev2.docID, rev1.docID);
    Assert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db.storage getLocalDocumentWithID: rev2.docID revisionID: nil];
    Assert(readRev != nil);
    AssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    AssertNil([db.storage putLocalRevision: rev2Input prevRevisionID: rev1.revID obeyMVCC: YES status: &status]);
    AssertEq(status, kCBLStatusConflict);
    
    // Delete it:
    CBL_Revision* revD = [[CBL_Revision alloc] initWithDocID: rev2.docID revID: nil deleted: YES];
    AssertEqual([db.storage putLocalRevision: revD prevRevisionID: nil obeyMVCC: YES status: &status], nil);
    AssertEq(status, kCBLStatusConflict);
    revD = [db.storage putLocalRevision: revD prevRevisionID: rev2.revID obeyMVCC: YES status: &status];
    AssertEq(status, kCBLStatusOK);
    
    // Delete nonexistent doc:
    CBL_Revision* revFake = [[CBL_Revision alloc] initWithDocID: @"_local/fake" revID: nil deleted: YES];
    [db.storage putLocalRevision: revFake prevRevisionID: nil obeyMVCC: YES status: &status];
    AssertEq(status, kCBLStatusNotFound);

    // Read it back (should fail):
    readRev = [db.storage getLocalDocumentWithID: revD.docID revisionID: nil];
    AssertNil(readRev);
}


- (void) test18_FindMissingRevisions {
    CBL_RevisionList* revs = [[CBL_RevisionList alloc] initWithArray: @[]];
    CBLStatus status;
    Assert([db.storage findMissingRevisions: revs status: &status]);

    CBL_Revision* doc1r1 = [self putDoc: $dict({@"_id", @"11111"}, {@"key", @"one"})];
    CBL_Revision* doc2r1 = [self putDoc: $dict({@"_id", @"22222"}, {@"key", @"two"})];
    [self putDoc: $dict({@"_id", @"33333"}, {@"key", @"three"})];
    [self putDoc: $dict({@"_id", @"44444"}, {@"key", @"four"})];
    [self putDoc: $dict({@"_id", @"55555"}, {@"key", @"five"})];

    CBL_Revision* doc1r2 = [self putDoc: $dict({@"_id", @"11111"}, {@"_rev", doc1r1.revID}, {@"key", @"one+"})];
    CBL_Revision* doc2r2 = [self putDoc: $dict({@"_id", @"22222"}, {@"_rev", doc2r1.revID}, {@"key", @"two+"})];
    
    [self putDoc: $dict({@"_id", @"11111"}, {@"_rev", doc1r2.revID}, {@"_deleted", $true})];
    
    // Now call -findMissingRevisions:
    CBL_Revision* revToFind1 = [[CBL_Revision alloc] initWithDocID: @"11111" revID: @"3-6060" deleted: NO];
    CBL_Revision* revToFind2 = [[CBL_Revision alloc] initWithDocID: @"22222" revID: doc2r2.revID deleted: NO];
    CBL_Revision* revToFind3 = [[CBL_Revision alloc] initWithDocID: @"99999" revID: @"9-4141" deleted: NO];
    revs = [[CBL_RevisionList alloc] initWithArray: @[revToFind1, revToFind2, revToFind3]];
    Assert([db.storage findMissingRevisions: revs status: &status]);
    AssertEqual(revs.allRevisions, (@[revToFind1, revToFind3]));
    
    // Check the possible ancestors:
    AssertEqual([db.storage getPossibleAncestorRevisionIDs: revToFind1 limit: 0 onlyAttachments: NO],
                 (@[doc1r2.revID, doc1r1.revID]));
    AssertEqual([db.storage getPossibleAncestorRevisionIDs: revToFind1 limit: 1 onlyAttachments: NO],
                 (@[doc1r2.revID]));
    AssertEqual([db.storage getPossibleAncestorRevisionIDs: revToFind3 limit: 0 onlyAttachments: NO],
                 nil);
}


- (void) test19_Purge {
    RequireTestCase(CBL_Database_PurgeRevs);
    CBL_Revision* rev1 = [self putDoc: $dict({@"_id", @"doc"}, {@"key", @"1"})];
    CBL_Revision* rev2 = [self putDoc: $dict({@"_id", @"doc"}, {@"_rev", rev1.revID}, {@"key", @"2"})];
    [self putDoc: $dict({@"_id", @"doc"}, {@"_rev", rev2.revID}, {@"key", @"3"})];

    // Purge the entire document:
    NSDictionary* toPurge = $dict({@"doc", @[@"*"]});
    NSDictionary* result;
    AssertEq([db.storage purgeRevisions: toPurge result: &result], kCBLStatusOK);
    AssertEqual(result, toPurge);

    CBL_RevisionList* remainingRevs = [db.storage getAllRevisionsOfDocumentID: @"doc" onlyCurrent: NO];
    AssertEq(remainingRevs.count, 0u);
    [db _close];
}


- (void) test20_PurgeRevs {
    CBL_Revision* rev1 = [self putDoc: $dict({@"_id", @"doc"}, {@"key", @"1"})];
    CBL_Revision* rev2 = [self putDoc: $dict({@"_id", @"doc"}, {@"_rev", rev1.revID}, {@"key", @"2"})];
    CBL_Revision* rev3 = [self putDoc: $dict({@"_id", @"doc"}, {@"_rev", rev2.revID}, {@"key", @"3"})];

    // Try to purge rev2, which should fail since it's not a leaf:
    NSDictionary* toPurge = $dict({@"doc", @[rev2.revID]});
    NSDictionary* result;
    AssertEq([db.storage purgeRevisions: toPurge result: &result], kCBLStatusOK);
    AssertEqual(result, $dict({@"doc", @[]}));
    AssertEq([result[@"doc"] count], 0u);

    // Purge rev3, which will remove all ancestors too:
    toPurge = $dict({@"doc", @[rev3.revID]});
    AssertEq([db.storage purgeRevisions: toPurge result: &result], kCBLStatusOK);
    AssertEqual(result, toPurge);

    CBL_RevisionList* remainingRevs = [db.storage getAllRevisionsOfDocumentID: @"doc" onlyCurrent: NO];
    AssertEq(remainingRevs.count, 0u);
}


- (void) test21_DeleteDatabase {
    // Add a revision and an attachment:
    CBL_Revision* rev1;
    CBLStatus status;
    NSError* error;
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSDictionary* props = @{@"foo": @1,
                            @"bar": $false,
                            @"_attachments": @{
                                @"attach": @{
                                    @"content_type": @"text/plain",
                                    @"data": attach1
                                }
                            }
                           };
    rev1 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
            prevRevisionID: nil allowConflict: NO status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);

    NSFileManager* manager = [NSFileManager defaultManager];
    NSString* attachmentStorePath = db.attachmentStorePath;
    AssertEq([manager fileExistsAtPath: attachmentStorePath], YES);

    BOOL result = [db deleteDatabase: &error];
    AssertEq(result, YES);
    AssertNil(error);
    AssertEq([manager fileExistsAtPath: attachmentStorePath], NO);
}


- (void) test22_Manager_Close {
    CBLManager* mgr1 = [dbmgr copy];
    CBLDatabase* testdb = [mgr1 databaseNamed: @"test_db" error: NULL];
    Assert(testdb);

    CBLManager* mgr2 = [dbmgr copy];
    testdb = [mgr2 databaseNamed: @"test_db" error: NULL];
    Assert(testdb);

    [mgr1 close];
    NSInteger count = [dbmgr.shared countForOpenedDatabase: @"test_db"];
    AssertEq(count, 1);

    [mgr2 close];
    count = [dbmgr.shared countForOpenedDatabase: @"test_db"];
    AssertEq(count, 0);
}


static CBL_Revision* mkrev(NSString* revID) {
    return [[CBL_Revision alloc] initWithDocID: @"docid" revID: revID deleted: NO];
}

- (void) test23_MakeRevisionHistoryDict {
    NSArray* revs = @[mkrev(@"4-jkl"), mkrev(@"3-ghi"), mkrev(@"2-def")];
    AssertEqual([CBLDatabase makeRevisionHistoryDict: revs],
                 $dict({@"ids", @[@"jkl", @"ghi", @"def"]},
                       {@"start", @4}));

    revs = @[mkrev(@"4-jkl"), mkrev(@"2-def")];
    AssertEqual([CBLDatabase makeRevisionHistoryDict: revs],
                 $dict({@"ids", @[@"4-jkl", @"2-def"]}));

    revs = @[mkrev(@"12345"), mkrev(@"6789")];
    AssertEqual([CBLDatabase makeRevisionHistoryDict: revs],
                 $dict({@"ids", @[@"12345", @"6789"]}));
}


- (void) test24_UpgradeDB {
    NSString* path = [self pathToTestFile: @"people.cblite"];
    CBLDatabaseUpgrade* upgrade = [[CBLDatabaseUpgrade alloc] initWithDatabase: db
                                                                    sqliteFile: path];
    Assert(upgrade);
    upgrade.canRemoveOldAttachmentsDir = NO;
    CBLStatus status = [upgrade import];
    AssertEq(status, kCBLStatusOK);
    AssertEq(upgrade.numDocs, 20u);
    AssertEq(upgrade.numRevs, 20u);
    AssertEq(db.documentCount, 19u);  // one of the imported docs is deleted and doesn't count
    AssertEq(db.attachmentStore.count, 2u);

    // Check the doc IDs:
    NSMutableArray* docIDs = $marray();
    NSEnumerator* iterator = [db getAllDocs: nil status: &status];
    CBLQueryRow* row;
    while (nil != (row = iterator.nextObject)) {
        [docIDs addObject: row.documentID];
    }
    AssertEqual(docIDs, (@[@"0BCD3CDB-2D2A-4794-9778-C246E1342DAF",
                           @"2523E485-BA62-41B6-B944-08F117DA9F1C",
                           @"290E84BA-CF7F-47C2-A9CD-8DCFA5D510D1",
                           @"7999782A-5064-44F7-94C0-6C7BB255380B",
                           @"8C912855-BBC5-422B-91AB-91E315B2B236",
                           @"B17BDF9C-17D7-4A20-99C7-98DECBC5DBBD",
                           @"CB35C64F-0570-45E1-AAEF-8183278A3AB7",
                           @"D04FB085-3AF9-48FC-AAED-EA5E61060B29",
                           @"DCB227A9-E079-484A-93A3-264A88562D36",
                           @"ECA02CAC-0672-4F42-856A-70BCB9EF941A",
                           @"ED49F69E-4FF9-4A3E-B3BA-8CD7D190F896",
                           @"F98C9AC0-A572-46BE-B94E-6593B3A15BE4",
                           @"FD1D7D76-88A8-4BF5-A3E2-D69573DFB647",
                           @"person-0234B8F3A662F09BDE3DAE8E1A3F65CDB2256983",
                           @"person-FDEB582FE67CB5AA12C76A8F75BDD2540B52F8BC",
                           @"rel-(person-0234B8F3A662F09BDE3DAE8E1A3F65CDB2256983)-to-(person-FDEB582FE67CB5AA12C76A8F75BDD2540B52F8BC)",
                           @"rel-(person-FDEB582FE67CB5AA12C76A8F75BDD2540B52F8BC)-to-(person-0234B8F3A662F09BDE3DAE8E1A3F65CDB2256983)",
                           @"thumbsup-by-(0234B8F3A662F09BDE3DAE8E1A3F65CDB2256983)-on-(7999782A-5064-44F7-94C0-6C7BB255380B)",
                           @"thumbsup-by-(0234B8F3A662F09BDE3DAE8E1A3F65CDB2256983)-on-(8C912855-BBC5-422B-91AB-91E315B2B236)"]));

    // Get an attachment:
    CBL_Revision* rev = [db getDocumentWithID: @"person-0234B8F3A662F09BDE3DAE8E1A3F65CDB2256983"
                                   revisionID: nil];
    CBL_Attachment* att = [db attachmentForRevision: rev named: @"picture" status: &status];
    AssertEq(att.content.length, 39730u);

    // This is the one deleted doc:
    rev = [db getDocumentWithID: @"thumbsup:0234B8F3A662F09BDE3DAE8E1A3F65CDB2256983:7999782A-5064-44F7-94C0-6C7BB255380B"
                                   revisionID: @"2-59a8b99190d92a186249cdf86c0344f6"];
    Assert(rev != nil);
}


#if TARGET_OS_IPHONE
#if !TARGET_IPHONE_SIMULATOR
- (void) test25_FileProtection {
    // Check that every file has the file protection set for the CBLManager (which defaults to
    // NSFileProtectionCompleteUnlessOpen.)
    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSString* dir = db.dir;
    NSArray* paths = [[fmgr subpathsAtPath: dir] arrayByAddingObject: @"."];
    for (NSString* path in paths) {
        NSString* absPath = [dir stringByAppendingPathComponent: path];
        id prot = [[fmgr attributesOfItemAtPath: absPath error: nil] objectForKey: NSFileProtectionKey];
        Log(@"Protection of %@ --> %@", path, prot);
        // Not checking -shm file as it will have NSFileProtectionNone by default regardless of its
        // parent directory projection level. However, the -shm file contains non-sensitive information.
        if (![path hasSuffix:@"-shm"])
            AssertEqual(prot, NSFileProtectionCompleteUnlessOpen);
    }
}
#endif
#endif

-(void) test26_ReAddAfterPurge {

    NSString* docId = @"test26-ReAddAfterPurge";

    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID:docId revID:@"1-1111" deleted: NO];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"testName", @"test26_ReAddAfterPurge"});
    NSError* error;
    CBLStatus status = [db forceInsert: rev revisionHistory: nil source: nil error: &error];
    AssertEq(status, kCBLStatusCreated);

    CBLDocument* redoc = [db existingDocumentWithID:docId];
    Assert(redoc);

    Log(@"Before purge, lastSequence = %llu", db.lastSequenceNumber);

    Log(@"PURGE");
    Assert([redoc purgeDocument: &error]);
    Log(@"After purge, lastSequence = %llu", db.lastSequenceNumber);

    AssertNil([db existingDocumentWithID:docId]);

    [self reopenTestDB];

    Log(@"After reopen, lastSequence = %llu", db.lastSequenceNumber);
    AssertNil([db existingDocumentWithID:docId]);

    CBL_MutableRevision* revAfterPurge = [[CBL_MutableRevision alloc] initWithDocID:docId revID:@"1-1111" deleted: NO];
    revAfterPurge.properties = $dict({@"_id", revAfterPurge.docID}, {@"_rev", revAfterPurge.revID}, {@"testName", @"test26_ReAddAfterPurge"});
    CBLStatus status2 = [db forceInsert: revAfterPurge revisionHistory: nil source: nil error: &error];
    AssertEq(status2, kCBLStatusCreated);
}


- (void) test27_ChangesSinceSequence {
    // Create 10 docs:
    [self createDocuments: 10];

    // Create a new doc with a conflict:
    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID" revID: @"1-1111" deleted: NO];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"hi"});
    NSArray* history = @[rev.revID];
    NSError* error;
    AssertEq([db forceInsert: rev revisionHistory: history source: nil error: &error], 201);
    rev = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID" revID: @"1-ffff" deleted: NO];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"bye"});
    history = @[rev.revID];
    AssertEq([db forceInsert: rev revisionHistory: history source: nil error: &error], 201);

    // Create another new doc with a merged conflict:
    rev = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID2" revID: @"1-1111" deleted: NO];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"hi"});
    history = @[rev.revID];
    AssertEq([db forceInsert: rev revisionHistory: history source: nil error: &error], 201);
    rev = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID2" revID: @"1-ffff" deleted: YES];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID});
    history = @[rev.revID];
    AssertEq([db forceInsert: rev revisionHistory: history source: nil error: &error], 201);

    // Get changes, testing all combinations of includeConflicts and includeDocs:
    for (int conflicts=0; conflicts <= 1; conflicts++) {
        for (int bodies=0; bodies <= 1; bodies++) {
            CBLChangesOptions options = kDefaultCBLChangesOptions;
            options.includeConflicts = (BOOL)conflicts;
            options.includeDocs = (BOOL)bodies;
            CBLStatus status;
            CBL_RevisionList* changes = [db changesSinceSequence: 0 options: &options filter: NULL params: nil status: &status];
            AssertEq(changes.count, 12u + 2*conflicts);
            for (CBL_Revision* change in changes) {
                if (bodies)
                    Assert(change.body != nil);
                else
                    AssertNil(change.body);
            }

            if (!conflicts) {
                AssertEqual(changes[10].revID, @"1-ffff");
                AssertEqual(changes[11].revID, @"1-1111"); // Non-deleted rev should be current (#896)
            }
        }
    }
}


// Ensure that a database created without auto-compact (by CBL 1.1, or prior to 10/5/15) can
// stil be opened, since it has to be switched to auto-compact mode.
- (void) test28_enableAutoCompact {
    __block NSError* error;
    [CBLDatabase setAutoCompact: NO];
    __block CBLDatabase* manualDB = [dbmgr databaseNamed: @"manualcompact" error: &error];
    Assert(manualDB);
    [self createDocumentWithProperties: @{} inDatabase: manualDB];
    Assert([manualDB close: &error]);
    manualDB = nil;

    [CBLDatabase setAutoCompact: YES];
    [self allowWarningsIn:^{
        manualDB = [dbmgr databaseNamed: @"manualcompact" error: &error];
    }];
    Assert(manualDB);
    [manualDB close: &error];
}


- (void) test29_autoPruneOnPut {    // Test #1165
    db.maxRevTreeDepth = 5;

    CBL_Revision* lastRev = nil;
    NSMutableArray *revs = [NSMutableArray new];
    for (int gen = 1; gen <= 10; gen++) {
        CBL_MutableRevision* newRev = [CBL_MutableRevision revisionWithProperties: @{@"_id": @"foo",
                                                                                     @"gen": @(gen)}];
        CBLStatus status;
        CBL_Revision* rev = [db putRevision: newRev prevRevisionID: lastRev.revID allowConflict: NO status: &status error: NULL];
        Assert(rev, @"Failed to putRevision: %d", status);
        [revs addObject: rev];
        lastRev = rev;
    }

    // Verify that the first five revs are no longer available:
    for (int gen = 1; gen <= 10; gen++) {
        CBL_Revision* rev = [db getDocumentWithID: @"foo" revisionID: [revs[gen-1] revID]];
        if (gen <= 5)
            AssertNil(rev);
        else
            Assert(rev != nil);
    }
}


- (void) test29_autoPruneOnForceInsert {    // Test #1165
    db.maxRevTreeDepth = 5;

    CBL_Revision* lastRev = nil;
    NSMutableArray *revs = [NSMutableArray new];
    NSMutableArray *history = [NSMutableArray new];
    for (int gen = 1; gen <= 10; gen++) {
        CBL_Revision* rev = [CBL_Revision revisionWithProperties: @{@"_id": @"foo",
                                                                    @"_rev": $sprintf(@"%d-cafebabe", gen),
                                                                    @"gen": @(gen)}];
        CBLStatus status = [db forceInsert: rev revisionHistory: history source: nil error: NULL];
        Assert(status == 201, @"Failed to forceInsert: %d", status);
        [history insertObject: rev.revID atIndex: 0];
        [revs addObject: rev];
        lastRev = rev;
    }

    // Verify that the first five revs are no longer available:
    for (int gen = 1; gen <= 10; gen++) {
        CBL_Revision* rev = [db getDocumentWithID: @"foo" revisionID: [revs[gen-1] revID]];
        if (gen <= 5)
            AssertNil(rev);
        else
            Assert(rev != nil);
    }
}


@end
