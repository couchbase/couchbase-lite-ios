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
#import "TDDatabase+Attachments.h"
#import "TDDatabase+Insertion.h"
#import "TDDatabase+LocalDocs.h"
#import "TDDatabase+Replication.h"
#import "TDBody.h"
#import "TDRevision.h"
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
            [user setObject: [dict objectForKey: key] forKey: key];
    }
    return user;
}


static TDRevision* putDoc(TDDatabase* db, NSDictionary* props) {
    TDRevision* rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status;
    TDRevision* result = [db putRevision: rev
                          prevRevisionID: [props objectForKey: @"_rev"]
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
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"foo", $object(1)}, {@"bar", $false});
    TDBody* doc = [[[TDBody alloc] initWithProperties: props] autorelease];
    TDRevision* rev1 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    TDStatus status;
    rev1 = [db putRevision: rev1 prevRevisionID: nil allowConflict: NO status: &status];
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
    rev2 = [db putRevision: rev2 prevRevisionID: rev1.revID allowConflict: NO status: &status];
    CAssertEq(status, 201);
    Log(@"Updated: %@", rev2);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getDocumentWithID: rev2.docID revisionID: nil options: 0];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    CAssertNil([db putRevision: rev2Input prevRevisionID: rev1.revID allowConflict: NO status: &status]);
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
    CAssertEq([db putRevision: revD prevRevisionID: nil allowConflict: NO status: &status], nil);
    CAssertEq(status, 409);
    revD = [db putRevision: revD prevRevisionID: rev2.revID allowConflict: NO status: &status];
    CAssertEq(status, 200);
    CAssertEqual(revD.docID, rev2.docID);
    CAssert([revD.revID hasPrefix: @"3-"]);
    
    // Delete nonexistent doc:
    TDRevision* revFake = [[[TDRevision alloc] initWithDocID: @"fake" revID: nil deleted: YES] autorelease];
    [db putRevision: revFake prevRevisionID: nil allowConflict: NO status: &status];
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


TestCase(TDDatabase_EmptyDoc) {
    // Test case for issue #44, which is caused by a bug in NSJSONSerialization.
    TDDatabase* db = createDB();
    TDRevision* rev = putDoc(db, $dict());
    TDQueryOptions options = kDefaultTDQueryOptions;
    options.includeDocs = YES;
    [db getDocsWithIDs: $array(rev.docID) options: &options]; // raises an exception :(
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
        BOOL hoopy = newRevision.deleted || [newRevision.properties objectForKey: @"towel"] != nil;
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
    CAssertEq(status, 201);
    
    // PUT a valid update:
    [props setObject: $object(3) forKey: @"head_count"];
    rev.properties = props;
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: rev.revID allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, 201);
    
    // PUT an invalid update:
    [props removeObjectForKey: @"towel"];
    rev.properties = props;
    validationCalled = NO;
#pragma unused (rev)  // tell analyzer to ignore dead stores below
    rev = [db putRevision: rev prevRevisionID: rev.revID allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, 403);
    
    // POST an invalid new document:
    props = $mdict({@"name", @"Vogon"}, {@"poetry", $true});
    rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, 403);

    // PUT a valid new document with an ID:
    props = $mdict({@"_id", @"ford"}, {@"name", @"Ford Prefect"}, {@"towel", @"terrycloth"});
    rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, 201);
    CAssertEqual(rev.docID, @"ford");
    
    // DELETE a document:
    rev = [[[TDRevision alloc] initWithDocID: rev.docID revID: rev.revID deleted: YES] autorelease];
    CAssert(rev.deleted);
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID:  rev.revID allowConflict: NO status: &status];
    CAssertEq(status, 200);
    CAssert(validationCalled);

    // PUT an invalid new document:
    props = $mdict({@"_id", @"petunias"}, {@"name", @"Pot of Petunias"});
    rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    validationCalled = NO;
    rev = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(validationCalled);
    CAssertEq(status, 403);
    
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
            prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, 201);
    
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    CAssertEq([db insertAttachmentWithKey: [db keyForAttachment: attach1]
                              forSequence: rev1.sequence
                                    named: @"attach" type: @"text/plain"
                                 encoding: kTDAttachmentEncodingNone
                                   length: attach1.length
                            encodedLength: 0
                            revpos: rev1.generation],
              201);
    
    NSString* type;
    TDAttachmentEncoding encoding;
    CAssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: &encoding status: &status], attach1);
    CAssertEq(status, 200);
    CAssertEqual(type, @"text/plain");
    CAssertEq(encoding, kTDAttachmentEncodingNone);
    
    // Check the attachment dict:
    NSMutableDictionary* itemDict = $mdict({@"content_type", @"text/plain"},
                                           {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                           {@"length", $object(27)},
                                           {@"stub", $true},
                                           {@"revpos", $object(1)});
    NSDictionary* attachmentDict = $dict({@"attach", itemDict});
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: 0], attachmentDict);
    TDRevision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                                options: 0];
    CAssertEqual([gotRev1.properties objectForKey: @"_attachments"], attachmentDict);
    
    // Check the attachment dict, with attachments included:
    [itemDict removeObjectForKey: @"stub"];
    [itemDict setObject: [TDBase64 encode: attach1] forKey: @"data"];
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: kTDIncludeAttachments], attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kTDIncludeAttachments];
    CAssertEqual([gotRev1.properties objectForKey: @"_attachments"], attachmentDict);
    
    // Add a second revision that doesn't update the attachment:
    TDRevision* rev2;
    rev2 = [db putRevision: [TDRevision revisionWithProperties:$dict({@"_id", rev1.docID},
                                                                      {@"foo", $object(2)},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev1.revID allowConflict: NO status: &status];
    CAssertEq(status, 201);
    
    [db copyAttachmentNamed: @"attach" fromSequence: rev1.sequence toSequence: rev2.sequence];

    // Add a third revision of the same document:
    TDRevision* rev3;
    rev3 = [db putRevision: [TDRevision revisionWithProperties:$dict({@"_id", rev2.docID},
                                                                      {@"foo", $object(2)},
                                                                      {@"bazz", $false})]
            prevRevisionID: rev2.revID allowConflict: NO status: &status];
    CAssertEq(status, 201);
    
    NSData* attach2 = [@"<html>And this is attach2</html>" dataUsingEncoding: NSUTF8StringEncoding];
    CAssertEq([db insertAttachmentWithKey: [db keyForAttachment: attach2]
                              forSequence: rev3.sequence
                                    named: @"attach" type: @"text/html"
                                 encoding: kTDAttachmentEncodingNone
                                   length: attach2.length
                            encodedLength: 0
                                   revpos: rev2.generation],
              201);
    
    // Check the 2nd revision's attachment:
    type = nil;
    CAssertEqual([db getAttachmentForSequence: rev2.sequence
                                        named: @"attach"
                                         type: &type
                                     encoding: &encoding
                                       status: &status], attach1);
    CAssertEq(status, 200);
    CAssertEqual(type, @"text/plain");
    CAssertEq(encoding, kTDAttachmentEncodingNone);
    
    // Check the 3rd revision's attachment:
    CAssertEqual([db getAttachmentForSequence: rev3.sequence
                                        named: @"attach"
                                         type: &type
                                     encoding: &encoding
                                       status: &status], attach2);
    CAssertEq(status, 200);
    CAssertEqual(type, @"text/html");
    CAssertEq(encoding, kTDAttachmentEncodingNone);
    
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
            prevRevisionID: nil allowConflict: NO status: &status];
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
                encoding: kTDAttachmentEncodingNone
                 ofDocID: rev1.docID revID: nil
                  status: &status];
    CAssertEq(status, 409);
    [db updateAttachment: @"attach" body: attachv2 type: @"application/foo"
                encoding: kTDAttachmentEncodingNone
                 ofDocID: rev1.docID revID: @"1-bogus"
                  status: &status];
    CAssertEq(status, 409);
    TDRevision* rev2 = [db updateAttachment: @"attach" body: attachv2 type: @"application/foo"
                                   encoding: kTDAttachmentEncodingNone
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
                encoding: kTDAttachmentEncodingNone
                 ofDocID: rev2.docID revID: rev2.revID
                  status: &status];
    CAssertEq(status, 404);
    [db updateAttachment: @"nosuchattach" body: nil type: nil
                encoding: kTDAttachmentEncodingNone
                 ofDocID: @"nosuchdoc" revID: @"nosuchrev"
                  status: &status];
    CAssertEq(status, 404);
    TDRevision* rev3 = [db updateAttachment: @"attach" body: nil type: nil
                                   encoding: kTDAttachmentEncodingNone
                                    ofDocID: rev2.docID revID: rev2.revID
                                     status: &status];
    CAssertEq(status, 200);
    CAssertEqual(rev3.docID, rev2.docID);
    CAssertEq(rev3.generation, 3u);
    
    // Get the updated revision:
    TDRevision* gotRev3 = [db getDocumentWithID: rev3.docID revisionID: rev3.revID
                                        options: 0];
    CAssertNil([gotRev3.properties objectForKey: @"_attachments"]);
}


TestCase(TDDatabase_EncodedAttachment) {
    RequireTestCase(TDDatabase_Attachments);
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();

    // Add a revision and an attachment to it:
    TDRevision* rev1;
    TDStatus status;
    rev1 = [db putRevision: [TDRevision revisionWithProperties:$dict({@"foo", $object(1)},
                                                                     {@"bar", $false})]
            prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, 201);
    
    NSData* attach1 = [@"Encoded! Encoded!Encoded! Encoded! Encoded! Encoded! Encoded! Encoded!"
                            dataUsingEncoding: NSUTF8StringEncoding];
    NSData* encoded = [NSData gtm_dataByGzippingData: attach1];
    CAssertEq([db insertAttachmentWithKey: [db keyForAttachment: encoded]
                              forSequence: rev1.sequence
                                    named: @"attach" type: @"text/plain"
                                 encoding: kTDAttachmentEncodingGZIP
                                   length: attach1.length
                            encodedLength: encoded.length
                            revpos: rev1.generation],
              201);
    
    // Read the attachment without decoding it:
    NSString* type;
    TDAttachmentEncoding encoding;
    CAssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: &encoding status: &status], encoded);
    CAssertEq(status, 200);
    CAssertEqual(type, @"text/plain");
    CAssertEq(encoding, kTDAttachmentEncodingGZIP);
    
    // Read the attachment, decoding it:
    CAssertEqual([db getAttachmentForSequence: rev1.sequence named: @"attach"
                                         type: &type encoding: NULL status: &status], attach1);
    CAssertEq(status, 200);
    CAssertEqual(type, @"text/plain");
    
    // Check the stub attachment dict:
    NSMutableDictionary* itemDict = $mdict({@"content_type", @"text/plain"},
                                           {@"digest", @"sha1-fhfNE/UKv/wgwDNPtNvG5DN/5Bg="},
                                           {@"length", $object(70)},
                                           {@"encoding", @"gzip"},
                                           {@"encoded_length", $object(37)},
                                           {@"stub", $true},
                                           {@"revpos", $object(1)});
    NSDictionary* attachmentDict = $dict({@"attach", itemDict});
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: 0], attachmentDict);
    TDRevision* gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                                options: 0];
    CAssertEqual([gotRev1.properties objectForKey: @"_attachments"], attachmentDict);

    // Check the attachment dict with encoded data:
    [itemDict setObject: [TDBase64 encode: encoded] forKey: @"data"];
    [itemDict removeObjectForKey: @"stub"];
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence
                                          options: kTDIncludeAttachments | kTDLeaveAttachmentsEncoded],
                 attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kTDIncludeAttachments | kTDLeaveAttachmentsEncoded];
    CAssertEqual([gotRev1.properties objectForKey: @"_attachments"], attachmentDict);

    // Check the attachment dict with data:
    [itemDict setObject: [TDBase64 encode: attach1] forKey: @"data"];
    [itemDict removeObjectForKey: @"encoding"];
    [itemDict removeObjectForKey: @"encoded_length"];
    CAssertEqual([db getAttachmentDictForSequence: rev1.sequence options: kTDIncludeAttachments], attachmentDict);
    gotRev1 = [db getDocumentWithID: rev1.docID revisionID: rev1.revID
                            options: kTDIncludeAttachments];
    CAssertEqual([gotRev1.properties objectForKey: @"_attachments"], attachmentDict);
}


TestCase(TDDatabase_StubOutAttachmentsBeforeRevPos) {
    NSDictionary* hello = $dict({@"revpos", $object(1)}, {@"follows", $true});
    NSDictionary* goodbye = $dict({@"revpos", $object(2)}, {@"data", @"squeeee"});
    NSDictionary* attachments = $dict({@"hello", hello}, {@"goodbye", goodbye});
    
    TDRevision* rev = [TDRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: 3];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", $object(1)}, {@"stub", $true})},
                                                               {@"goodbye", $dict({@"revpos", $object(2)}, {@"stub", $true})})}));
    
    rev = [TDRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: 2];
    CAssertEqual(rev.properties, $dict({@"_attachments", $dict({@"hello", $dict({@"revpos", $object(1)}, {@"stub", $true})},
                                                               {@"goodbye", goodbye})}));
    
    rev = [TDRevision revisionWithProperties: $dict({@"_attachments", attachments})];
    [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: 1];
    CAssertEqual(rev.properties, $dict({@"_attachments", attachments}));
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


TestCase(TDDatabase_LocalDocs) {
    // Start with a fresh database in /tmp:
    TDDatabase* db = createDB();
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"_id", @"_local/doc1"},
                                        {@"foo", $object(1)}, {@"bar", $false});
    TDBody* doc = [[[TDBody alloc] initWithProperties: props] autorelease];
    TDRevision* rev1 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    TDStatus status;
    rev1 = [db putLocalRevision: rev1 prevRevisionID: nil status: &status];
    CAssertEq(status, 201);
    Log(@"Created: %@", rev1);
    CAssertEqual(rev1.docID, @"_local/doc1");
    CAssert([rev1.revID hasPrefix: @"1-"]);
    
    // Read it back:
    TDRevision* readRev = [db getLocalDocumentWithID: rev1.docID revisionID: nil];
    CAssert(readRev != nil);
    CAssertEqual([readRev.properties objectForKey: @"_id"], rev1.docID);
    CAssertEqual([readRev.properties objectForKey: @"_rev"], rev1.revID);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Now update it:
    props = [[readRev.properties mutableCopy] autorelease];
    [props setObject: @"updated!" forKey: @"status"];
    doc = [TDBody bodyWithProperties: props];
    TDRevision* rev2 = [[[TDRevision alloc] initWithBody: doc] autorelease];
    TDRevision* rev2Input = rev2;
    rev2 = [db putLocalRevision: rev2 prevRevisionID: rev1.revID status: &status];
    CAssertEq(status, 201);
    Log(@"Updated: %@", rev2);
    CAssertEqual(rev2.docID, rev1.docID);
    CAssert([rev2.revID hasPrefix: @"2-"]);
    
    // Read it back:
    readRev = [db getLocalDocumentWithID: rev2.docID revisionID: nil];
    CAssert(readRev != nil);
    CAssertEqual(userProperties(readRev.properties), userProperties(doc.properties));
    
    // Try to update the first rev, which should fail:
    CAssertNil([db putLocalRevision: rev2Input prevRevisionID: rev1.revID status: &status]);
    CAssertEq(status, 409);
    
    // Delete it:
    TDRevision* revD = [[[TDRevision alloc] initWithDocID: rev2.docID revID: nil deleted: YES] autorelease];
    CAssertEq([db putLocalRevision: revD prevRevisionID: nil status: &status], nil);
    CAssertEq(status, 409);
    revD = [db putLocalRevision: revD prevRevisionID: rev2.revID status: &status];
    CAssertEq(status, 200);
    
    // Delete nonexistent doc:
    TDRevision* revFake = [[[TDRevision alloc] initWithDocID: @"_local/fake" revID: nil deleted: YES] autorelease];
    [db putLocalRevision: revFake prevRevisionID: nil status: &status];
    CAssertEq(status, 404);
    
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
    TDRevisionList* revs = [[[TDRevisionList alloc] initWithArray: $array(revToFind1, revToFind2, revToFind3)] autorelease];
    CAssert([db findMissingRevisions: revs]);
    CAssertEqual(revs.allRevisions, $array(revToFind1, revToFind3));
    
    // Check the possible ancestors:
    CAssertEqual([db getPossibleAncestorRevisionIDs: revToFind1], $array(doc1r1.revID, doc1r2.revID));
    CAssertEqual([db getPossibleAncestorRevisionIDs: revToFind3], nil);
    
}


TestCase(TDDatabase) {
    RequireTestCase(TDDatabase_CRUD);
    RequireTestCase(TDDatabase_RevTree);
    RequireTestCase(TDDatabase_Attachments);
    RequireTestCase(TDDatabase_PutAttachment);
    RequireTestCase(TDDatabase_EncodedAttachment);
    RequireTestCase(TDDatabase_StubOutAttachmentsBeforeRevPos);
    RequireTestCase(TDDatabase_ReplicatorSequences);
    RequireTestCase(TDDatabase_LocalDocs);
    RequireTestCase(TDDatabase_FindMissingRevisions);
}


#endif //DEBUG
