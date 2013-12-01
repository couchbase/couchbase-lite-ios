//
//  APITests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/12/11.
//  Copyright 2011-2013 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"
#import "Test.h"


#if DEBUG


static CBLDatabase* createEmptyDB(void) {
    CBLManager* dbmgr = [CBLManager sharedInstance];
    CAssert(dbmgr);
    NSError* error;
    CBLDatabase* db = [dbmgr createEmptyDatabaseNamed: @"test_db" error: &error];
    CAssert(db, @"Couldn't create test_db: %@", error);
    return db;
}


static void closeTestDB(CBLDatabase* db) {
    CAssert(db != nil);
    CAssert([db close]);
}


static CBLDocument* createDocumentWithProperties(CBLDatabase* db,
                                                   NSDictionary* properties) {
    CBLDocument* doc = [db createDocument];
    CAssert(doc != nil);
    CAssertNil(doc.currentRevisionID);
    CAssertNil(doc.currentRevision);
    CAssert(doc.documentID, @"Document has no ID"); // 'untitled' docs are no longer untitled (8/10/12)

    NSError* error;
    CAssert([doc putProperties: properties error: &error], @"Couldn't save: %@", error);  // save it!
    
    CAssert(doc.documentID);
    CAssert(doc.currentRevisionID);
    CAssertEqual(doc.userProperties, properties);
    CAssertEq(db[doc.documentID], doc);
    //Log(@"Created %p = %@", doc, doc);
    return doc;
}


static void createDocuments(CBLDatabase* db, unsigned n) {
    [db inTransaction:^BOOL{
    for (unsigned i=0; i<n; i++) {
            @autoreleasepool {
        NSDictionary* properties = @{@"testName": @"testDatabase", @"sequence": @(i)};
        createDocumentWithProperties(db, properties);
    }
}
        return YES;
    }];
}


#pragma mark - SERVER & DOCUMENTS:


TestCase(API_Manager) {
    CBLManager* dbmgr = [CBLManager sharedInstance];
    CAssert(dbmgr);
    for (NSString* name in dbmgr.allDatabaseNames) {
        CBLDatabase* db = dbmgr[name];
        Log(@"Database '%@': %u documents", db.name, (unsigned)db.documentCount);
    }

    CBLManagerOptions options = {.readOnly= true, .noReplicator= false};
    NSError* error;
    CBLManager* ro = [[CBLManager alloc] initWithDirectory: dbmgr.directory options: &options
                                                     error: &error];
    CAssert(ro);

    CBLDatabase* db = [ro databaseNamed: @"foo" error: &error];
    CAssertNil(db);

    db = [ro existingDatabaseNamed: @"test_db" error: &error];
    CAssert(db);
    CBLDocument* doc = [db createDocument];
    CAssert(![doc putProperties: @{@"foo": @"bar"} error: &error]);
    [ro close];
}


TestCase(API_CreateDocument) {
    CBLDatabase* db = createEmptyDB();
    NSDictionary* properties = @{@"testName": @"testCreateDocument",
                                @"tag": @1337};
    CBLDocument* doc = createDocumentWithProperties(db, properties);
    
    NSString* docID = doc.documentID;
    CAssert(docID.length > 10, @"Invalid doc ID: '%@'", docID);
    NSString* currentRevisionID = doc.currentRevisionID;
    CAssert(currentRevisionID.length > 10, @"Invalid doc revision: '%@'", currentRevisionID);

    CAssertEqual(doc.userProperties, properties);

    CAssertEq([db documentWithID: docID], doc);

    [db _clearDocumentCache]; // so we can load fresh copies

    CBLDocument* doc2 = [db existingDocumentWithID: docID];
    CAssertEqual(doc2.documentID, docID);
    CAssertEqual(doc2.currentRevision.revisionID, currentRevisionID);

    CAssertNil([db existingDocumentWithID: @"b0gus"]);

    closeTestDB(db);
}


TestCase(API_CreateRevisions) {
    RequireTestCase(API_CreateDocument);
    NSDictionary* properties = @{@"testName": @"testCreateRevisions",
    @"tag": @1337};
    CBLDatabase* db = createEmptyDB();
    CBLDocument* doc = createDocumentWithProperties(db, properties);
    CBLSavedRevision* rev1 = doc.currentRevision;
    CAssert([rev1.revisionID hasPrefix: @"1-"]);
    CAssertEq(rev1.sequence, 1);
    CAssertNil(rev1.attachments);

    // Test -createRevisionWithProperties:
    NSMutableDictionary* properties2 = [properties mutableCopy];
    properties2[@"tag"] = @4567;
    NSError* error;
    CBLSavedRevision* rev2 = [rev1 createRevisionWithProperties: properties2 error: &error];
    CAssert(rev2, @"Put failed: %@", error);

    CAssert([doc.currentRevisionID hasPrefix: @"2-"],
            @"Document revision ID is still %@", doc.currentRevisionID);

    CAssertEqual(rev2.revisionID, doc.currentRevisionID);
    CAssert(rev2.propertiesAreLoaded);
    CAssertEqual(rev2.userProperties, properties2);
    CAssertEq(rev2.document, doc);
    CAssertEqual(rev2.properties[@"_id"], doc.documentID);
    CAssertEqual(rev2.properties[@"_rev"], rev2.revisionID);

    // Test -createRevision:
    CBLUnsavedRevision* newRev = [rev2 createRevision];
    CAssertNil(newRev.revisionID);
    CAssertEq(newRev.parentRevision, rev2);
    CAssertEqual(newRev.parentRevisionID, rev2.revisionID);
    CAssertEqual(([newRev getRevisionHistory: &error]), (@[rev1, rev2]));
    CAssertEqual(newRev.properties, rev2.properties);
    CAssertEqual(newRev.userProperties, rev2.userProperties);
    newRev.userProperties = @{@"because": @"NoSQL"};
    CAssertEqual(newRev.userProperties, @{@"because": @"NoSQL"});
    CAssertEqual(newRev.properties,
                 (@{@"because": @"NoSQL", @"_id": doc.documentID, @"_rev": rev2.revisionID}));
    CBLSavedRevision* rev3 = [newRev save: &error];
    CAssert(rev3);
    CAssertEqual(rev3.userProperties, newRev.userProperties);
    closeTestDB(db);
}

TestCase(API_CreateNewRevisions) {
    RequireTestCase(API_CreateRevisions);
    NSDictionary* properties = @{@"testName": @"testCreateRevisions",
    @"tag": @1337};
    CBLDatabase* db = createEmptyDB();
    CBLDocument* doc = [db createDocument];
    CBLUnsavedRevision* newRev = [doc newRevision];

    CBLDocument* newRevDocument = newRev.document;
    CAssertEq(newRevDocument, doc);
    CAssertEq(newRev.database, db);
    CAssertNil(newRev.parentRevisionID);
    CAssertNil(newRev.parentRevision);
    CAssertEqual(newRev.properties, $mdict({@"_id", doc.documentID}));
    CAssert(!newRev.isDeletion);
    CAssertEq(newRev.sequence, 0);

    newRev[@"testName"] = @"testCreateRevisions";
    newRev[@"tag"] = @1337;
    CAssertEqual(newRev.userProperties, properties);

    NSError* error;
    CBLSavedRevision* rev1 = [newRev save: &error];
    CAssert(rev1, @"Save 1 failed: %@", error);
    CAssertEqual(rev1, doc.currentRevision);
    CAssert([rev1.revisionID hasPrefix: @"1-"]);
    CAssertEq(rev1.sequence, 1);
    CAssertNil(rev1.parentRevisionID);
    CAssertNil(rev1.parentRevision);

    newRev = [rev1 createRevision];
    newRevDocument = newRev.document;
    CAssertEq(newRevDocument, doc);
    CAssertEq(newRev.database, db);
    CAssertEqual(newRev.parentRevisionID, rev1.revisionID);
    CAssertEqual(newRev.parentRevision, rev1);
    CAssertEqual(newRev.properties, rev1.properties);
    CAssertEqual(newRev.userProperties, rev1.userProperties);
    CAssert(!newRev.isDeletion);

    newRev[@"tag"] = @4567;
    CBLSavedRevision* rev2 = [newRev save: &error];
    CAssert(rev2, @"Save 2 failed: %@", error);
    CAssertEqual(rev2, doc.currentRevision);
    CAssert([rev2.revisionID hasPrefix: @"2-"]);
    CAssertEq(rev2.sequence, 2);
    CAssertEqual(rev2.parentRevisionID, rev1.revisionID);
    CAssertEqual(rev2.parentRevision, rev1);

    CAssert([doc.currentRevisionID hasPrefix: @"2-"],
            @"Document revision ID is still %@", doc.currentRevisionID);

    // Add a deletion/tombstone revision:
    newRev = doc.newRevision;
    CAssertEq(newRev.parentRevisionID, rev2.revisionID);
    CAssertEqual(newRev.parentRevision, rev2);
    newRev.isDeletion = true;
    CBLSavedRevision* rev3 = [newRev save: &error];
    CAssert(rev3, @"Save 2 failed: %@", error);
    CAssertEqual(rev3, doc.currentRevision);
    CAssert([rev3.revisionID hasPrefix: @"3-"], @"Unexpected revID '%@'", rev3.revisionID);
    CAssertEq(rev3.sequence, 3);
    CAssert(rev3.isDeletion);

    CAssert(doc.isDeleted);
    CBLDocument* doc2 = db[doc.documentID];
    CAssertEq(doc2, doc);

    closeTestDB(db);
}

#if 0
TestCase(API_SaveMultipleDocuments) {
    CBLDatabase* db = createEmptyDB();
    NSMutableArray* docs = [NSMutableArray array];
    for (int i=0; i<5; i++) {
        NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                    @"testSaveMultipleDocuments", @"testName",
                                    [NSNumber numberWithInt: i], @"sequence",
                                    nil];
        CBLDocument* doc = createDocumentWithProperties(db, properties);
        [docs addObject: doc];
    }
    
    NSMutableArray* revisions = [NSMutableArray array];
    NSMutableArray* revisionProperties = [NSMutableArray array];
    
    for (CBLDocument* doc in docs) {
        CBLRevision* revision = doc.currentRevision;
        CAssert([revision.revisionID hasPrefix: @"1-"],
                     @"Expected 1st revision: %@ in %@", doc.currentRevisionID, doc);
        NSMutableDictionary* properties = revision.properties.mutableCopy;
        [properties setObject: @"updated!" forKey: @"misc"];
        [revisions addObject: revision];
        [revisionProperties addObject: properties];
    }
    
    CAssertWait([db putChanges: revisionProperties toRevisions: revisions]);
    
    for (CBLDocument* doc in docs) {
        CAssert([doc.currentRevisionID hasPrefix: @"2-"],
                     @"Expected 2nd revision: %@ in %@", doc.currentRevisionID, doc);
        CAssertEqual([doc.currentRevision.properties objectForKey: @"misc"],
                             @"updated!");
    }
    closeTestDB(db);
}


TestCase(API_SaveMultipleUnsavedDocuments) {
    CBLDatabase* db = createEmptyDB();
    NSMutableArray* docs = [NSMutableArray array];
    NSMutableArray* docProperties = [NSMutableArray array];
    
    for (int i=0; i<5; i++) {
        CBLDocument* doc = [db untitledDocument];
        [docs addObject: doc];
        [docProperties addObject: [NSDictionary dictionaryWithObject: [NSNumber numberWithInt: i]
                                                              forKey: @"order"]];
    }
    
    CAssertWait([db putChanges: docProperties toRevisions: docs]);
    
    for (int i=0; i<5; i++) {
        CBLDocument* doc = [docs objectAtIndex: i];
        CAssert([doc.currentRevisionID hasPrefix: @"1-"],
                     @"Expected 2nd revision: %@ in %@", doc.currentRevisionID, doc);
        CAssertEqual([doc.currentRevision.properties objectForKey: @"order"],
                             [NSNumber numberWithInt: i]);
    }
    closeTestDB(db);
}


TestCase(API_DeleteMultipleDocuments) {
    CBLDatabase* db = createEmptyDB();
    NSMutableArray* docs = [NSMutableArray array];
    for (int i=0; i<5; i++) {
        NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                    @"testDeleteMultipleDocuments", @"testName",
                                    [NSNumber numberWithInt: i], @"sequence",
                                    nil];
        CBLDocument* doc = createDocumentWithProperties(properties);
        [docs addObject: doc];
    }
    
    CAssertWait([db deleteDocuments: docs]);
    
    for (CBLDocument* doc in docs) {
        CAssert(doc.isDeleted);
        CAssert(doc.currentRevision.isDeleted);
    }
    
    CAssertEq([db getDocumentCount], (NSInteger)0);
    closeTestDB(db);
}
#endif

TestCase(API_DeleteDocument) {
    CBLDatabase* db = createEmptyDB();
    NSDictionary* properties = @{@"testName": @"testDeleteDocument"};
    CBLDocument* doc = createDocumentWithProperties(db, properties);
    CAssert(!doc.isDeleted);
    CAssert(!doc.currentRevision.isDeletion);
    NSError* error;
    CAssert([doc deleteDocument: &error]);
    CAssert(doc.isDeleted);
    CAssert(doc.currentRevision.isDeletion);
    closeTestDB(db);
}


TestCase(API_PurgeDocument) {
    CBLDatabase* db = createEmptyDB();
    NSDictionary* properties = @{@"testName": @"testPurgeDocument"};
    CBLDocument* doc = createDocumentWithProperties(db, properties);
    CAssert(doc);
    
    NSError* error;
    CAssert([doc purgeDocument: &error]);
    
    CBLDocument* redoc = [db _cachedDocumentWithID:doc.documentID];
    CAssert(!redoc);
    closeTestDB(db);
}

TestCase(API_AllDocuments) {
    CBLDatabase* db = createEmptyDB();
    static const NSUInteger kNDocs = 5;
    createDocuments(db, kNDocs);

    // clear the cache so all documents/revisions will be re-fetched:
    [db _clearDocumentCache];
    
    Log(@"----- all documents -----");
    CBLQuery* query = [db createAllDocumentsQuery];
    //query.prefetch = YES;
    Log(@"Getting all documents: %@", query);
    
    CBLQueryEnumerator* rows = [query rows: NULL];
    CAssertEq(rows.count, kNDocs);
    NSUInteger n = 0;
    for (CBLQueryRow* row in rows) {
        Log(@"    --> %@", row);
        CBLDocument* doc = row.document;
        CAssert(doc, @"Couldn't get doc from query");
        CAssert(doc.currentRevision.propertiesAreLoaded, @"QueryRow should have preloaded revision contents");
        Log(@"        Properties = %@", doc.properties);
        CAssert(doc.properties, @"Couldn't get doc properties");
        CAssertEqual([doc propertyForKey: @"testName"], @"testDatabase");
        n++;
    }
    CAssertEq(n, kNDocs);
    closeTestDB(db);
}


TestCase(API_LocalDocs) {
    CBLDatabase* db = createEmptyDB();
    NSDictionary* props = [db existingLocalDocumentWithID: @"dock"];
    CAssertNil(props);
    NSError* error;
    CAssert([db putLocalDocument: @{@"foo": @"bar"} withID: @"dock" error: &error],
            @"Couldn't put new local doc: %@", error);
    props = [db existingLocalDocumentWithID: @"dock"];
    CAssertEqual(props[@"foo"], @"bar");
    
    CAssert([db putLocalDocument: @{@"FOOO": @"BARRR"} withID: @"dock" error: &error],
            @"Couldn't update local doc: %@", error);
    props = [db existingLocalDocumentWithID: @"dock"];
    CAssertNil(props[@"foo"]);
    CAssertEqual(props[@"FOOO"], @"BARRR");

    CAssert([db deleteLocalDocumentWithID: @"dock" error: &error],
            @"Couldn't delete local doc: %@", error);
    props = [db existingLocalDocumentWithID: @"dock"];
    CAssertNil(props);

    CAssert(![db deleteLocalDocumentWithID: @"dock" error: &error],
            @"Second delete should have failed");
    CAssertEq(error.code, kCBLStatusNotFound);
    closeTestDB(db);
}

#pragma mark - HISTORY

TestCase(API_History) {
    CBLDatabase* db = createEmptyDB();
    NSMutableDictionary* properties = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                @"test06_History", @"testName",
                                @1, @"tag",
                                nil];
    CBLDocument* doc = createDocumentWithProperties(db, properties);
    NSString* rev1ID = [doc.currentRevisionID copy];
    Log(@"1st revision: %@", rev1ID);
    CAssert([rev1ID hasPrefix: @"1-"], @"1st revision looks wrong: '%@'", rev1ID);
    CAssertEqual(doc.userProperties, properties);
    properties = doc.properties.mutableCopy;
    properties[@"tag"] = @2;
    CAssert(![properties isEqual: doc.properties]);
    NSError* error;
    CAssert([doc putProperties: properties error: &error]);
    NSString* rev2ID = doc.currentRevisionID;
    Log(@"2nd revision: %@", rev2ID);
    CAssert([rev2ID hasPrefix: @"2-"], @"2nd revision looks wrong: '%@'", rev2ID);

    NSArray* revisions = [doc getRevisionHistory: &error];
    Log(@"Revisions = %@", revisions);
    CAssertEq(revisions.count, 2u);
    
    CBLSavedRevision* rev1 = revisions[0];
    CAssertEqual(rev1.revisionID, rev1ID);
    NSDictionary* gotProperties = rev1.properties;
    CAssertEqual(gotProperties[@"tag"], @1);
    
    CBLSavedRevision* rev2 = revisions[1];
    CAssertEqual(rev2.revisionID, rev2ID);
    CAssertEq(rev2, doc.currentRevision);
    gotProperties = rev2.properties;
    CAssertEqual(gotProperties[@"tag"], @2);
    
    CAssertEqual([doc getConflictingRevisions: &error], @[rev2]);
    CAssertEqual([doc getLeafRevisions: &error], @[rev2]);
    closeTestDB(db);
}


TestCase(API_Conflict) {
    RequireTestCase(API_History);
    CBLDatabase* db = createEmptyDB();
    CBLDocument* doc = createDocumentWithProperties(db, @{@"foo": @"bar"});
    CBLSavedRevision* rev1 = doc.currentRevision;

    NSMutableDictionary* properties = doc.properties.mutableCopy;
    properties[@"tag"] = @2;
    NSError* error;
    CBLSavedRevision* rev2a = [doc putProperties: properties error: &error];

    properties = rev1.properties.mutableCopy;
    properties[@"tag"] = @3;
    CBLUnsavedRevision* newRev = [rev1 createRevision];
    newRev.properties = properties;
    CBLSavedRevision* rev2b = [newRev saveAllowingConflict: &error];
    CAssert(rev2b, @"Failed to create a a conflict: %@", error);

    CAssertEqual([doc getConflictingRevisions: &error], (@[rev2b, rev2a]));
    CAssertEqual([doc getLeafRevisions: &error], (@[rev2b, rev2a]));

    CBLSavedRevision* defaultRev, *otherRev;
    if ([rev2a.revisionID compare: rev2b.revisionID] > 0) {
        defaultRev = rev2a; otherRev = rev2b;
    } else {
        defaultRev = rev2b; otherRev = rev2a;
    }
    AssertEqual(doc.currentRevision, defaultRev);

    CBLQuery* query = [db createAllDocumentsQuery];
    query.allDocsMode = kCBLShowConflicts;
    NSArray* rows = [[query rows: NULL] allObjects];
    AssertEq(rows.count, 1u);
    CBLQueryRow* row = rows[0];
    NSArray* revs = row.conflictingRevisions;
    AssertEq(revs.count, 2u);
    AssertEqual(revs[0], defaultRev);
    AssertEqual(revs[1], otherRev);
    
    closeTestDB(db);
}


#pragma mark - ATTACHMENTS

TestCase(API_Attachments) {
    CBLDatabase* db = createEmptyDB();
    NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"testAttachments", @"testName",
                                nil];
    CBLDocument* doc = createDocumentWithProperties(db, properties);
    CBLSavedRevision* rev = doc.currentRevision;
    
    CAssertEq(rev.attachments.count, (NSUInteger)0);
    CAssertEq(rev.attachmentNames.count, (NSUInteger)0);
    CAssertNil([rev attachmentNamed: @"index.html"]);
    
    NSData* body = [@"This is a test attachment!" dataUsingEncoding: NSUTF8StringEncoding];
    CBLUnsavedRevision *rev2 = [doc newRevision];
    [rev2 setAttachmentNamed: @"index.html" withContentType: @"text/plain; charset=utf-8" content:body];

    NSError * error;
    CBLSavedRevision *rev3 = [rev2 save:&error];
    
    CAssertNil(error);
    CAssert(rev3);
    CAssertEq(rev3.attachments.count, (NSUInteger)1);
    CAssertEq(rev3.attachmentNames.count, (NSUInteger)1);

    CBLAttachment* attach = [rev3 attachmentNamed:@"index.html"];
    CAssert(attach);
    CAssertEq(attach.document, doc);
    CAssertEqual(attach.name, @"index.html");
    CAssertEqual(rev3.attachmentNames, [NSArray arrayWithObject: @"index.html"]);

    CAssertEqual(attach.contentType, @"text/plain; charset=utf-8");
    CAssertEqual(attach.content, body);
    CAssertEq(attach.length, (UInt64)body.length);

    NSURL* bodyURL = attach.contentURL;
    CAssert(bodyURL.isFileURL);
    CAssertEqual([NSData dataWithContentsOfURL: bodyURL], body);

    CBLUnsavedRevision *newRev = [rev3 createRevision];
    [newRev removeAttachmentNamed: attach.name];
    CBLRevision* rev4 = [newRev save: &error];
    CAssert(!error);
    CAssert(rev4);
    CAssertEq([rev4.attachmentNames count], (NSUInteger)0);
    closeTestDB(db);
}

#pragma mark - CHANGE TRACKING


TestCase(API_ChangeTracking) {
    CBLDatabase* db = createEmptyDB();
    __block int changeCount = 0;
    [[NSNotificationCenter defaultCenter] addObserverForName: kCBLDatabaseChangeNotification
                                                      object: db
                                                       queue: nil
                                                  usingBlock: ^(NSNotification *n) {
                                                      ++changeCount;
                                                  }];
    
    createDocuments(db,5);

    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
    // We expect that the changes reported by the server won't be notified, because those revisions
    // are already cached in memory.
    CAssertEq(changeCount, 1);
    
    CAssertEq(db.lastSequenceNumber, 5);
    closeTestDB(db);
}


#pragma mark - VIEWS:


TestCase(API_CreateView) {
    CBLDatabase* db = createEmptyDB();

    CBLView* view = [db viewNamed: @"vu"];
    CAssert(view);
    CAssertEq(view.database, db);
    CAssertEqual(view.name, @"vu");
    CAssert(view.mapBlock == NULL);
    CAssert(view.reduceBlock == NULL);

    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    CAssert(view.mapBlock != nil);

    static const NSUInteger kNDocs = 50;
    createDocuments(db, kNDocs);

    CBLQuery* query = [view createQuery];
    CAssertEq(query.database, db);
    query.startKey = @23;
    query.endKey = @33;
    CBLQueryEnumerator* rows = [query rows: NULL];
    CAssert(rows);
    CAssertEq(rows.count, (NSUInteger)11);

    int expectedKey = 23;
    for (CBLQueryRow* row in rows) {
        CAssertEq([row.key intValue], expectedKey);
        CAssertEq(row.sequenceNumber, (UInt64)expectedKey+1);
        ++expectedKey;
    }
    closeTestDB(db);
}


#if 0
TestCase(API_RunSlowView) {
    CBLDatabase* db = createEmptyDB();
    static const NSUInteger kNDocs = 50;
    [self createDocuments: kNDocs];
    
    CBLQuery* query = [db slowQueryWithMap: @"function(doc){emit(doc.sequence,null);};"];
    query.startKey = [NSNumber numberWithInt: 23];
    query.endKey = [NSNumber numberWithInt: 33];
    CBLQueryEnumerator* rows = [query rows: NULL];
    CAssert(rows);
    CAssertEq(rows.count, (NSUInteger)11);
    CAssertEq(rows.totalCount, kNDocs);
    
    int expectedKey = 23;
    for (CBLQueryRow* row in rows) {
        CAssertEq([row.key intValue], expectedKey);
        ++expectedKey;
    }
    closeTestDB(db);
}
#endif


TestCase(API_Validation) {
    CBLDatabase* db = createEmptyDB();

    [db setValidationNamed: @"uncool"
                 asBlock: ^BOOL(CBLSavedRevision *newRevision, id<CBLValidationContext> context) {
                     if (!newRevision.properties[@"groovy"]) {
                         context.errorMessage = @"uncool";
                         return NO;
                     }
                     return YES;
                 }];
    
    NSDictionary* properties = @{ @"groovy" : @"right on", @"foo": @"bar" };
    CBLDocument* doc = [db createDocument];
    NSError *error;
    CAssert([doc putProperties: properties error: &error]);
    
    properties = @{ @"foo": @"bar" };
    doc = [db createDocument];
    CAssert(![doc putProperties: properties error: &error]);
    CAssertEq(error.code, 403);
    //CAssertEqual(error.localizedDescription, @"forbidden: uncool"); //TODO: Not hooked up yet
    closeTestDB(db);
}


TestCase(API_ViewWithLinkedDocs) {
    CBLDatabase* db = createEmptyDB();
    static const NSUInteger kNDocs = 50;
    NSMutableArray* docs = [NSMutableArray array];
    NSString* lastDocID = @"";
    for (NSUInteger i=0; i<kNDocs; i++) {
        NSDictionary* properties = @{ @"sequence" : @(i),
                                      @"prev": lastDocID };
        CBLDocument* doc = createDocumentWithProperties(db, properties);
        [docs addObject: doc];
        lastDocID = doc.documentID;
    }
    
    // The map function will emit the ID of the previous document, causing that document to be
    // included when include_docs (aka prefetch) is enabled.
    CBLQuery* query = [db slowQueryWithMap: MAPBLOCK({
        emit(doc[@"sequence"], @{ @"_id": doc[@"prev"] });
    })];
    query.startKey = @23;
    query.endKey = @33;
    query.prefetch = YES;
    CBLQueryEnumerator* rows = [query rows: NULL];
    CAssert(rows);
    CAssertEq(rows.count, (NSUInteger)11);
    
    int rowNumber = 23;
    for (CBLQueryRow* row in rows) {
        CAssertEq([row.key intValue], rowNumber);
        CBLDocument* prevDoc = docs[rowNumber-1];
        CAssertEqual(row.documentID, prevDoc.documentID);
        CAssertEq(row.document, prevDoc);
        ++rowNumber;
    }
    closeTestDB(db);
}


TestCase(API_LiveQuery) {
    RequireTestCase(API_CreateView);
    CBLDatabase* db = createEmptyDB();
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    static const NSUInteger kNDocs = 50;
    createDocuments(db, kNDocs);

    CBLLiveQuery* query = [[view createQuery] asLiveQuery];
    query.startKey = @23;
    query.endKey = @33;
    Log(@"Created %@", query);
    CAssertNil(query.rows);

    Log(@"Waiting for live query to update...");
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    bool finished = false;
    while (!finished) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;
        CBLQueryEnumerator* rows = query.rows;
        Log(@"Live query rows = %@", rows);
        if (rows != nil) {
            CAssertEq(rows.count, (NSUInteger)11);

            int expectedKey = 23;
            for (CBLQueryRow* row in rows) {
                CAssertEq(row.document.database, db);
                CAssertEq([row.key intValue], expectedKey);
                ++expectedKey;
            }
            finished = true;
        }
    }
    [query stop];
    CAssert(finished, @"Live query timed out!");
    closeTestDB(db);
}


TestCase(API_AsyncViewQuery) {
    RequireTestCase(API_CreateView);
    CBLDatabase* db = createEmptyDB();
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    static const NSUInteger kNDocs = 50;
    createDocuments(db, kNDocs);

    CBLQuery* query = [view createQuery];
    query.startKey = @23;
    query.endKey = @33;

    __block bool finished = false;
    NSThread* curThread = [NSThread currentThread];
    [query runAsync: ^(CBLQueryEnumerator *rows, NSError* error) {
        Log(@"Async query finished!");
        CAssertEq([NSThread currentThread], curThread);
        CAssert(rows);
        CAssertNil(error);
        CAssertEq(rows.count, (NSUInteger)11);

        int expectedKey = 23;
        for (CBLQueryRow* row in rows) {
            CAssertEq(row.document.database, db);
            CAssertEq([row.key intValue], expectedKey);
            ++expectedKey;
        }
        finished = true;
    }];

    Log(@"Waiting for async query to finish...");
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 5.0];
    while (!finished) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;
    }
    CAssert(finished, @"Async query timed out!");
    closeTestDB(db);
}


// Make sure that a database's map/reduce functions are shared with the shadow database instance
// running in the background server.
TestCase(API_SharedMapBlocks) {
    CBLManager* mgr = [CBLManager createEmptyAtTemporaryPath: @"API_SharedMapBlocks"];
    CBLDatabase* db = [mgr databaseNamed: @"db" error: nil];
    [db setFilterNamed: @"phil" asBlock: ^BOOL(CBLSavedRevision *revision, NSDictionary *params) {
        return YES;
    }];
    [db setValidationNamed: @"val" asBlock: VALIDATIONBLOCK({
        return YES;
    })];
    CBLView* view = [db viewNamed: @"view"];
    BOOL ok = [view setMapBlock: MAPBLOCK({
        // nothing
    }) reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
        return nil;
    } version: @"1"];
    CAssert(ok, @"Couldn't set map/reduce");

    CBLMapBlock map = view.mapBlock;
    CBLReduceBlock reduce = view.reduceBlock;
    CBLFilterBlock filter = [db filterNamed: @"phil"];
    CBLValidationBlock validation = [db validationNamed: @"val"];

    id result = [mgr.backgroundServer waitForDatabaseNamed: @"db" to: ^id(CBLDatabase *serverDb) {
        CAssert(serverDb != nil);
        CBLView* serverView = [serverDb viewNamed: @"view"];
        CAssert(serverView != nil);
        CAssertEq([serverDb filterNamed: @"phil"], filter);
        CAssertEq([serverDb validationNamed: @"val"], validation);
        CAssertEq(serverView.mapBlock, map);
        CAssertEq(serverView.reduceBlock, reduce);
        return @"ok";
    }];
    CAssertEqual(result, @"ok");
    closeTestDB(db);
    [mgr close];
}


TestCase(API_ChangeUUID) {
    CBLManager* mgr = [CBLManager createEmptyAtTemporaryPath: @"API_SharedMapBlocks"];
    CBLDatabase* db = [mgr databaseNamed: @"db" error: nil];
    NSString* pub = db.publicUUID;
    NSString* priv = db.privateUUID;
    Assert(pub.length > 10);
    Assert(priv.length > 10);

    NSError* error;
    Assert([db replaceUUIDs: &error], @"replaceUUIDs failed: %@", error);
    Assert(!$equal(pub, db.publicUUID));
    Assert(!$equal(priv, db.privateUUID));
    [mgr close];
}


TestCase(API) {
    RequireTestCase(API_Manager);
    RequireTestCase(API_CreateDocument);
    RequireTestCase(API_CreateRevisions);
    RequireTestCase(API_DeleteDocument);
    RequireTestCase(API_PurgeDocument);
    RequireTestCase(API_AllDocuments);
    RequireTestCase(API_LocalDocs);
    RequireTestCase(API_History);
    RequireTestCase(API_Attachments);
    RequireTestCase(API_ChangeTracking);
    RequireTestCase(API_CreateView);
    RequireTestCase(API_Validation);
    RequireTestCase(API_ViewWithLinkedDocs);
    RequireTestCase(API_SharedMapBlocks);
    RequireTestCase(API_LiveQuery);
    RequireTestCase(API_Model);

    RequireTestCase(API_Replicator);
}

#endif // DEBUG
