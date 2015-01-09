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
#import "CBLDatabase+LocalDocs.h"
#import "CBLDatabase+Replication.h"
#import "CBL_Attachment.h"
#import "CBL_Body.h"
#import "CBLRevision.h"
#import "CBLDatabaseChange.h"
#import "CBL_BlobStore.h"
#import "CBLBase64.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "GTMNSData+zlib.h"


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
    CBL_Revision* result = [db putRevision: [rev mutableCopy]
                           prevRevisionID: props[@"_rev"]
                            allowConflict: NO
                                   status: &status];
    Assert(status < 300, @"Status %d from putRevision:", status);
    Assert(result.revID != nil);
    return result;
}


- (void) test_CRUD {
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
    AssertNil([db getDocumentWithID: @"nonexistent" revisionID: nil options: 0 status: &status]);
    AssertEq(status, kCBLStatusNotFound);
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"foo", @1}, {@"bar", $false});
    CBL_Body* doc = [[CBL_Body alloc] initWithProperties: props];
    CBL_Revision* rev1 = [[CBL_Revision alloc] initWithBody: doc];
    Assert(rev1);
    rev1 = [db putRevision: [rev1 mutableCopy] prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
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
    rev2 = [db putRevision: [rev2 mutableCopy] prevRevisionID: rev1.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
    Log(@"Updated: %@", rev2);
    AssertEqual(rev2.docID, rev1.docID);
    Assert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getDocumentWithID: rev2.docID revisionID: nil];
    Assert(readRev != nil);
    AssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    AssertNil([db putRevision: [rev2Input mutableCopy] prevRevisionID: rev1.revID allowConflict: NO status: &status]);
    AssertEq(status, kCBLStatusConflict);

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
    CBL_Revision* revD = [[CBL_Revision alloc] initWithDocID: rev2.docID revID: nil deleted: YES];
    AssertEqual([db putRevision: [revD mutableCopy] prevRevisionID: nil allowConflict: NO status: &status], nil);
    AssertEq(status, kCBLStatusConflict);
    revD = [db putRevision: [revD mutableCopy] prevRevisionID: rev2.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusOK);
    AssertEqual(revD.docID, rev2.docID);
    Assert([revD.revID hasPrefix: @"3-"]);

    // Read the deletion revision:
    readRev = [db getDocumentWithID: revD.docID revisionID: revD.revID];
    Assert(readRev);
    Assert(readRev.deleted);
    AssertEqual(readRev.revID, revD.revID);

    // Delete nonexistent doc:
    CBL_Revision* revFake = [[CBL_Revision alloc] initWithDocID: @"fake" revID: nil deleted: YES];
    [db putRevision: [revFake mutableCopy] prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusNotFound);

    // Read it back (should fail):
    readRev = [db getDocumentWithID: revD.docID revisionID: nil];
    AssertNil(readRev);
    
    // Check the changes feed again after the deletion:
    changes = [db changesSinceSequence: 0 options: NULL filter: NULL params: nil status: &status];
    Log(@"Changes = %@", changes);
    AssertEq(changes.count, 1u);
    
    NSArray* history = [db getRevisionHistory: revD];
    Log(@"History = %@", history);
    AssertEqual(history, (@[revD, rev2, rev1]));

    // Check the revision-history object (_revisions property):
    NSString* revDSuffix = [revD.revID substringFromIndex: 2];
    NSString* rev2Suffix = [rev2.revID substringFromIndex: 2];
    NSString* rev1Suffix = [rev1.revID substringFromIndex: 2];
    AssertEqual(([db getRevisionHistoryDict: revD startingFromAnyOf: @[@"??", rev2.revID]]),
                 (@{@"ids": @[revDSuffix, rev2Suffix],
                    @"start": @3}));
    AssertEqual(([db getRevisionHistoryDict: revD startingFromAnyOf: nil]),
                 (@{@"ids": @[revDSuffix, rev2Suffix, rev1Suffix],
                    @"start": @3}));

    // Read rev 1 again:
    readRev = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    Assert(readRev != nil);
    AssertEqual(userProperties(readRev.properties), userProperties(rev1.properties));

    // Compact the database:
    NSError* error;
    Assert([db compact: &error]);

    // Make sure old rev is missing:
    AssertNil([db getDocumentWithID: rev1.docID revisionID: rev1.revID]);

    [[NSNotificationCenter defaultCenter] removeObserver: observer];
}


- (void) test_EmptyDoc {
    // Test case for issue #44, which is caused by a bug in CBLJSON.
    CBL_Revision* rev = [self putDoc: $dict()];
    CBLQueryOptions *options = [CBLQueryOptions new];
    options->includeDocs = YES;
    NSArray* keys = @[rev.docID];
    options.keys = keys;
    CBLStatus status;
    CBLQueryIteratorBlock iterator = [db getAllDocs: options status: &status];
    Assert(iterator);
    while (iterator()) {
    }
}


- (void) test_DeleteWithProperties {
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


- (void) test_DeleteAndRecreate {
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


- (void) test_Validation {
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
        AssertNil(newRevision.revisionID);
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
    validationCalled = NO;
    expectedParentRevID = nil;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: nil allowConflict: NO status: &status];
    Assert(validationCalled);
    AssertEq(status, kCBLStatusCreated);

    // PUT a valid update:
    props[@"head_count"] = @3;
    rev = revBySettingProperties(rev, props);
    validationCalled = NO;
    expectedParentRevID = rev.revID;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: rev.revID allowConflict: NO status: &status];
    Assert(validationCalled);
    AssertEq(status, kCBLStatusCreated);

    // PUT an invalid update:
    [props removeObjectForKey: @"towel"];
    rev = revBySettingProperties(rev, props);
    validationCalled = NO;
    expectedParentRevID = rev.revID;
#pragma unused(rev)
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: rev.revID allowConflict: NO status: &status];
    Assert(validationCalled);
    AssertEq(status, kCBLStatusForbidden);

    // POST an invalid new document:
    props = $mdict({@"name", @"Vogon"}, {@"poetry", $true});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    validationCalled = NO;
    expectedParentRevID = nil;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: nil allowConflict: NO status: &status];
    Assert(validationCalled);
    AssertEq(status, kCBLStatusForbidden);

    // PUT a valid new document with an ID:
    props = $mdict({@"_id", @"ford"}, {@"name", @"Ford Prefect"}, {@"towel", @"terrycloth"});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    validationCalled = NO;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: nil allowConflict: NO status: &status];
    Assert(validationCalled);
    expectedParentRevID = nil;
    AssertEq(status, kCBLStatusCreated);
    AssertEqual(rev.docID, @"ford");
    
    // DELETE a document:
    rev = [[CBL_Revision alloc] initWithDocID: rev.docID revID: rev.revID deleted: YES];
    Assert(rev.deleted);
    validationCalled = NO;
    expectedParentRevID = rev.revID;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: rev.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusOK);
    Assert(validationCalled);

    // PUT an invalid new document:
    props = $mdict({@"_id", @"petunias"}, {@"name", @"Pot of Petunias"});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    validationCalled = NO;
    expectedParentRevID = nil;
    rev = [db putRevision: [rev mutableCopy] prevRevisionID: nil allowConflict: NO status: &status];
    Assert(validationCalled);
    AssertEq(status, kCBLStatusForbidden);
}


- (void) verifyRev: (CBL_Revision*)rev
           history: (NSArray*)history
          existing: (unsigned)nExistingRevs
{
    CBL_Revision* gotRev = [db getDocumentWithID: rev.docID revisionID: nil];
    AssertEqual(gotRev, rev);
    AssertEqual(gotRev.properties, rev.properties);
    
    NSArray* revHistory = [db getRevisionHistory: gotRev];
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


static CBLDatabaseChange* announcement(CBL_Revision* rev, CBL_Revision* winner) {
    return [[CBLDatabaseChange alloc] initWithAddedRevision: rev winningRevision: winner
                                                 inConflict: NO source: nil];
}


- (void) test_RevTree {
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
    NSArray* history = @[rev.revID, @"3-3333", @"2-2222", @"1-1111"];
    change = nil;
    CBLStatus status = [db forceInsert: rev revisionHistory: history source: nil];
    AssertEq(status, kCBLStatusCreated);
    AssertEq(db.documentCount, 1u);
    [self verifyRev: rev history: history existing: 0];
    AssertEqual(change, announcement(rev, rev));
    Assert(!change.inConflict);


    CBL_MutableRevision* conflict = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID" revID: @"5-5555" deleted: NO];
    conflict.properties = $dict({@"_id", conflict.docID}, {@"_rev", conflict.revID},
                                {@"message", @"yo"});
    NSArray* conflictHistory = @[conflict.revID, @"4-4545", @"3-3030", @"2-2222", @"1-1111"];
    change = nil;
    status = [db forceInsert: conflict revisionHistory: conflictHistory source: nil];
    AssertEq(status, kCBLStatusCreated);
    AssertEq(db.documentCount, 1u);
    [self verifyRev: conflict history: conflictHistory existing: 0];
    AssertEqual(change, announcement(conflict, conflict));
    Assert(change.inConflict);

    // Add an unrelated document:
    CBL_MutableRevision* other = [[CBL_MutableRevision alloc] initWithDocID: @"AnotherDocID" revID: @"1-1010" deleted: NO];
    other.properties = $dict({@"language", @"jp"});
    change = nil;
    status = [db forceInsert: other revisionHistory: @[other.revID] source: nil];
    AssertEq(status, kCBLStatusCreated);
    AssertEqual(change, announcement(other, other));
    Assert(!change.inConflict);

    // Fetch one of those phantom revisions with no body:
    CBL_Revision* rev2 = [db getDocumentWithID: rev.docID revisionID: @"2-2222"];
    AssertNil(rev2);

    // Make sure no duplicate rows were inserted for the common revisions:
    AssertEq(db.lastSequenceNumber, 8u);
    
    // Make sure the revision with the higher revID wins the conflict:
    CBL_Revision* current = [db getDocumentWithID: rev.docID revisionID: nil];
    AssertEqual(current, conflict);

    // Check that the list of conflicts is accurate:
    CBL_RevisionList* conflictingRevs = [db getAllRevisionsOfDocumentID: rev.docID onlyCurrent: YES];
    AssertEqual(conflictingRevs.allRevisions, (@[conflict, rev]));

    // Get the _changes feed and verify only the winner is in it:
    CBLChangesOptions options = kDefaultCBLChangesOptions;
    CBL_RevisionList* changes = [db changesSinceSequence: 0 options: &options filter: NULL params: nil status: &status];
    AssertEqual(changes.allRevisions, (@[conflict, other]));
    options.includeConflicts = YES;
    changes = [db changesSinceSequence: 0 options: &options filter: NULL params: nil status: &status];
    AssertEqual(changes.allRevisions, (@[conflict, rev, other]));

    // Verify that compaction leaves the document history:
    Assert([db compact: NULL]);
    [self verifyRev: conflict history: conflictHistory existing: 0];

    // Delete the current winning rev, leaving the other one:
    CBL_Revision* del1 = [[CBL_Revision alloc] initWithDocID: conflict.docID revID: nil deleted: YES];
    change = nil;
    del1 = [db putRevision: [del1 mutableCopy] prevRevisionID: conflict.revID
             allowConflict: NO status: &status];
    AssertEq(status, 200);
    current = [db getDocumentWithID: rev.docID revisionID: nil];
    AssertEqual(current, rev);
    AssertEqual(change, announcement(del1, rev));
    
    [self verifyRev: rev history: history existing: 0];

    // Delete the remaining rev:
    CBL_Revision* del2 = [[CBL_Revision alloc] initWithDocID: rev.docID revID: nil deleted: YES];
    change = nil;
    del2 = [db putRevision: [del2 mutableCopy] prevRevisionID: rev.revID
             allowConflict: NO status: &status];
    AssertEq(status, 200);
    current = [db getDocumentWithID: rev.docID revisionID: nil];
    AssertEqual(current, nil);

    CBL_Revision* maxDel = CBLCompareRevIDs(del1.revID, del2.revID) > 0 ? del1 : nil;
    AssertEqual(change, announcement(del2, maxDel));
    Assert(!change.inConflict);

    [[NSNotificationCenter defaultCenter] removeObserver: observer];
}


- (void) test_RevTreeConflict {
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
    CBLStatus status = [db forceInsert: rev revisionHistory: history source: nil];
    AssertEq(status, 201);
    AssertEq(db.documentCount, 1u);
    Assert(!change.inConflict);
    [self verifyRev: rev history: history existing: 0];
    AssertEqual(change, announcement(rev, rev));

    rev = [[CBL_MutableRevision alloc] initWithDocID: @"MyDocID" revID: @"4-4444" deleted: NO];
    rev.properties = $dict({@"_id", rev.docID}, {@"_rev", rev.revID}, {@"message", @"hi"});
    history = @[rev.revID, @"3-3333", @"2-2222", @"1-1111"];
    change = nil;
    status = [db forceInsert: rev revisionHistory: history source: nil];
    AssertEq(status, kCBLStatusCreated);
    AssertEq(db.documentCount, 1u);
    Assert(!change.inConflict);
    [self verifyRev: rev history: history existing: 1];
    AssertEqual(change, announcement(rev, rev));

    [[NSNotificationCenter defaultCenter] removeObserver: observer];
}


- (void) test_DeterministicRevIDs {
    CBL_Revision* rev = [self putDoc: $dict({@"_id", @"mydoc"}, {@"key", @"value"})];
    NSString* revID = rev.revID;
    [self eraseTestDB];
    rev = [self putDoc: $dict({@"_id", @"mydoc"}, {@"key", @"value"})];
    AssertEqual(rev.revID, revID);
}


// Adding an identical revision to one that already exists should succeed with status 200.
- (void) test_DuplicateRev {
    CBL_Revision* rev1 = [self putDoc: $dict({@"_id", @"mydoc"}, {@"key", @"value"})];

    NSDictionary* props = $dict({@"_id", @"mydoc"},
                                {@"_rev", rev1.revID},
                                {@"key", @"new-value"});
    CBL_Revision* rev2a = [self putDoc: props];

    CBL_Revision* rev2b = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status;
    rev2b = [db putRevision: [rev2b mutableCopy]
             prevRevisionID: rev1.revID
              allowConflict: YES
                     status: &status];
    AssertEq(status, kCBLStatusOK);
    AssertEqual(rev2b, rev2a);
}


#pragma mark - ATTACHMENTS:


static void insertAttachment(DatabaseInternal_Tests* self,
                             NSData* blob,
                             SequenceNumber sequence,
                             NSString* name, NSString* type,
                             CBLAttachmentEncoding encoding,
                             UInt64 length, UInt64 encodedLength,
                             unsigned revpos)
{
    CBL_Attachment* attachment = [[CBL_Attachment alloc] initWithName: name contentType: type];
    CBLBlobKey blobKey = attachment.blobKey;
    Assert([self->db storeBlob: blob creatingKey: &blobKey], @"Failed to store blob");
    attachment->encoding = encoding;
    attachment->length = length;
    attachment->encodedLength = encodedLength;
    AssertEq([self->db insertAttachment: attachment forSequence: sequence], kCBLStatusCreated);
}


- (void) test_Attachments {
    RequireTestCase(CRUD);
    CBL_BlobStore* attachments = db.attachmentStore;

    AssertEq(attachments.count, 0u);
    AssertEqual(attachments.allKeys, @[]);
    
    // Add a revision and an attachment to it:
    CBL_Revision* rev1;
    CBLStatus status;
    rev1 = [db putRevision: [CBL_MutableRevision revisionWithProperties:$dict({@"foo", @1},
                                                                       {@"bar", $false})]
            prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);

    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    insertAttachment(self, attach1,
                     rev1.sequence,
                     @"attach", @"text/plain",
                     kCBLAttachmentEncodingNone,
                     attach1.length,
                     0,
                     rev1.generation);
    
    CBL_Attachment* att = [db attachmentForRevision: rev1 named: @"attach" status: &status];
    AssertEq(status, kCBLStatusOK);
    AssertEqual(att.data, attach1);
    AssertEqual(att.contentType, @"text/plain");
    AssertEq(att->encoding, kCBLAttachmentEncodingNone);

    // Check the attachment dict:
    NSMutableDictionary* itemDict = $mdict({@"content_type", @"text/plain"},
                                           {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                           {@"length", @(27)},
                                           {@"stub", $true},
                                           {@"revpos", @1});
    NSDictionary* attachmentDict = $dict({@"attach", itemDict});
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    AssertEqual(gotRev1[@"_attachments"], attachmentDict);
    
    // Check the attachment dict, with attachments included:
    [itemDict removeObjectForKey: @"stub"];
    itemDict[@"data"] = [CBLBase64 encode: attach1];
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kCBLIncludeAttachments
                             status: &status];
    AssertEqual(gotRev1[@"_attachments"], attachmentDict);
    
    // Add a second revision that doesn't update the attachment:
    CBL_Revision* rev2;
    rev2 = [db putRevision: [CBL_MutableRevision revisionWithProperties:$dict({@"_id", rev1.docID},
                                                                      {@"foo", @2},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev1.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
    
    [db copyAttachmentNamed: @"attach" fromSequence: rev1.sequence toSequence: rev2.sequence];

    // Add a third revision of the same document:
    CBL_Revision* rev3;
    rev3 = [db putRevision: [CBL_MutableRevision revisionWithProperties:$dict({@"_id", rev2.docID},
                                                                      {@"foo", @2},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev2.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
    
    NSData* attach2 = [@"<html>And this is attach2</html>" dataUsingEncoding: NSUTF8StringEncoding];
    insertAttachment(self, attach2,
                     rev3.sequence,
                     @"attach", @"text/html",
                     kCBLAttachmentEncodingNone,
                     attach2.length,
                     0,
                     rev2.generation);
    
    // Check the 2nd revision's attachment:
    att = [db attachmentForRevision: rev2 named: @"attach" status: &status];
    AssertEq(status, kCBLStatusOK);
    AssertEqual(att.data, attach1);
    AssertEqual(att.contentType, @"text/plain");
    AssertEq(att->encoding, kCBLAttachmentEncodingNone);
    
    // Check the 3rd revision's attachment:
    att = [db attachmentForRevision: rev3 named: @"attach" status: &status];
    AssertEq(status, kCBLStatusOK);
    AssertEqual(att.data, attach2);
    AssertEqual(att.contentType, @"text/html");
    AssertEq(att->encoding, kCBLAttachmentEncodingNone);
    
    // Examine the attachment store:
    AssertEq(attachments.count, 2u);
    NSSet* expected = [NSSet setWithObjects: [CBL_BlobStore keyDataForBlob: attach1],
                                             [CBL_BlobStore keyDataForBlob: attach2], nil];
    AssertEqual([NSSet setWithArray: attachments.allKeys], expected);
    
    Assert([db compact: NULL]);  // This clears the body of the first revision
    AssertEq(attachments.count, 1u);
    AssertEqual(attachments.allKeys, @[[CBL_BlobStore keyDataForBlob: attach2]]);
}


static CBL_BlobStoreWriter* blobForData(CBLDatabase* db, NSData* data) {
    CBL_BlobStoreWriter* blob = db.attachmentWriter;
    [blob appendData: data];
    [blob finish];
    return blob;
}


- (CBL_Revision*) putDoc: (NSString*)docID
          withAttachment: (NSString*) attachmentText
              compressed: (BOOL)compress
{
    NSData* attachmentData = [attachmentText dataUsingEncoding: NSUTF8StringEncoding];
    NSString* encoding = nil;
    NSNumber* length = nil;
    if (compress) {
        length = @(attachmentData.length);
        encoding = @"gzip";
        attachmentData = [NSData gtm_dataByGzippingData: attachmentData];
    }
    NSString* base64 = [CBLBase64 encode: attachmentData];
    NSDictionary* attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                           {@"data", base64},
                                                           {@"encoding", encoding},
                                                           {@"length", length}
                                                           )});
    NSDictionary* props = $dict({@"_id", docID},
                                {@"foo", @1},
                                {@"bar", $false},
                                {@"_attachments", attachmentDict});
    CBLStatus status;
    CBL_Revision* rev = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
                         prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
    return rev;
}


- (void) test_PutAttachment {
    RequireTestCase(CBL_Database_CRUD);
    // Put a revision that includes an _attachments dict:
    CBL_Revision* rev1 = [self putDoc: nil withAttachment: @"This is the body of attach1" compressed: NO];
    AssertEqual(rev1[@"_attachments"], $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                                {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                                                {@"length", @(27)},
                                                                {@"stub", $true},
                                                                {@"revpos", @1})}));

    // Examine the attachment store:
    AssertEq(db.attachmentStore.count, 1u);
    
    // Get the revision:
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    NSDictionary* attachmentDict = gotRev1[@"_attachments"];
    AssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                         {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                                         {@"length", @(27)},
                                                         {@"stub", $true},
                                                         {@"revpos", @1})}));
    
    // Update the attachment directly:
    CBLStatus status;
    NSData* attachv2 = [@"Replaced body of attach" dataUsingEncoding: NSUTF8StringEncoding];
    [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                    type: @"application/foo"
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev1.docID revID: nil
                  status: &status];
    AssertEq(status, kCBLStatusConflict);
    [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                    type: @"application/foo"
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev1.docID revID: @"1-deadbeef"
                  status: &status];
    AssertEq(status, kCBLStatusConflict);
    CBL_Revision* rev2 = [db updateAttachment: @"attach" body: blobForData(db, attachv2)
                                        type: @"application/foo"
                                   encoding: kCBLAttachmentEncodingNone
                                    ofDocID: rev1.docID revID: rev1.revID
                                     status: &status];
    AssertEq(status, kCBLStatusCreated);
    AssertEqual(rev2.docID, rev1.docID);
    AssertEq(rev2.generation, 2u);

    // Get the updated revision:
    CBL_Revision* gotRev2 = [db getDocumentWithID: rev2.docID revisionID: rev2.revID];
    attachmentDict = gotRev2[@"_attachments"];
    AssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"application/foo"},
                                                         {@"digest", @"sha1-mbT3208HI3PZgbG4zYWbDW2HsPk="},
                                                         {@"length", @(23)},
                                                         {@"stub", $true},
                                                         {@"revpos", @2})}));

    CBL_Attachment* gotAttach = [db attachmentForRevision: gotRev2 named: @"attach" status: &status];
    AssertEqual(gotAttach.data, attachv2);

    // Delete the attachment:
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: rev2.docID revID: rev2.revID
                  status: &status];
    AssertEq(status, kCBLStatusAttachmentNotFound);
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                encoding: kCBLAttachmentEncodingNone
                 ofDocID: @"nosuchdoc" revID: @"nosuchrev"
                  status: &status];
    AssertEq(status, kCBLStatusNotFound);
    CBL_Revision* rev3 = [db updateAttachment: @"attach" body: nil type: nil
                                     encoding: kCBLAttachmentEncodingNone
                                      ofDocID: rev2.docID revID: rev2.revID
                                       status: &status];
    AssertEq(status, kCBLStatusOK);
    AssertEqual(rev3.docID, rev2.docID);
    AssertEq(rev3.generation, 3u);

    // Get the updated revision:
    CBL_Revision* gotRev3 = [db getDocumentWithID: rev3.docID revisionID: rev3.revID];
    AssertNil((gotRev3.properties)[@"_attachments"]);
}


- (void)test_PutEncodedAttachment {
    RequireTestCase(CBL_Database_PutAttachment);
    CBL_Revision* rev1 = [self putDoc: nil withAttachment: @"This is the body of attach1" compressed: YES];
    AssertEqual(rev1[@"_attachments"], $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                                {@"digest", @"sha1-Wk8g89eb0Y+5DtvMKkf+/g90Mhc="},
                                                                {@"length", @(27)},
                                                                {@"encoded_length", @(45)},
                                                                {@"encoding", @"gzip"},
                                                                {@"stub", $true},
                                                                {@"revpos", @1})}));

    // Examine the attachment store:
    AssertEq(db.attachmentStore.count, 1u);

    // Get the revision:
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    NSDictionary* attachmentDict = gotRev1[@"_attachments"];
    AssertEqual(attachmentDict, $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                         {@"digest", @"sha1-Wk8g89eb0Y+5DtvMKkf+/g90Mhc="},
                                                         {@"length", @(27)},
                                                         {@"encoded_length", @(45)},
                                                         {@"encoding", @"gzip"},
                                                         {@"stub", $true},
                                                         {@"revpos", @1})}));
}


// Test that updating an attachment via a PUT correctly updates its revpos.
- (void) test_AttachmentRevPos {
    RequireTestCase(PutAttachment);

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
    rev1 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
            prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);

    AssertEqual((rev1[@"_attachments"])[@"attach"][@"revpos"], @1);

    // Update the attachment with another PUT:
    NSData* attach2 = [@"This WAS the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    base64 = [CBLBase64 encode: attach2];
    attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                             {@"data", base64})});
    props = $dict({@"_id", rev1.docID},
                  {@"foo", @2},
                  {@"bar", $true},
                  {@"_attachments", attachmentDict});
    CBL_Revision* rev2;
    rev2 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
            prevRevisionID: rev1.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);

    // The punch line: Did the revpos get incremented to 2?
    AssertEqual((rev2[@"_attachments"])[@"attach"][@"revpos"], @2);
    [db _close];
}


- (void) test_GarbageCollectAttachments {
    NSMutableArray* revs = $marray();
    for (int i=0; i<100; i++) {
        [revs addObject: [self putDoc: $sprintf(@"doc-%d", i)
                       withAttachment: $sprintf(@"Attachment #%d", i)
                           compressed: NO]];
    }
    for (int i=0; i<40; i++) {
        CBLStatus status;
        revs[i] = [db updateAttachment: @"attach" body: nil type: nil
                              encoding: kCBLAttachmentEncodingNone
                               ofDocID: [revs[i] docID] revID: [revs[i] revID]
                                status: &status];
    }

    NSError* error;
    Assert([db compact: &error], @"Compact failed: %@", error);
    AssertEq(db.attachmentStore.count, 60u);
    [db _close];
}


#if 0
- (void) test_EncodedAttachment {
    RequireTestCase(CBL_Database_CRUD);
    // Start with a fresh database in /tmp:
    CBLDatabase* db = createDB();

    // Add a revision and an attachment to it:
    CBL_Revision* rev1;
    CBLStatus status;
    rev1 = [db putRevision: [CBL_Revision revisionWithProperties:$dict({@"foo", @1},
                                                                     {@"bar", $false})]
            prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
    
    NSData* attach1 = [@"Encoded! Encoded!Encoded! Encoded! Encoded! Encoded! Encoded! Encoded!"
                            dataUsingEncoding: NSUTF8StringEncoding];
    NSData* encoded = [NSData gtm_dataByGzippingData: attach1];
    insertAttachment(self, encoded,
                     rev1.sequence,
                     @"attach", @"text/plain",
                     kCBLAttachmentEncodingGZIP,
                     attach1.length,
                     encoded.length,
                     rev1.generation);
    
    // Read the attachment without decoding it:
    NSString* type;
    CBLAttachmentEncoding encoding;
    AssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: &encoding status: &status], encoded);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(type, @"text/plain");
    AssertEq(encoding, kCBLAttachmentEncodingGZIP);
    
    // Read the attachment, decoding it:
    AssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: NULL status: &status], attach1);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(type, @"text/plain");
    
    // Check the stub attachment dict:
    NSMutableDictionary* itemDict = $mdict({@"content_type", @"text/plain"},
                                           {@"digest", @"sha1-fhfNE/UKv/wgwDNPtNvG5DN/5Bg="},
                                           {@"length", @(70)},
                                           {@"encoding", @"gzip"},
                                           {@"encoded_length", @(37)},
                                           {@"stub", $true},
                                           {@"revpos", @1});
    NSDictionary* attachmentDict = $dict({@"attach", itemDict});
    AssertEqual([db getAttachmentDictForSequence: rev1.sequence options: 0], attachmentDict);
    CBL_Revision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID];
    AssertEqual(gotRev1[@"_attachments"], attachmentDict);

    // Check the attachment dict with encoded data:
    itemDict[@"data"] = [CBLBase64 encode: encoded];
    [itemDict removeObjectForKey: @"stub"];
    AssertEqual([db getAttachmentDictForSequence: rev1.sequence
                                          options: kCBLIncludeAttachments | kCBLLeaveAttachmentsEncoded],
                 attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kCBLIncludeAttachments | kCBLLeaveAttachmentsEncoded
                             status: &status];
    AssertEqual(gotRev1[@"_attachments"], attachmentDict);

    // Check the attachment dict with data:
    itemDict[@"data"] = [CBLBase64 encode: attach1];
    [itemDict removeObjectForKey: @"encoding"];
    [itemDict removeObjectForKey: @"encoded_length"];
    AssertEqual([db getAttachmentDictForSequence: rev1.sequence options: kCBLIncludeAttachments], attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kCBLIncludeAttachments
                             status: &status];
    AssertEqual(gotRev1[@"_attachments"], attachmentDict);
}
#endif


- (void) test_StubOutAttachmentsBeforeRevPos {
    NSDictionary* hello = $dict({@"revpos", @1}, {@"follows", $true});
    NSDictionary* goodbye = $dict({@"revpos", @2}, {@"data", @"squeeee"});
    NSDictionary* attachments = $dict({@"hello", hello}, {@"goodbye", goodbye});
    
    CBL_MutableRevision* rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 3 attachmentsFollow: NO];
    AssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"stub", $true})})}));
    
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 2 attachmentsFollow: NO];
    AssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", goodbye})}));
    
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 1 attachmentsFollow: NO];
    AssertEqual(rev.properties, $dict({@"_attachments", attachments}));
    
    // Now test the "follows" mode:
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 3 attachmentsFollow: YES];
    AssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"stub", $true})})}));

    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 2 attachmentsFollow: YES];
    AssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"follows", $true})})}));
    
    rev = [CBL_MutableRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [CBLDatabase stubOutAttachmentsIn: rev beforeRevPos: 1 attachmentsFollow: YES];
    AssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", @1}, {@"follows", $true})},
                                                               {@"goodbye", $dict({@"revpos", @2}, {@"follows", $true})})}));
}


#pragma mark - MISC.:


- (void) test_ReplicatorSequences {
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


- (void) test_LocalDocs {
    // Create a document:
    NSMutableDictionary* props = $mdict({@"_id", @"_local/doc1"},
                                        {@"foo", @1}, {@"bar", $false});
    CBL_Body* doc = [[CBL_Body alloc] initWithProperties: props];
    CBL_Revision* rev1 = [[CBL_Revision alloc] initWithBody: doc];
    CBLStatus status;
    rev1 = [db putLocalRevision: rev1 prevRevisionID: nil obeyMVCC: YES status: &status];
    AssertEq(status, kCBLStatusCreated);
    Log(@"Created: %@", rev1);
    AssertEqual(rev1.docID, @"_local/doc1");
    Assert([rev1.revID hasPrefix: @"1-"]);
    
    // Read it back:
    CBL_Revision* readRev = [db getLocalDocumentWithID: rev1.docID revisionID: nil];
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
    rev2 = [db putLocalRevision: rev2 prevRevisionID: rev1.revID obeyMVCC: YES status: &status];
    AssertEq(status, kCBLStatusCreated);
    Log(@"Updated: %@", rev2);
    AssertEqual(rev2.docID, rev1.docID);
    Assert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getLocalDocumentWithID: rev2.docID revisionID: nil];
    Assert(readRev != nil);
    AssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    AssertNil([db putLocalRevision: rev2Input prevRevisionID: rev1.revID obeyMVCC: YES status: &status]);
    AssertEq(status, kCBLStatusConflict);
    
    // Delete it:
    CBL_Revision* revD = [[CBL_Revision alloc] initWithDocID: rev2.docID revID: nil deleted: YES];
    AssertEqual([db putLocalRevision: revD prevRevisionID: nil obeyMVCC: YES status: &status], nil);
    AssertEq(status, kCBLStatusConflict);
    revD = [db putLocalRevision: revD prevRevisionID: rev2.revID obeyMVCC: YES status: &status];
    AssertEq(status, kCBLStatusOK);
    
    // Delete nonexistent doc:
    CBL_Revision* revFake = [[CBL_Revision alloc] initWithDocID: @"_local/fake" revID: nil deleted: YES];
    [db putLocalRevision: revFake prevRevisionID: nil obeyMVCC: YES status: &status];
    AssertEq(status, kCBLStatusNotFound);

    // Read it back (should fail):
    readRev = [db getLocalDocumentWithID: revD.docID revisionID: nil];
    AssertNil(readRev);
}


- (void) test_FindMissingRevisions {
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
    CBL_RevisionList* revs = [[CBL_RevisionList alloc] initWithArray: @[revToFind1, revToFind2, revToFind3]];
    CBLStatus status;
    Assert([db findMissingRevisions: revs status: &status]);
    AssertEqual(revs.allRevisions, (@[revToFind1, revToFind3]));
    
    // Check the possible ancestors:
    AssertEqual([db getPossibleAncestorRevisionIDs: revToFind1 limit: 0 onlyAttachments: NO],
                 (@[doc1r2.revID, doc1r1.revID]));
    AssertEqual([db getPossibleAncestorRevisionIDs: revToFind1 limit: 1 onlyAttachments: NO],
                 (@[doc1r2.revID]));
    AssertEqual([db getPossibleAncestorRevisionIDs: revToFind3 limit: 0 onlyAttachments: NO],
                 nil);
}


- (void) test_Purge {
    RequireTestCase(CBL_Database_PurgeRevs);
    CBL_Revision* rev1 = [self putDoc: $dict({@"_id", @"doc"}, {@"key", @"1"})];
    CBL_Revision* rev2 = [self putDoc: $dict({@"_id", @"doc"}, {@"_rev", rev1.revID}, {@"key", @"2"})];
    [self putDoc: $dict({@"_id", @"doc"}, {@"_rev", rev2.revID}, {@"key", @"3"})];

    // Purge the entire document:
    NSDictionary* toPurge = $dict({@"doc", @[@"*"]});
    NSDictionary* result;
    AssertEq([db purgeRevisions: toPurge result: &result], kCBLStatusOK);
    AssertEqual(result, toPurge);

    CBL_RevisionList* remainingRevs = [db getAllRevisionsOfDocumentID: @"doc" onlyCurrent: NO];
    AssertEq(remainingRevs.count, 0u);
    [db _close];
}


- (void) test_PurgeRevs {
    CBL_Revision* rev1 = [self putDoc: $dict({@"_id", @"doc"}, {@"key", @"1"})];
    CBL_Revision* rev2 = [self putDoc: $dict({@"_id", @"doc"}, {@"_rev", rev1.revID}, {@"key", @"2"})];
    CBL_Revision* rev3 = [self putDoc: $dict({@"_id", @"doc"}, {@"_rev", rev2.revID}, {@"key", @"3"})];

    // Try to purge rev2, which should fail since it's not a leaf:
    NSDictionary* toPurge = $dict({@"doc", @[rev2.revID]});
    NSDictionary* result;
    AssertEq([db purgeRevisions: toPurge result: &result], kCBLStatusOK);
    AssertEqual(result, $dict({@"doc", @[]}));
    AssertEq([result[@"doc"] count], 0u);

    // Purge rev3, which will remove all ancestors too:
    toPurge = $dict({@"doc", @[rev3.revID]});
    AssertEq([db purgeRevisions: toPurge result: &result], kCBLStatusOK);
    AssertEqual(result, toPurge);

    CBL_RevisionList* remainingRevs = [db getAllRevisionsOfDocumentID: @"doc" onlyCurrent: NO];
    AssertEq(remainingRevs.count, 0u);
}


- (void) test_DeleteDatabase {
    // Add a revision and an attachment:
    CBL_Revision* rev1;
    CBLStatus status;
    rev1 = [db putRevision: [CBL_MutableRevision revisionWithProperties: $dict({@"foo", @1},
                                                                               {@"bar", $false})]
            prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);

    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    insertAttachment(self, attach1,
                     rev1.sequence,
                     @"attach", @"text/plain",
                     kCBLAttachmentEncodingNone,
                     attach1.length,
                     0,
                     rev1.generation);

    NSFileManager* manager = [NSFileManager defaultManager];
    NSString* attachmentStorePath = db.attachmentStorePath;
    AssertEq([manager fileExistsAtPath: attachmentStorePath], YES);

    NSError* error;
    BOOL result = [db deleteDatabase: &error];
    AssertEq(result, YES);
    AssertNil(error);
    AssertEq([manager fileExistsAtPath: attachmentStorePath], NO);
}


- (void) test_Manager_Close {
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

- (void) test_MakeRevisionHistoryDict {
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


@end
