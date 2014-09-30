//
//  APIViewTests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/8/14.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#if DEBUG
#import "APITestUtils.h"


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
    CBLQueryEnumerator* rows = [query run: NULL];
    CAssert(rows);
    CAssertEq(rows.count, (NSUInteger)11);

    int expectedKey = 23;
    for (CBLQueryRow* row in rows) {
        CAssertEq([row.key intValue], expectedKey);
        CAssertEq(row.sequenceNumber, (UInt64)expectedKey+1);
        ++expectedKey;
    }
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
    CBLQueryEnumerator* rows = [query run: NULL];
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


TestCase(API_EmitNil) {
    RequireTestCase(API_CreateView);
    CBLDatabase* db = createEmptyDB();
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    CBLDocument* doc1 = createDocumentWithProperties(db, @{@"sequence": @1});
    __unused CBLDocument* doc2 = createDocumentWithProperties(db, @{@"sequence": @2});
    CBLQuery* query = view.createQuery;
    NSArray* result1 = [[query run: NULL] allObjects];
    AssertEqual([(CBLQueryRow*)result1[0] key], @1);
    AssertEqual([(CBLQueryRow*)result1[0] value], nil);
    AssertEqual([(CBLQueryRow*)result1[1] key], @2);
    AssertEqual([(CBLQueryRow*)result1[1] value], nil);

    // Update doc1
    [doc1 update:^BOOL(CBLUnsavedRevision *rev) {
        rev[@"something"] = @"else";
        return YES;
    } error: NULL];

    // Query again and verify that the results sets are not considered equal:
    NSArray* result2 = [[query run: NULL] allObjects];
    Assert(![result2 isEqual: result1]);
    AssertEqual([(CBLQueryRow*)result2[0] key], @1);
    AssertEqual([(CBLQueryRow*)result2[0] value], nil);
}


TestCase(API_EmitDoc) {
    RequireTestCase(API_CreateView);
    CBLDatabase* db = createEmptyDB();
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], doc);
    }) version: @"1"];

    CBLDocument* doc1 = createDocumentWithProperties(db, @{@"sequence": @1});
    CBLDocument* doc2 = createDocumentWithProperties(db, @{@"sequence": @2});
    CBLQuery* query = view.createQuery;
    NSArray* result1 = [[query run: NULL] allObjects];
    AssertEqual([(CBLQueryRow*)result1[0] key], @1);
    AssertEqual([(CBLQueryRow*)result1[0] value], doc1.properties);
    AssertEqual([(CBLQueryRow*)result1[1] key], @2);
    AssertEqual([(CBLQueryRow*)result1[1] value], doc2.properties);
    NSDictionary* initialDoc1Properties = doc1.properties;

    // Update doc1
    [doc1 update:^BOOL(CBLUnsavedRevision *rev) {
        rev[@"something"] = @"else";
        return YES;
    } error: NULL];

    // Query again and verify that the results sets are not considered equal:
    NSArray* result2 = [[query run: NULL] allObjects];
    Assert(![result2 isEqual: result1]);
    AssertEqual([(CBLQueryRow*)result2[0] key], @1);
    AssertEqual([(CBLQueryRow*)result2[0] value], doc1.properties);

    // Rows from initial query should still return the revisions they were created with:
    AssertEqual([(CBLQueryRow*)result1[0] key], @1);
    AssertEqual([(CBLQueryRow*)result1[0] value], initialDoc1Properties); // i.e. _not_ doc1.properties
}


TestCase(API_ViewCustomSort) {
    RequireTestCase(CBLQuery_KeyPathForQueryRow);
    CBLDatabase* db = createEmptyDB();

    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"name"], doc[@"skin"]);
    }) version: @"1"];

    CAssert(view.mapBlock != nil);

    [db inTransaction: ^BOOL {
        createDocumentWithProperties(db, @{@"name": @"Barry", @"skin": @"none"});
        createDocumentWithProperties(db, @{@"name": @"Terry", @"skin": @"furry"});
        createDocumentWithProperties(db, @{@"name": @"Wanda", @"skin": @"scaly"});
        return YES;
    }];

    CBLQuery* query = [view createQuery];
    query.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey: @"value" ascending: NO]];
    CBLQueryEnumerator* rows = [query run: NULL];

    AssertEqual(rows.nextRow.value, @"scaly");
    AssertEqual(rows.nextRow.value, @"none");
    AssertEqual(rows.nextRow.value, @"furry");
    AssertNil(rows.nextRow);

    // Now test a keypath that implicitly refers to the value:
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"name"], @{@"skin": doc[@"skin"]});
    }) version: @"2"];

    query.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey: @"value.skin" ascending: NO]];
    rows = [query run: NULL];

    AssertEqual(rows.nextRow.value, @{@"skin": @"scaly"});
    AssertEqual(rows.nextRow.value, @{@"skin": @"none"});
    AssertEqual(rows.nextRow.value, @{@"skin": @"furry"});
    AssertNil(rows.nextRow);

    // Now test a keypath with an array:
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"name"], @[doc[@"skin"]]);
    }) version: @"3"];

    query.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey: @"value[0]" ascending: NO]];
    rows = [query run: NULL];

    AssertEqual(rows.nextRow.value, @[@"scaly"]);
    AssertEqual(rows.nextRow.value, @[@"none"]);
    AssertEqual(rows.nextRow.value, @[@"furry"]);
    AssertNil(rows.nextRow);
}


TestCase(API_ViewCustomFilter) {
    CBLDatabase* db = createEmptyDB();

    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"name"], doc[@"skin"]);
    }) version: @"1"];

    CAssert(view.mapBlock != nil);

    [db inTransaction: ^BOOL {
        createDocumentWithProperties(db, @{@"name": @"Barry", @"skin": @"none"});
        createDocumentWithProperties(db, @{@"name": @"Terry", @"skin": @"furry"});
        createDocumentWithProperties(db, @{@"name": @"Wanda", @"skin": @"scaly"});
        return YES;
    }];

    CBLQuery* query = [view createQuery];
    query.postFilter = [NSPredicate predicateWithFormat: @"value endswith 'y'"];
    CBLQueryEnumerator* rows = [query run: NULL];

    AssertEqual(rows.nextRow.value, @"furry");
    AssertEqual(rows.nextRow.value, @"scaly");
    AssertNil(rows.nextRow);
}


TestCase(API_AllDocsCustomFilter) {
    CBLDatabase* db = createEmptyDB();

    [db inTransaction: ^BOOL {
        createDocumentWithProperties(db, @{@"_id": @"1", @"name": @"Barry", @"skin": @"none"});
        createDocumentWithProperties(db, @{@"_id": @"2", @"name": @"Terry", @"skin": @"furry"});
        createDocumentWithProperties(db, @{@"_id": @"3", @"name": @"Wanda", @"skin": @"scaly"});
        return YES;
    }];
    [db _clearDocumentCache];

    Log(@" ---- QUERYIN' ----");
    CBLQuery* query = [db createAllDocumentsQuery];
    query.postFilter = [NSPredicate predicateWithFormat: @"document.properties.skin endswith 'y'"];
    CBLQueryEnumerator* rows = [query run: NULL];

    AssertEqual(rows.nextRow.key, @"2");
    AssertEqual(rows.nextRow.key, @"3");
    AssertNil(rows.nextRow);
}


#pragma mark - LIVE QUERIES:


TestCase(API_LiveQuery) {
    RequireTestCase(API_CreateView);
    CBLDatabase* db = createManagerAndEmptyDBAtPath(@"API_LiveQuery");
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
    while (!finished && timeout.timeIntervalSinceNow > 0.0) {
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
}


@interface TestLiveQueryObserver : NSObject
@property (copy) NSDictionary*change;
@property unsigned changeCount;
@end

@implementation TestLiveQueryObserver
@synthesize change=_change, changeCount=_changeCount;
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    self.change = change;
    ++_changeCount;
}
@end


TestCase(API_LiveQuery_DispatchQueue) {
    RequireTestCase(API_LiveQuery);
    CBLManager* dbmgr = [CBLManager createEmptyAtTemporaryPath: @"LiveQuery_DispatchQueue"];
    dispatch_queue_t queue = dispatch_queue_create("LiveQuery", NULL);
    dbmgr.dispatchQueue = queue;
    __block CBLDatabase* db;
    __block CBLView* view;
    __block CBLLiveQuery* query;
    TestLiveQueryObserver* observer = [[TestLiveQueryObserver alloc] init];
    dispatch_sync(queue, ^{
        NSError* error;
        db = [dbmgr createEmptyDatabaseNamed: @"test_db" error: &error];
        view = [db viewNamed: @"vu"];
        [view setMapBlock: MAPBLOCK({
            emit(doc[@"sequence"], nil);
        }) version: @"1"];

        static const NSUInteger kNDocs = 50;
        createDocuments(db, kNDocs);

        query = [[view createQuery] asLiveQuery];
        query.startKey = @23;
        query.endKey = @33;
        Log(@"Created %@", query);
        CAssertNil(query.rows);

        [query addObserver: observer forKeyPath: @"rows" options: NSKeyValueObservingOptionNew context: NULL];
    });

    Log(@"Waiting for live query to complete...");
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    bool finished = false;
    while (!finished && timeout.timeIntervalSinceNow > 0.0) {
        usleep(1000);
        if (observer.change) {
            CBLQueryEnumerator* rows = observer.change[NSKeyValueChangeNewKey];
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
    }
    Assert(finished, @"LiveQuery didn't complete");

    dispatch_async(queue, ^{
        NSDictionary* properties = @{@"testName": @"testDatabase", @"sequence": @(23.5)};
        createDocumentWithProperties(db, properties);
    });

    Log(@"Waiting for live query to update again...");
    timeout = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    finished = false;
    while (!finished && timeout.timeIntervalSinceNow > 0.0) {
        usleep(1000);
        if (observer.changeCount == 2) {
            CBLQueryEnumerator* rows = observer.change[NSKeyValueChangeNewKey];
            Log(@"Live query rows = %@", rows);
            if (rows != nil) {
                CAssertEq(rows.count, (NSUInteger)12);
                finished = true;
            }
        }
    }
    Assert(finished, @"LiveQuery didn't update");

    // Clean up:
    dispatch_sync(queue, ^{
        [query removeObserver: observer forKeyPath: @"rows"];
        [query stop];
        [dbmgr close];
    });
}


TestCase(API_AsyncViewQuery) {
    RequireTestCase(API_CreateView);
    CBLDatabase* db = createManagerAndEmptyDBAtPath(@"API_AsyncViewQuery");
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
}

// Ensure that when the view mapblock changes, a related live query
// will be notified and automatically updated
TestCase(API_LiveQuery_UpdatesWhenViewChanges) {
    CBLDatabase* db = createManagerAndEmptyDBAtPath(@"UpdatesWhenViewChanges");
    
    CBLView* view = [db viewNamed: @"vu"];
    
    [view setMapBlock: MAPBLOCK({
        emit(@1, nil);
    }) version: @"1"];
    
    createDocuments(db, 1);
    
    CBLQuery* query = [view createQuery];
    CBLQueryEnumerator* rows = [query run: NULL];
    CAssertEq(rows.count, (NSUInteger)1);
    
    int expectedKey = 1;
    for (CBLQueryRow* row in rows) {
        CAssertEq([row.key intValue], expectedKey);
    }
    
    CBLLiveQuery* liveQuery = [[view createQuery] asLiveQuery];
//    CAssertNil(liveQuery.rows);
    
    TestLiveQueryObserver* observer = [TestLiveQueryObserver new];

    [liveQuery addObserver: observer forKeyPath: @"rows" options: NSKeyValueObservingOptionNew context: NULL];
    
    Log(@"Waiting for live query to update...");
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    bool finished = false;
    while (!finished && timeout.timeIntervalSinceNow > 0.0) {

        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;

        if (observer.changeCount == 1) {
            
            CBLQueryEnumerator* rows = liveQuery.rows;
            Log(@"Live query rows = %@", rows);
            if (rows != nil) {
                CAssertEq(rows.count, (NSUInteger)1);
                
                int expectedKey = 1;
                for (CBLQueryRow* row in rows) {
                    CAssertEq([row.key intValue], expectedKey);
                }
                finished = true;
            }
        }

    }
    CAssert(finished, @"Live query timed out!");

    // now update the view definition, while the live query is running
    [view setMapBlock: MAPBLOCK({
        emit(@2, nil);
    }) version: @"2"];
    
    Log(@"Waiting for live query to update...");
    timeout = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    finished = false;
    while (!finished && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;
        
        if (observer.changeCount == 2) {
            
            CBLQueryEnumerator* rows = liveQuery.rows;
            Log(@"Live query rows = %@", rows);
            if (rows != nil) {
                CAssertEq(rows.count, (NSUInteger)1);
                
                int expectedKey = 2;
                for (CBLQueryRow* row in rows) {
                    CAssertEq([row.key intValue], expectedKey);
                }
                finished = true;
            }

        }
        
    }
    CAssert(finished, @"Live query timed out!");
    
    [liveQuery stop];
    [liveQuery removeObserver:observer forKeyPath:@"rows"];
}


// Make sure that a database's map/reduce functions are shared with the shadow database instance
// running in the background server.
TestCase(API_SharedMapBlocks) {
    CBLManager* mgr = [CBLManager createEmptyAtTemporaryPath: @"API_SharedMapBlocks"];
    CBLDatabase* db = [mgr databaseNamed: @"db" error: nil];
    [db setFilterNamed: @"phil" asBlock: ^BOOL(CBLSavedRevision *revision, NSDictionary *params) {
        return YES;
    }];
    [db setValidationNamed: @"val" asBlock: VALIDATIONBLOCK({ })];
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
    [mgr close];
}




TestCase(API_View) {
    RequireTestCase(API_CreateView);
    RequireTestCase(API_ViewCustomSort);
    RequireTestCase(API_ViewCustomFilter);
    RequireTestCase(API_AllDocsCustomFilter);
    RequireTestCase(API_ViewWithLinkedDocs);
    RequireTestCase(API_SharedMapBlocks);
    RequireTestCase(API_EmitNil);
    RequireTestCase(API_EmitDoc);
    RequireTestCase(API_LiveQuery);
    RequireTestCase(API_LiveQuery_DispatchQueue);
    RequireTestCase(API_AsyncViewQuery);
}


#endif // DEBUG
