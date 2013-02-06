//
//  APITests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/12/11.
//  Copyright 2011 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLite.h"
#import "Test.h"


#if DEBUG


static CBLDatabase* createEmptyDB(void) {
    CBLManager* dbmgr = [CBLManager sharedInstance];
    CAssert(dbmgr);
    NSError* error;
    CBLDatabase* db = dbmgr[@"test_db"];
    if (db)
        CAssert([db deleteDatabase: &error], @"Couldn't delete old test_db: %@", error);
    db = [dbmgr createDatabaseNamed: @"test_db" error: &error];
    CAssert(db, @"Couldn't create db: %@", error);
    return db;
}


static CBLDocument* createDocumentWithProperties(CBLDatabase* db,
                                                   NSDictionary* properties) {
    CBLDocument* doc = [db untitledDocument];
    CAssert(doc != nil);
    CAssertNil(doc.currentRevisionID);
    CAssertNil(doc.currentRevision);
    CAssert(doc.documentID, @"Document has no ID"); // 'untitled' docs are no longer untitled (8/10/12)

    NSError* error;
    CAssert([doc putProperties: properties error: &error], @"Couldn't save: %@", error);  // save it!
    
    CAssert(doc.documentID);
    CAssert(doc.currentRevisionID);
    CAssertEqual(doc.userProperties, properties);
    CAssertEq([db documentWithID: doc.documentID], doc);
    Log(@"Created %p = %@", doc, doc);
    return doc;
}


static void createDocuments(CBLDatabase* db, unsigned n) {
    for (unsigned i=0; i<n; i++) {
        NSDictionary* properties = @{@"testName": @"testDatabase", @"sequence": @(i)};
        createDocumentWithProperties(db, properties);
    }
}


#pragma mark - SERVER & DOCUMENTS:


TestCase(API_Server) {
    CBLManager* dbmgr = [CBLManager sharedInstance];
    CAssert(dbmgr);
    for (NSString* name in dbmgr.allDatabaseNames) {
        CBLDatabase* db = dbmgr[name];
        Log(@"Database '%@': %u documents", db.name, (unsigned)db.documentCount);
    }
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
}


TestCase(API_CreateRevisions) {
    RequireTestCase(API_CreateDocument);
    NSDictionary* properties = @{@"testName": @"testCreateRevisions",
    @"tag": @1337};
    CBLDatabase* db = createEmptyDB();
    CBLDocument* doc = createDocumentWithProperties(db, properties);
    CBLRevision* rev1 = doc.currentRevision;
    CAssert([rev1.revisionID hasPrefix: @"1-"]);

    NSMutableDictionary* properties2 = [properties mutableCopy];
    properties2[@"tag"] = @4567;
    NSError* error;
    CBLRevision* rev2 = [rev1 putProperties: properties2 error: &error];
    CAssert(rev2, @"Put failed: %@", error);

    CAssert([doc.currentRevisionID hasPrefix: @"2-"],
            @"Document revision ID is still %@", doc.currentRevisionID);

    CAssertEqual(rev2.revisionID, doc.currentRevisionID);
    CAssert(rev2.propertiesAreLoaded);
    CAssertEqual(rev2.userProperties, properties2);
    CAssertEq(rev2.document, doc);
}

TestCase(API_CreateNewRevisions) {
    RequireTestCase(API_CreateRevisions);
    NSDictionary* properties = @{@"testName": @"testCreateRevisions",
    @"tag": @1337};
    CBLDatabase* db = createEmptyDB();
    CBLDocument* doc = [db untitledDocument];
    CBLNewRevision* newRev = [doc newRevision];

    CAssertEq(newRev.document, doc);
    CAssertEq(newRev.database, db);
    CAssertNil(newRev.parentRevisionID);
    CAssertNil(newRev.parentRevision);
    CAssertEqual(newRev.properties, $mdict({@"_id", doc.documentID}));

    newRev[@"testName"] = @"testCreateRevisions";
    newRev[@"tag"] = @1337;
    CAssertEqual(newRev.userProperties, properties);

    NSError* error;
    CBLRevision* rev1 = [newRev save: &error];
    CAssert(rev1, @"Save 1 failed: %@", error);
    CAssertEqual(rev1, doc.currentRevision);
    CAssert([rev1.revisionID hasPrefix: @"1-"]);

    newRev = [rev1 newRevision];
    CAssertEq(newRev.document, doc);
    CAssertEq(newRev.database, db);
    CAssertEq(newRev.parentRevisionID, rev1.revisionID);
    CAssertEqual(newRev.parentRevision, rev1);
    CAssertEqual(newRev.properties, rev1.properties);
    CAssertEqual(newRev.userProperties, rev1.userProperties);

    newRev[@"tag"] = @4567;
    CBLRevision* rev2 = [newRev save: &error];
    CAssert(rev2, @"Save 2 failed: %@", error);
    CAssertEqual(rev2, doc.currentRevision);
    CAssert([rev2.revisionID hasPrefix: @"2-"]);

    CAssert([doc.currentRevisionID hasPrefix: @"2-"],
            @"Document revision ID is still %@", doc.currentRevisionID);
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
    }
    
    CAssertEq([db getDocumentCount], (NSInteger)0);
}
#endif

TestCase(API_DeleteDocument) {
    CBLDatabase* db = createEmptyDB();
    NSDictionary* properties = @{@"testName": @"testDeleteDocument"};
    CBLDocument* doc = createDocumentWithProperties(db, properties);
    CAssert(!doc.isDeleted);
    NSError* error;
    CAssert([doc deleteDocument: &error]);
    CAssert(doc.isDeleted);
}


TestCase(API_PurgeDocument) {
    CBLDatabase* db = createEmptyDB();
    NSDictionary* properties = @{@"testName": @"testPurgeDocument"};
    CBLDocument* doc = createDocumentWithProperties(db, properties);
    CAssert(doc);
    
    NSError* error;
    CAssert([doc purgeDocument: &error]);
    
    CBLDocument* redoc = [db cachedDocumentWithID:doc.documentID];
    CAssert(!redoc);
}

TestCase(API_AllDocuments) {
    CBLDatabase* db = createEmptyDB();
    static const NSUInteger kNDocs = 5;
    createDocuments(db, kNDocs);

    // clear the cache so all documents/revisions will be re-fetched:
    [db clearDocumentCache];
    
    Log(@"----- all documents -----");
    CBLQuery* query = [db queryAllDocuments];
    //query.prefetch = YES;
    Log(@"Getting all documents: %@", query);
    
    CBLQueryEnumerator* rows = query.rows;
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
}


TestCase(API_RowsIfChanged) {
    CBLDatabase* db = createEmptyDB();
    static const NSUInteger kNDocs = 5;
    createDocuments(db, kNDocs);
    // clear the cache so all documents/revisions will be re-fetched:
    [db clearDocumentCache];
    
    CBLQuery* query = [db queryAllDocuments];
    query.prefetch = NO;    // Prefetching prevents view caching, so turn it off
    CBLQueryEnumerator* rows = query.rows;
    CAssertEq(rows.count, kNDocs);
    
    // Make sure the query is cached (view eTag hasn't changed):
    CAssertNil(query.rowsIfChanged);
    
    // Get the rows again to make sure caching isn't messing up:
    rows = query.rows;
    CAssertEq(rows.count, kNDocs);
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
    
    CBLRevision* rev1 = revisions[0];
    CAssertEqual(rev1.revisionID, rev1ID);
    NSDictionary* gotProperties = rev1.properties;
    CAssertEqual(gotProperties[@"tag"], @1);
    
    CBLRevision* rev2 = revisions[1];
    CAssertEqual(rev2.revisionID, rev2ID);
    CAssertEq(rev2, doc.currentRevision);
    gotProperties = rev2.properties;
    CAssertEqual(gotProperties[@"tag"], @2);
    
    CAssertEqual([doc getConflictingRevisions: &error], @[rev2]);
}


#pragma mark - ATTACHMENTS

TestCase(API_Attachments) {
    CBLDatabase* db = createEmptyDB();
    NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"testAttachments", @"testName",
                                nil];
    CBLDocument* doc = createDocumentWithProperties(db, properties);
    CBLRevision* rev = doc.currentRevision;
    
    CAssertEq(rev.attachmentNames.count, (NSUInteger)0);
    CAssertNil([rev attachmentNamed: @"index.html"]);
    
    NSData* body = [@"This is a test attachment!" dataUsingEncoding: NSUTF8StringEncoding];
    CBLAttachment* attach = [[CBLAttachment alloc] initWithContentType:@"text/plain; charset=utf-8" body:body];
    CAssert(attach);
    
    CBLNewRevision *rev2 = [doc newRevision];
    [rev2 addAttachment:attach named:@"index.html"];
    
    NSError * error;
    CBLRevision *rev3 = [rev2 save:&error];
    
    CAssertNil(error);
    CAssert(rev3);
    CAssertEq(rev3.attachmentNames.count, (NSUInteger)1);
    
    attach = [rev3 attachmentNamed:@"index.html"];
    CAssert(attach);
    CAssertEq(attach.document, doc);
    CAssertEqual(attach.name, @"index.html");
    CAssertEqual(rev3.attachmentNames, [NSArray arrayWithObject: @"index.html"]);
    
    CAssertEqual(attach.contentType, @"text/plain; charset=utf-8");
    CAssertEqual(attach.body, body);
    CAssertEq(attach.length, (UInt64)body.length);

    CBLRevision *rev4 = [attach updateBody:nil contentType:nil error:&error];
    CAssert(!error);
    CAssert(rev4);
    CAssertEq([rev4.attachmentNames count], (NSUInteger)0);
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

    [view setMapBlock:^(NSDictionary *doc, CBLMapEmitBlock emit) {
        emit(doc[@"sequence"], nil);
    } version: @"1"];

    CAssert(view.mapBlock != nil);

    static const NSUInteger kNDocs = 50;
    createDocuments(db, kNDocs);

    CBLQuery* query = [view query];
    CAssertEq(query.database, db);
    query.startKey = @23;
    query.endKey = @33;
    CBLQueryEnumerator* rows = query.rows;
    CAssert(rows);
    CAssertEq(rows.count, (NSUInteger)11);

    int expectedKey = 23;
    for (CBLQueryRow* row in rows) {
        CAssertEq([row.key intValue], expectedKey);
        ++expectedKey;
    }
}


#if 0
TestCase(API_RunSlowView) {
    CBLDatabase* db = createEmptyDB();
    static const NSUInteger kNDocs = 50;
    [self createDocuments: kNDocs];
    
    CBLQuery* query = [db slowQueryWithMap: @"function(doc){emit(doc.sequence,null);};"];
    query.startKey = [NSNumber numberWithInt: 23];
    query.endKey = [NSNumber numberWithInt: 33];
    CBLQueryEnumerator* rows = query.rows;
    CAssert(rows);
    CAssertEq(rows.count, (NSUInteger)11);
    CAssertEq(rows.totalCount, kNDocs);
    
    int expectedKey = 23;
    for (CBLQueryRow* row in rows) {
        CAssertEq([row.key intValue], expectedKey);
        ++expectedKey;
    }
}
#endif


TestCase(API_Validation) {
    CBLDatabase* db = createEmptyDB();

    [db defineValidation: @"uncool"
                 asBlock: ^BOOL(CBLRevision *newRevision, id<CBLValidationContext> context) {
                     if (!newRevision.properties[@"groovy"]) {
                         context.errorMessage = @"uncool";
                         return NO;
                     }
                     return YES;
                 }];
    
    NSDictionary* properties = @{ @"groovy" : @"right on", @"foo": @"bar" };
    CBLDocument* doc = [db untitledDocument];
    NSError *error;
    CAssert([doc putProperties: properties error: &error]);
    
    properties = @{ @"foo": @"bar" };
    doc = [db untitledDocument];
    CAssert(![doc putProperties: properties error: &error]);
    CAssertEq(error.code, 403);
    //CAssertEqual(error.localizedDescription, @"forbidden: uncool"); //TODO: Not hooked up yet
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
    CBLQuery* query = [db slowQueryWithMap: ^(NSDictionary *doc, CBLMapEmitBlock emit) {
        emit(doc[@"sequence"], @{ @"_id": doc[@"prev"] });
    }];
    query.startKey = @23;
    query.endKey = @33;
    query.prefetch = YES;
    CBLQueryEnumerator* rows = query.rows;
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
}


#if 0
#pragma mark - Custom Path Maps

- (void) test_GetDocument_using_a_custom_path_map {
    NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"testCreateDocument", @"testName",
                                [NSNumber numberWithInt:1337], @"tag",
                                nil];
    CBLDocument* doc = createDocumentWithProperties(properties);
    
    NSString* docID = doc.documentID;
    CAssert(docID.length > 10, @"Invalid doc ID: '%@'", docID);
    NSString* currentRevisionID = doc.currentRevisionID;
    CAssert(currentRevisionID.length > 10, @"Invalid doc revision: '%@'", currentRevisionID);
    
    CAssertEqual(doc.userProperties, properties, @"Couldn't get doc properties");

    // Use a show function for testing the GET. A show function would not normally work well because it is read-only.
    NSString *showFunction = @"function(doc, req) { doc.showValue = 'show'; return JSON.stringify(doc);}";
    NSString *showFunctionName = @"myshow";
    NSDictionary *showsJson = [NSDictionary dictionaryWithObject:showFunction forKey:showFunctionName];
    NSString *designDocumentId = @"_design/testPathMap";
    NSDictionary *designDocumentProperties = [NSDictionary dictionaryWithObject:showsJson forKey:@"shows"];
    CBLDocument *designDocument = [self.db documentWithID:designDocumentId];
    [[designDocument putProperties:designDocumentProperties] wait];
    
    self.db.documentPathMap = ^(NSString *docId) {
        return [NSString stringWithFormat:@"%@/_show/%@/%@", designDocumentId, showFunctionName, docId];
    };
    
    NSMutableDictionary *expectedProperties = [properties mutableCopy];
    [expectedProperties setObject:@"show" forKey:@"showValue"];

    doc = [self.db documentWithID:docID];
    
    RESTOperation* op = CAssertWait([doc GET]);
    CAssertEq(op.httpStatus, 200, @"GET failed");
    
    CAssertEqual(doc.userProperties, expectedProperties, @"Couldn't get doc properties after GET");

    // Try it again
    doc = [self.db documentWithID:docID];
    
    op = CAssertWait([doc GET]);
    CAssertEq(op.httpStatus, 200, @"GET failed");
    
    CAssertEqual(doc.userProperties, expectedProperties, @"Couldn't get doc properties after GET");
}


TestCase(API_ViewOptions) {
    CBLDatabase* db = createEmptyDB();
    createDocuments(db, 5);

    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: ^(NSDictionary *doc, CBLMapEmitBlock emit) {
        emit(doc[@"_id"], doc[@"_local_seq"]);
    } version: @"1"];
        
    CBLQuery* query = [view query];
    CBLQueryEnumerator* rows = query.rows;
    for (CBLQueryRow* row in rows) {
        CAssertEqual(row.value, nil);
        Log(@"row _id = %@, local_seq = %@", row.key, row.value);
    }
    
    query.sequences = YES;
    rows = query.rows;
    for (CBLQueryRow* row in rows) {
        CAssert([row.value isKindOfClass: [NSNumber class]], @"Unexpected value: %@", row.value);
        Log(@"row _id = %@, local_seq = %@", row.key, row.value);
    }
}
#endif


TestCase(API) {
    RequireTestCase(API_Server);
    RequireTestCase(API_CreateDocument);
    RequireTestCase(API_CreateRevisions);
    RequireTestCase(API_SaveMultipleDocuments);
    RequireTestCase(API_SaveMultipleUnsavedDocuments);
    RequireTestCase(API_DeleteMultipleDocuments);
    RequireTestCase(API_DeleteDocument);
    RequireTestCase(API_PurgeDocument);
    RequireTestCase(API_AllDocuments);
    RequireTestCase(API_RowsIfChanged);
    RequireTestCase(API_History);
    RequireTestCase(API_Attachments);
    RequireTestCase(API_ChangeTracking);
    RequireTestCase(API_CreateView);
    RequireTestCase(API_Validation);
    RequireTestCase(API_ViewWithLinkedDocs);
//    RequireTestCase(API_ViewOptions);
}

#endif // DEBUG
