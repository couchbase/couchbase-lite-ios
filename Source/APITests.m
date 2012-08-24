//
//  Test_Touch.m
//  TouchDB
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

#import "TouchDB.h"
#import "Test.h"


#if DEBUG


static TouchDatabase* createEmptyDB(void) {
    TouchDatabaseManager* dbmgr = [TouchDatabaseManager sharedInstance];
    CAssert(dbmgr);
    NSError* error;
    TouchDatabase* db = [dbmgr databaseNamed: @"test_db"];
    if (db)
        CAssert([db deleteDatabase: &error], @"Couldn't delete old test_db: %@", error);
    db = [dbmgr createDatabaseNamed: @"test_db" error: &error];
    CAssert(db, @"Couldn't create db: %@", error);
    return db;
}


static TouchDocument* createDocumentWithProperties(TouchDatabase* db,
                                                   NSDictionary* properties) {
    TouchDocument* doc = [db untitledDocument];
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


static void createDocuments(TouchDatabase* db, unsigned n) {
    for (unsigned i=0; i<n; i++) {
        NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                    @"testDatabase", @"testName",
                                    [NSNumber numberWithInt: i], @"sequence",
                                    nil];
        createDocumentWithProperties(db, properties);
    }
}


#pragma mark - SERVER & DOCUMENTS:


TestCase(API_Server) {
    TouchDatabaseManager* dbmgr = [TouchDatabaseManager sharedInstance];
    CAssert(dbmgr);
    for (NSString* name in dbmgr.allDatabaseNames) {
        TouchDatabase* db = [dbmgr databaseNamed: name];
        Log(@"Database '%@': %u documents", db.name, (unsigned)db.documentCount);
    }
}


TestCase(API_CreateDocument) {
    TouchDatabase* db = createEmptyDB();
    NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"testCreateDocument", @"testName",
                                [NSNumber numberWithInt:1337], @"tag",
                                nil];
    TouchDocument* doc = createDocumentWithProperties(db, properties);
    
    NSString* docID = doc.documentID;
    CAssert(docID.length > 10, @"Invalid doc ID: '%@'", docID);
    NSString* currentRevisionID = doc.currentRevisionID;
    CAssert(currentRevisionID.length > 10, @"Invalid doc revision: '%@'", currentRevisionID);

    CAssertEqual(doc.userProperties, properties);
}


TestCase(API_CreateRevisions) {
    NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"testCreateRevisions", @"testName",
                                [NSNumber numberWithInt:1337], @"tag",
                                nil];
    TouchDatabase* db = createEmptyDB();
    TouchDocument* doc = createDocumentWithProperties(db, properties);
    TouchRevision* rev1 = doc.currentRevision;
    CAssert([rev1.revisionID hasPrefix: @"1-"]);
    
    NSMutableDictionary* properties2 = [[properties mutableCopy] autorelease];
    [properties2 setObject: [NSNumber numberWithInt: 4567] forKey: @"tag"];
    NSError* error;
    TouchRevision* rev2 = [rev1 putProperties: properties2 error: &error];
    CAssert(rev2, @"Put failed: %@", error);
    
    CAssert([doc.currentRevisionID hasPrefix: @"2-"],
                 @"Document revision ID is still %@", doc.currentRevisionID);
    
    CAssertEqual(rev2.revisionID, doc.currentRevisionID);
    CAssert(rev2.propertiesAreLoaded);
    CAssertEqual(rev2.userProperties, properties2);
    CAssertEq(rev2.document, doc);
}

#if 0
TestCase(API_SaveMultipleDocuments) {
    TouchDatabase* db = createEmptyDB();
    NSMutableArray* docs = [NSMutableArray array];
    for (int i=0; i<5; i++) {
        NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                    @"testSaveMultipleDocuments", @"testName",
                                    [NSNumber numberWithInt: i], @"sequence",
                                    nil];
        TouchDocument* doc = createDocumentWithProperties(db, properties);
        [docs addObject: doc];
    }
    
    NSMutableArray* revisions = [NSMutableArray array];
    NSMutableArray* revisionProperties = [NSMutableArray array];
    
    for (TouchDocument* doc in docs) {
        TouchRevision* revision = doc.currentRevision;
        CAssert([revision.revisionID hasPrefix: @"1-"],
                     @"Expected 1st revision: %@ in %@", doc.currentRevisionID, doc);
        NSMutableDictionary* properties = revision.properties.mutableCopy;
        [properties setObject: @"updated!" forKey: @"misc"];
        [revisions addObject: revision];
        [revisionProperties addObject: properties];
        [properties release];
    }
    
    CAssertWait([db putChanges: revisionProperties toRevisions: revisions]);
    
    for (TouchDocument* doc in docs) {
        CAssert([doc.currentRevisionID hasPrefix: @"2-"],
                     @"Expected 2nd revision: %@ in %@", doc.currentRevisionID, doc);
        CAssertEqual([doc.currentRevision.properties objectForKey: @"misc"],
                             @"updated!");
    }
}


TestCase(API_SaveMultipleUnsavedDocuments) {
    TouchDatabase* db = createEmptyDB();
    NSMutableArray* docs = [NSMutableArray array];
    NSMutableArray* docProperties = [NSMutableArray array];
    
    for (int i=0; i<5; i++) {
        TouchDocument* doc = [db untitledDocument];
        [docs addObject: doc];
        [docProperties addObject: [NSDictionary dictionaryWithObject: [NSNumber numberWithInt: i]
                                                              forKey: @"order"]];
    }
    
    CAssertWait([db putChanges: docProperties toRevisions: docs]);
    
    for (int i=0; i<5; i++) {
        TouchDocument* doc = [docs objectAtIndex: i];
        CAssert([doc.currentRevisionID hasPrefix: @"1-"],
                     @"Expected 2nd revision: %@ in %@", doc.currentRevisionID, doc);
        CAssertEqual([doc.currentRevision.properties objectForKey: @"order"],
                             [NSNumber numberWithInt: i]);
    }
}


TestCase(API_DeleteMultipleDocuments) {
    TouchDatabase* db = createEmptyDB();
    NSMutableArray* docs = [NSMutableArray array];
    for (int i=0; i<5; i++) {
        NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                    @"testDeleteMultipleDocuments", @"testName",
                                    [NSNumber numberWithInt: i], @"sequence",
                                    nil];
        TouchDocument* doc = createDocumentWithProperties(properties);
        [docs addObject: doc];
    }
    
    CAssertWait([db deleteDocuments: docs]);
    
    for (TouchDocument* doc in docs) {
        CAssert(doc.isDeleted);
    }
    
    CAssertEq([db getDocumentCount], (NSInteger)0);
}
#endif

TestCase(API_DeleteDocument) {
    TouchDatabase* db = createEmptyDB();
    NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"testDeleteDocument", @"testName",
                                nil];
    TouchDocument* doc = createDocumentWithProperties(db, properties);
    CAssert(!doc.isDeleted);
    NSError* error;
    CAssert([doc deleteDocument: &error]);
    CAssert(doc.isDeleted);
}


TestCase(API_AllDocuments) {
    TouchDatabase* db = createEmptyDB();
    static const NSUInteger kNDocs = 5;
    createDocuments(db, kNDocs);

    // clear the cache so all documents/revisions will be re-fetched:
    [db clearDocumentCache];
    
    Log(@"----- all documents -----");
    TouchQuery* query = [db queryAllDocuments];
    //query.prefetch = YES;
    Log(@"Getting all documents: %@", query);
    
    TouchQueryEnumerator* rows = query.rows;
    CAssertEq(rows.count, kNDocs);
    NSUInteger n = 0;
    for (TouchQueryRow* row in rows) {
        Log(@"    --> %@", row);
        TouchDocument* doc = row.document;
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
    TouchDatabase* db = createEmptyDB();
    static const NSUInteger kNDocs = 5;
    createDocuments(db, kNDocs);
    // clear the cache so all documents/revisions will be re-fetched:
    [db clearDocumentCache];
    
    TouchQuery* query = [db queryAllDocuments];
    query.prefetch = NO;    // Prefetching prevents view caching, so turn it off
    TouchQueryEnumerator* rows = query.rows;
    CAssertEq(rows.count, kNDocs);
    
    // Make sure the query is cached (view eTag hasn't changed):
    CAssertNil(query.rowsIfChanged);
    
    // Get the rows again to make sure caching isn't messing up:
    rows = query.rows;
    CAssertEq(rows.count, kNDocs);
}

#pragma mark - HISTORY

TestCase(API_History) {
    TouchDatabase* db = createEmptyDB();
    NSMutableDictionary* properties = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                @"test06_History", @"testName",
                                [NSNumber numberWithInt:1], @"tag",
                                nil];
    TouchDocument* doc = createDocumentWithProperties(db, properties);
    NSString* rev1ID = [[doc.currentRevisionID copy] autorelease];
    Log(@"1st revision: %@", rev1ID);
    CAssert([rev1ID hasPrefix: @"1-"], @"1st revision looks wrong: '%@'", rev1ID);
    CAssertEqual(doc.userProperties, properties);
    properties = [doc.properties.mutableCopy autorelease];
    [properties setObject: [NSNumber numberWithInt: 2] forKey: @"tag"];
    CAssert(![properties isEqual: doc.properties]);
    NSError* error;
    CAssert([doc putProperties: properties error: &error]);
    NSString* rev2ID = doc.currentRevisionID;
    Log(@"2nd revision: %@", rev2ID);
    CAssert([rev2ID hasPrefix: @"2-"], @"2nd revision looks wrong: '%@'", rev2ID);

    NSArray* revisions = [doc getRevisionHistory: &error];
    Log(@"Revisions = %@", revisions);
    CAssertEq(revisions.count, 2u);
    
    TouchRevision* rev1 = [revisions objectAtIndex: 0];
    CAssertEqual(rev1.revisionID, rev1ID);
    NSDictionary* gotProperties = rev1.properties;
    CAssertEqual([gotProperties objectForKey: @"tag"], [NSNumber numberWithInt: 1]);
    
    TouchRevision* rev2 = [revisions objectAtIndex: 1];
    CAssertEqual(rev2.revisionID, rev2ID);
    CAssertEq(rev2, doc.currentRevision);
    gotProperties = rev2.properties;
    CAssertEqual([gotProperties objectForKey: @"tag"], [NSNumber numberWithInt: 2]);
    
    CAssertEqual([doc getConflictingRevisions: &error],
                         [NSArray arrayWithObject: rev2]);
}


#if 0


#pragma mark - ATTACHMENTS


TestCase(API_Attachments) {
    TouchDatabase* db = createEmptyDB();
    NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"testAttachments", @"testName",
                                nil];
    TouchDocument* doc = createDocumentWithProperties(db, properties);
    TouchRevision* rev = doc.currentRevision;
    
    CAssertEq(rev.attachmentNames.count, (NSUInteger)0);
    CAssertNil([rev attachmentNamed: @"index.html"]);
    
    NSData* body = [@"This is a test attachment!" dataUsingEncoding: NSUTF8StringEncoding];
    TouchAttachment* attach = [doc putAttachmentWithName: @"index.html"
                                                    type: @"text/plain; charset=utf-8"
                                                    body: body];
    CAssert(attach);
    CAssertEq(attach.document, doc);
    CAssertEqual(attach.name, @"index.html");

    TouchRevision* rev2 = attach.revision;
    CAssertEq(rev2.document, doc);
    CAssert([rev2.revisionID hasPrefix: @"2-"]);
    Log(@"Now attachments = %@", rev2.attachmentNames);
    CAssertEqual(rev2.attachmentNames, [NSArray arrayWithObject: @"index.html"]);

    attach = [rev2 attachmentNamed: @"index.html"];
    CAssertEqual(attach.contentType, @"text/plain; charset=utf-8");
    CAssertEqual(attach.body, body);
    CAssertEq(attach.length, (UInt64)body.length);
}


#endif


#pragma mark - CHANGE TRACKING


TestCase(API_ChangeTracking) {
    TouchDatabase* db = createEmptyDB();
    __block int changeCount = 0;
    [[NSNotificationCenter defaultCenter] addObserverForName: kTouchDatabaseChangeNotification
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
    TouchDatabase* db = createEmptyDB();

    TouchView* view = [db viewNamed: @"vu"];
    CAssert(view);
    CAssertEq(view.database, db);
    CAssertEqual(view.name, @"vu");
    CAssertNull(view.mapBlock);
    CAssertNull(view.reduceBlock);

    [view setMapBlock:^(NSDictionary *doc, TDMapEmitBlock emit) {
        emit([doc objectForKey: @"sequence"], nil);
    } version: @"1"];

    CAssert(view.mapBlock != nil);

    static const NSUInteger kNDocs = 50;
    createDocuments(db, kNDocs);

    TouchQuery* query = [view query];
    CAssertEq(query.database, db);
    query.startKey = [NSNumber numberWithInt: 23];
    query.endKey = [NSNumber numberWithInt: 33];
    TouchQueryEnumerator* rows = query.rows;
    CAssert(rows);
    CAssertEq(rows.count, (NSUInteger)11);

    int expectedKey = 23;
    for (TouchQueryRow* row in rows) {
        CAssertEq([row.key intValue], expectedKey);
        ++expectedKey;
    }
}


#if 0
TestCase(API_RunSlowView) {
    TouchDatabase* db = createEmptyDB();
    static const NSUInteger kNDocs = 50;
    [self createDocuments: kNDocs];
    
    TouchQuery* query = [db slowQueryWithMap: @"function(doc){emit(doc.sequence,null);};"];
    query.startKey = [NSNumber numberWithInt: 23];
    query.endKey = [NSNumber numberWithInt: 33];
    TouchQueryEnumerator* rows = query.rows;
    CAssert(rows);
    CAssertEq(rows.count, (NSUInteger)11);
    CAssertEq(rows.totalCount, kNDocs);
    
    int expectedKey = 23;
    for (TouchQueryRow* row in rows) {
        CAssertEq([row.key intValue], expectedKey);
        ++expectedKey;
    }
}
#endif


TestCase(API_Validation) {
    TouchDatabase* db = createEmptyDB();

    [db defineValidation: @"uncool"
                 asBlock: ^BOOL(TDRevision *newRevision, id<TDValidationContext> context) {
                     if (!newRevision.properties[@"groovy"]) {
                         context.errorMessage = @"uncool";
                         return NO;
                     }
                     return YES;
                 }];
    
    NSDictionary* properties = @{ @"groovy" : @"right on", @"foo": @"bar" };
    TouchDocument* doc = [db untitledDocument];
    NSError *error;
    CAssert([doc putProperties: properties error: &error]);
    
    properties = @{ @"foo": @"bar" };
    doc = [db untitledDocument];
    CAssert(![doc putProperties: properties error: &error]);
    CAssertEq(error.code, 403);
    //CAssertEqual(error.localizedDescription, @"forbidden: uncool"); //TODO: Not hooked up yet
}


TestCase(API_ViewWithLinkedDocs) {
    TouchDatabase* db = createEmptyDB();
    static const NSUInteger kNDocs = 50;
    NSMutableArray* docs = [NSMutableArray array];
    NSString* lastDocID = @"";
    for (NSUInteger i=0; i<kNDocs; i++) {
        NSDictionary* properties = @{ @"sequence" : @(i),
                                      @"prev": lastDocID };
        TouchDocument* doc = createDocumentWithProperties(db, properties);
        [docs addObject: doc];
        lastDocID = doc.documentID;
    }
    
    // The map function will emit the ID of the previous document, causing that document to be
    // included when include_docs (aka prefetch) is enabled.
    TouchQuery* query = [db slowQueryWithMap: ^(NSDictionary *doc, TDMapEmitBlock emit) {
        emit(doc[@"sequence"], @{ @"_id": doc[@"prev"] });
    }];
    query.startKey = @23;
    query.endKey = @33;
    query.prefetch = YES;
    TouchQueryEnumerator* rows = query.rows;
    CAssert(rows);
    CAssertEq(rows.count, (NSUInteger)11);
    
    int rowNumber = 23;
    for (TouchQueryRow* row in rows) {
        CAssertEq([row.key intValue], rowNumber);
        TouchDocument* prevDoc = [docs objectAtIndex: rowNumber-1];
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
    TouchDocument* doc = createDocumentWithProperties(properties);
    
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
    TouchDocument *designDocument = [self.db documentWithID:designDocumentId];
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
    TouchDatabase* db = createEmptyDB();
    createDocuments(db, 5);

    TouchView* view = [db viewNamed: @"vu"];
    [view setMapBlock: ^(NSDictionary *doc, TDMapEmitBlock emit) {
        emit(doc[@"_id"], doc[@"_local_seq"]);
    } version: @"1"];
        
    TouchQuery* query = [view query];
    TouchQueryEnumerator* rows = query.rows;
    for (TouchQueryRow* row in rows) {
        CAssertEqual(row.value, nil);
        Log(@"row _id = %@, local_seq = %@", row.key, row.value);
    }
    
    query.sequences = YES;
    rows = query.rows;
    for (TouchQueryRow* row in rows) {
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
    RequireTestCase(API_AllDocuments);
    RequireTestCase(API_RowsIfChanged);
    RequireTestCase(API_History);
    RequireTestCase(API_ChangeTracking);
    RequireTestCase(API_CreateView);
    RequireTestCase(API_Validation);
    RequireTestCase(API_ViewWithLinkedDocs);
//    RequireTestCase(API_ViewOptions);
}

#endif // DEBUG
