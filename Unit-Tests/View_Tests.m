//
//  View_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/19/14.
//
//

#import "CBLTestCase.h"
#import "CBLInternal.h"
#import "CBLQueryRow+Router.h"
#import "MYBlockUtils.h"


@interface CBLView (Private)
@property SequenceNumber lastSequenceChangedAt;
@end


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
    Log(@"TestLiveQueryObserver -- change #%u", _changeCount);
}
@end


@interface View_Tests : CBLTestCaseWithDB
@end


@implementation View_Tests


- (void) test01_CreateView {
    CBLView* view = [db viewNamed: @"vu"];
    Assert(view);
    AssertEq(view.database, db);
    AssertEqual(view.name, @"vu");
    Assert(view.mapBlock == NULL);
    Assert(view.reduceBlock == NULL);

    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    Assert(view.mapBlock != nil);

    static const NSUInteger kNDocs = 50;
    [self createDocuments: kNDocs];

    CBLQuery* query = [view createQuery];
    AssertEq(query.database, db);
    query.startKey = @23;
    query.endKey = @33;
    CBLQueryEnumerator* rows = [query run: NULL];
    Assert(rows);
    AssertEq(rows.count, (NSUInteger)11);

    int expectedKey = 23;
    for (CBLQueryRow* row in rows) {
        AssertEq([row.key intValue], expectedKey);
        AssertEq(row.sequenceNumber, (UInt64)expectedKey+1);
        ++expectedKey;
    }
}


- (void) test02_ViewWithLinkedDocs {
    static const NSUInteger kNDocs = 50;
    NSMutableArray* docs = [NSMutableArray array];
    NSString* lastDocID = @"";
    for (NSUInteger i=0; i<kNDocs; i++) {
        NSDictionary* properties = @{ @"sequence" : @(i),
                                      @"prev": lastDocID };
        CBLDocument* doc = [self createDocumentWithProperties: properties];
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
    Assert(rows);
    AssertEq(rows.count, (NSUInteger)11);
    
    int rowNumber = 23;
    for (CBLQueryRow* row in rows) {
        AssertEq([row.key intValue], rowNumber);
        CBLDocument* prevDoc = docs[rowNumber-1];
        AssertEqual(row.documentID, prevDoc.documentID);
        AssertEq(row.document, prevDoc);
        AssertEqual(row.sourceDocumentID, [docs[rowNumber] documentID]);
        ++rowNumber;
    }

    // Try again, without using prefetch (include_docs): [#626]
    query.prefetch = NO;
    rows = [query run: NULL];
    Assert(rows);
    AssertEq(rows.count, (NSUInteger)11);

    rowNumber = 23;
    for (CBLQueryRow* row in rows) {
        AssertEq([row.key intValue], rowNumber);
        CBLDocument* prevDoc = docs[rowNumber-1];
        AssertEqual(row.documentID, prevDoc.documentID);
        AssertEq(row.document, prevDoc);
        AssertEqual(row.sourceDocumentID, [docs[rowNumber] documentID]);
        ++rowNumber;
    }
}


- (void) test03_EmitNil {
    RequireTestCase(API_CreateView);
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    CBLDocument* doc1 = [self createDocumentWithProperties: @{@"sequence": @1}];
    __unused CBLDocument* doc2 = [self createDocumentWithProperties: @{@"sequence": @2}];
    CBLQuery* query = view.createQuery;
    NSArray* result1 = [[query run: NULL] allObjects];
    AssertEqual([(CBLQueryRow*)result1[0] key], @1);
    AssertEqual([(CBLQueryRow*)result1[0] value], nil);
    AssertEqual([(CBLQueryRow*)result1[1] key], @2);
    AssertEqual([(CBLQueryRow*)result1[1] value], nil);
    SequenceNumber query1ChangedAt = view.lastSequenceChangedAt;

    // Update doc1
    [doc1 update:^BOOL(CBLUnsavedRevision *rev) {
        rev[@"something"] = @"else";
        return YES;
    } error: NULL];

    // Query again
    NSArray* result2 = [[query run: NULL] allObjects];
    AssertEqual([(CBLQueryRow*)result2[0] key], @1);
    AssertEqual([(CBLQueryRow*)result2[0] value], nil);
    if (self.isSQLiteDB) {
        // SQLite: The result sets are not considered equal:
        Assert(![result2 isEqual: result1]);
    } else {
        // ForestDB: The view index has not changed, making the result sets equal:
        AssertEq(view.lastSequenceChangedAt, query1ChangedAt);
        Assert([result2 isEqual: result1]);
    }
}


- (void) test04_EmitDoc {
    RequireTestCase(API_CreateView);
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], doc);
    }) version: @"1"];

    CBLDocument* doc1 = [self createDocumentWithProperties: @{@"sequence": @1}];
    CBLDocument* doc2 = [self createDocumentWithProperties: @{@"sequence": @2}];
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


- (CBLView*) createSkinsViewAndDocs {
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        if (doc[@"name"])
            emit(doc[@"name"], doc[@"skin"]);
    }) version: @"1"];

    Assert(view.mapBlock != nil);

    [db inTransaction: ^BOOL {
        [self createDocumentWithProperties: @{@"_id": @"1", @"name": @"Barry", @"skin": @"none"}];
        [self createDocumentWithProperties: @{@"_id": @"2", @"name": @"Terry", @"skin": @"furry"}];
        [self createDocumentWithProperties: @{@"_id": @"3", @"name": @"Wanda", @"skin": @"scaly"}];
        return YES;
    }];
    return view;
}


- (void) test05_ViewCustomSort {
    RequireTestCase(CBLQuery_KeyPathForQueryRow);
    CBLView* view = [self createSkinsViewAndDocs];
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

    // Now combine with a limit (#892):
    query.limit = 2;
    rows = [query run: NULL];

    AssertEqual(rows.nextRow.value, @[@"scaly"]);
    AssertEqual(rows.nextRow.value, @[@"none"]);
    AssertNil(rows.nextRow);

    // ...and a skip
    query.skip = 1;
    query.limit = 9;
    rows = [query run: NULL];

    AssertEqual(rows.nextRow.value, @[@"none"]);
    AssertEqual(rows.nextRow.value, @[@"furry"]);
    AssertNil(rows.nextRow);

    // ...and skipping everything:
    query.skip = 3;
    rows = [query run: NULL];

    AssertNil(rows.nextRow);
}


- (void) test06_ViewCustomFilter {
    CBLView* view = [self createSkinsViewAndDocs];
    CBLQuery* query = [view createQuery];
    query.postFilter = [NSPredicate predicateWithFormat: @"value endswith 'y'"];
    CBLQueryEnumerator* rows = [query run: NULL];

    AssertEqual(rows.nextRow.value, @"furry");
    AssertEqual(rows.nextRow.value, @"scaly");
    AssertNil(rows.nextRow);

    // Check that limits work as expected (#574, #893):
    query = [view createQuery];
    query.postFilter = [NSPredicate predicateWithFormat: @"value endswith 'y'"];
    query.limit = 1;
    rows = [query run: NULL];

    AssertEq(rows.count, 1u);
    AssertEqual(rows.nextRow.value, @"furry");
    AssertNil(rows.nextRow);

    query.limit = 0;
    rows = [query run: NULL];
    AssertEq(rows.count, 0u);

    // Check that skip works as expected (#574):
    query = [view createQuery];
    query.postFilter = [NSPredicate predicateWithFormat: @"value endswith 'y'"];
    query.skip = 1;
    rows = [query run: NULL];

    AssertEqual(rows.nextRow.value, @"scaly");
    AssertNil(rows.nextRow);
}


- (void) test06_AllDocsCustomFilter {
    [self createSkinsViewAndDocs];
    [db _clearDocumentCache];

    Log(@" ---- QUERYIN' ----");
    CBLQuery* query = [db createAllDocumentsQuery];
    query.postFilter = [NSPredicate predicateWithFormat: @"document.properties.skin endswith 'y'"];
    CBLQueryEnumerator* rows = [query run: NULL];

    AssertEqual(rows.nextRow.key, @"2");
    AssertEqual(rows.nextRow.key, @"3");
    AssertNil(rows.nextRow);
}


- (void) test061_UpdateIndex {
    CBLView* view = [self createSkinsViewAndDocs];

    AssertEq(view.lastSequenceIndexed, 0);
    AssertEq(view.lastSequenceChangedAt, 0);
    [view updateIndex];
    AssertEq(view.lastSequenceIndexed, 3);
    AssertEq(view.lastSequenceChangedAt, 3);
    [view updateIndex];
    AssertEq(view.lastSequenceIndexed, 3);
    AssertEq(view.lastSequenceChangedAt, 3);

    [self createDocumentWithProperties: @{@"_id": @"4", @"name": @"Peach", @"skin": @"pink"}];
    [view updateIndex];

    [self createDocuments: 500];
    AssertEq(view.lastSequenceIndexed, 4);
    XCTestExpectation *expect = [self expectationWithDescription: @"Indexing complete"];
    [view updateIndexAsync:^() {
        [expect fulfill];
    }];
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    AssertEq(view.lastSequenceIndexed, 504);
}


#pragma mark - LIVE QUERIES:


- (void) test07_LiveQuery {
    RequireTestCase(API_CreateView);
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    static const NSUInteger kNDocs = 50;
    [self createDocuments: kNDocs];

    CBLLiveQuery* query = [[view createQuery] asLiveQuery];
    query.startKey = @23;
    query.endKey = @33;
    Log(@"Created %@", query);
    AssertNil(query.rows);

    Log(@"Waiting for live query to update...");
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    bool finished = false;
    while (!finished) {
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout];
        Assert(timeout.timeIntervalSinceNow > 0.0, @"timed out waiting for live query");
        CBLQueryEnumerator* rows = query.rows;
        Log(@"Live query rows = %@", rows);
        if (rows != nil) {
            AssertEq(rows.count, (NSUInteger)11);

            int expectedKey = 23;
            for (CBLQueryRow* row in rows) {
                AssertEq(row.document.database, db);
                AssertEq([row.key intValue], expectedKey);
                ++expectedKey;
            }
            finished = true;
        }
    }
    [query stop];
    Assert(finished, @"Live query timed out!");
}


- (void) test08_LiveQuery_DispatchQueue {
    RequireTestCase(API_LiveQuery);
    dispatch_queue_t queue = dispatch_queue_create("LiveQuery", NULL);
    dbmgr.dispatchQueue = queue;
    [db close: NULL];
    db = [dbmgr databaseNamed: @"queued" error: NULL];

    __block CBLView* view;
    __block CBLLiveQuery* query;
    TestLiveQueryObserver* observer = [[TestLiveQueryObserver alloc] init];
    dispatch_sync(queue, ^{
        view = [db viewNamed: @"vu"];
        [view setMapBlock: MAPBLOCK({
            emit(doc[@"sequence"], nil);
        }) version: @"1"];

        static const NSUInteger kNDocs = 50;
        [self createDocuments: kNDocs];

        query = [[view createQuery] asLiveQuery];
        query.startKey = @23;
        query.endKey = @33;
        Log(@"Created %@", query);
        AssertNil(query.rows);

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
                AssertEq(rows.count, (NSUInteger)11);

                int expectedKey = 23;
                for (CBLQueryRow* row in rows) {
                    AssertEq(row.document.database, db);
                    AssertEq([row.key intValue], expectedKey);
                    ++expectedKey;
                }
                finished = true;
            }
        }
    }
    Assert(finished, @"LiveQuery didn't complete");

    dispatch_async(queue, ^{
        NSDictionary* properties = @{@"testName": @"testDatabase", @"sequence": @(23.5)};
        [self createDocumentWithProperties: properties];
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
                AssertEq(rows.count, (NSUInteger)12);
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


- (void) test09_LiveQuery_WaitForRows {
    RequireTestCase(API_LiveQuery);
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    [self createDocuments: 1000];

    // Schedule a garden variety event on the default runloop mode; we want to ensure
    // that this does _not_ trigger during the -waitForRows call.
    __block BOOL delayedBlockRan = NO;
    MYAfterDelay(0.0, ^{
        delayedBlockRan = YES;
    });

    CBLLiveQuery* query = [[view createQuery] asLiveQuery];
    Assert([query waitForRows]);
    Assert(!delayedBlockRan, @"waitForRows accidentally allowed a default-mode event");
    [query stop];
}


- (void) test10_LiveQuery_UpdateInterval {
    RequireTestCase(API_LiveQuery);
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    [self createDocuments: 10];
    unsigned i = 10;

    CBLLiveQuery* query = [[view createQuery] asLiveQuery];
    query.updateInterval = 0.25;
    Log(@"Created %@", query);

    TestLiveQueryObserver* observer = [TestLiveQueryObserver new];
    [query addObserver: observer forKeyPath: @"rows" options: NSKeyValueObservingOptionNew
                   context: NULL];

    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    CFAbsoluteTime lastUpdateTime = 0;
    while (timeout.timeIntervalSinceNow > 0.0) {
        @autoreleasepool {
            if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                          beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.025]])
                break;
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if ( now - lastUpdateTime >= .050) { // throttle the loop so we don't add docs too fast
                NSDictionary* properties = @{@"testName": @"testDatabase", @"sequence": @(i++)};
                [self createDocumentWithProperties: properties];
                //Log(@"%% Created doc #%u", i-1);
                lastUpdateTime = now;
            }
        }
    }
    [query stop];

    Log(@"LiveQuery notified observers %d times", observer.changeCount);
    Assert(observer.changeCount >= 7 && observer.changeCount <= 9);

    [query removeObserver:observer forKeyPath:@"rows"];
}


- (void) test11_AsyncViewQuery {
    RequireTestCase(API_CreateView);
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        if (doc[@"sequence"])
            emit(doc[@"sequence"], doc);    // Emitting doc as value makes trickier things happen
    }) version: @"1"];

    static const NSUInteger kNDocs = 50;
    [self createDocuments: kNDocs];

    CBLQuery* query = [view createQuery];
    query.startKey = @23;
    query.endKey = @33;

    XCTestExpectation* finished = [self expectationWithDescription: @"Query finished"];
    NSThread* curThread = [NSThread currentThread];
    __block SequenceNumber lastSequence;
    [query runAsync: ^(CBLQueryEnumerator *rows, NSError* error) {
        Log(@"Async query finished!");
        AssertEq([NSThread currentThread], curThread);
        Assert(rows);
        AssertNil(error);
        AssertEq(rows.count, (NSUInteger)11);
        lastSequence = rows.sequenceNumber;
        AssertEq(lastSequence, 50);

        int expectedKey = 23;
        for (CBLQueryRow* row in rows) {
            AssertEq(row.document.database, db);
            AssertEq([row.key intValue], expectedKey);
            AssertEqual(row.value, row.document.properties);    // Make sure value is looked up
            ++expectedKey;
        }
        [finished fulfill];
    }];

    Log(@"Waiting for async query to finish...");
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];

    // Now try a conditional async query:
    finished = [self expectationWithDescription: @"Conditional query finished"];
    [query runAsyncIfChangedSince: lastSequence
                       onComplete: ^(CBLQueryEnumerator *rows, NSError* error) {
        Log(@"Conditional async query finished!");
        AssertEq([NSThread currentThread], curThread);
        // Expect no rows because the view index is unchanged since lastSequence:
        AssertNil(rows);
        AssertNil(error);
        [finished fulfill];
    }];
    Log(@"Waiting for conditional async query to finish...");
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];

    // Add a doc that doesn't affect the index, and run another conditional query:
    [self createDocumentWithProperties: @{}];
    finished = [self expectationWithDescription: @"2nd conditional query finished"];
    [query runAsyncIfChangedSince: lastSequence
                       onComplete: ^(CBLQueryEnumerator *rows, NSError* error) {
                           Log(@"Conditional async query finished!");
                           AssertEq([NSThread currentThread], curThread);
                           // ForestDB storage will detect that the index is unchanged; SQLite won't
                           if (!self.isSQLiteDB)
                               AssertNil(rows);
                           AssertNil(error);
                           [finished fulfill];
                       }];
    Log(@"Waiting for 2nd conditional async query to finish...");
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
}

// Ensure that when the view mapblock changes, a related live query
// will be notified and automatically updated
- (void) test12_LiveQuery_UpdatesWhenViewChanges {
    CBLView* view = [db viewNamed: @"vu"];
    
    [view setMapBlock: MAPBLOCK({
        Log(@"*** Emitting 1 for doc %@", doc.cbl_id);//TEMP
        emit(@1, nil);
    }) version: @"1"];
    
    [self createDocuments: 1];
    
    CBLQuery* query = [view createQuery];
    CBLQueryEnumerator* rows = [query run: NULL];
    AssertEq(rows.count, (NSUInteger)1);
    
    int expectedKey = 1;
    for (CBLQueryRow* row in rows) {
        AssertEq([row.key intValue], expectedKey);
    }
    
    CBLLiveQuery* liveQuery = [[view createQuery] asLiveQuery];
//    AssertNil(liveQuery.rows);
    
    TestLiveQueryObserver* observer = [TestLiveQueryObserver new];

    [liveQuery addObserver: observer forKeyPath: @"rows" options: NSKeyValueObservingOptionNew context: NULL];

    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    bool finished = false;
    while (!finished && timeout.timeIntervalSinceNow > 0.0) {

        Log(@"Waiting for live query FIRST update...");
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;

        if (observer.changeCount == 1) {
            
            CBLQueryEnumerator* rows = liveQuery.rows;
            Log(@"Live query rows = %@", rows);
            if (rows != nil) {
                AssertEq(rows.count, (NSUInteger)1);
                
                int expectedKey = 1;
                for (CBLQueryRow* row in rows) {
                    AssertEq([row.key intValue], expectedKey);
                }
                finished = true;
            }
        }

    }
    Assert(finished, @"Live query timed out!");

    // now update the view definition, while the live query is running
    Log(@"Updating view mapBlock");
    [view setMapBlock: MAPBLOCK({
        Log(@"*** Emitting 2 for doc %@", doc.cbl_id);//TEMP
        emit(@2, nil);
    }) version: @"2"];
    
    timeout = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    finished = false;
    while (!finished && timeout.timeIntervalSinceNow > 0.0) {
        Log(@"Waiting for live query SECOND update...");
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;
        
        if (observer.changeCount == 2) {
            
            CBLQueryEnumerator* rows = liveQuery.rows;
            Log(@"Live query rows = %@", rows);
            if (rows != nil) {
                AssertEq(rows.count, (NSUInteger)1);
                
                int expectedKey = 2;
                for (CBLQueryRow* row in rows) {
                    AssertEq([row.key intValue], expectedKey);
                }
                finished = true;
            }

        }
        
    }
    Assert(finished, @"Live query timed out!");
    
    [liveQuery stop];
    [liveQuery removeObserver:observer forKeyPath:@"rows"];
}


- (void) test13_LiveQuery_UpdateWhenQueryOptionsChanged {
    CBLView* view = [db viewNamed: @"vu"];

    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    [self createDocuments: 5];

    CBLQuery* query = [view createQuery];
    CBLQueryEnumerator* rows = [query run: NULL];
    AssertEq(rows.count, (NSUInteger)5);

    int expectedKey = 0;
    for (CBLQueryRow* row in rows) {
        AssertEq([row.key intValue], expectedKey++);
    }

    CBLLiveQuery* liveQuery = [[view createQuery] asLiveQuery];
    TestLiveQueryObserver* observer = [TestLiveQueryObserver new];
    [liveQuery addObserver: observer forKeyPath: @"rows" options: NSKeyValueObservingOptionNew context: NULL];

    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 3.0];
    bool finished = false;
    while (!finished && timeout.timeIntervalSinceNow > 0.0) {
        Log(@"Waiting for live query FIRST update...");
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;

        if (observer.changeCount == 1) {
            CBLQueryEnumerator* rows = liveQuery.rows;
            Log(@"Live query rows = %@", rows);
            if (rows != nil) {
                AssertEq(rows.count, (NSUInteger)5);

                int expectedKey = 0;
                for (CBLQueryRow* row in rows) {
                    AssertEq([row.key intValue], expectedKey++);
                }
                finished = true;
            }
        }

    }
    Assert(finished, @"Live query timed out!");

    liveQuery.startKey = @(2);
    [liveQuery queryOptionsChanged];

    timeout = [NSDate dateWithTimeIntervalSinceNow: 3.0];
    finished = false;
    while (!finished && timeout.timeIntervalSinceNow > 0.0) {
        Log(@"Waiting for live query FIRST update...");
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;

        if (observer.changeCount == 2) {
            CBLQueryEnumerator* rows = liveQuery.rows;
            Log(@"Live query rows = %@", rows);
            if (rows != nil) {
                AssertEq(rows.count, (NSUInteger)3);

                int expectedKey = 2;
                for (CBLQueryRow* row in rows) {
                    AssertEq([row.key intValue], expectedKey++);
                }
                finished = true;
            }
        }
    }
    Assert(finished, @"Live query timed out!");

    [liveQuery stop];
    [liveQuery removeObserver:observer forKeyPath:@"rows"];
}

- (void) test14_LiveQuery_AddingNonIndexedDocsPriorCreatingLiveQuery {
    CBLView* view = [db viewNamed: @"vu"];

    [view setMapBlock: MAPBLOCK({
        if ([doc[@"type"] isEqualToString:@"user"]) {
            emit(doc[@"name"], nil);
        }
    }) version: @"1"];

    // Create a new document which will not get indexed by the created view:
    [self createDocumentWithProperties: @{@"type": @"settings", @"allows_guest": @(YES)}];

    // Start a new live query object:
    CBLLiveQuery* liveQuery = [[view createQuery] asLiveQuery];
    TestLiveQueryObserver* observer = [TestLiveQueryObserver new];
    [liveQuery addObserver: observer forKeyPath: @"rows" options: NSKeyValueObservingOptionNew context: NULL];

    // Wait for an initial result from the live query which should return zero rows.
    // Wait until timeout reached to ensure that no pending operation inside the live query
    // espeically a pending update method call from the databaseChanged: method.
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    bool finished = false;
    while (timeout.timeIntervalSinceNow > 0.0) {
        Log(@"Waiting for live query FIRST update...");
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;

        if (observer.changeCount == 1) {
            CBLQueryEnumerator* rows = liveQuery.rows;
            Log(@"Live query rows = %@", rows);
            if (rows != nil) {
                AssertEq(rows.count, (NSUInteger)0);
                finished = true;
            }
        }
    }
    Assert(finished, @"Live query timed out!");

    // Create a new document which will get indexed by the created view:
    [self createDocumentWithProperties: @{@"type": @"user", @"name": @"Peter"}];

    // Wait for the live query to update the result:
    timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    finished = false;
    while (!finished && timeout.timeIntervalSinceNow > 0.0) {
        Log(@"Waiting for live query FIRST update...");
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;

        if (observer.changeCount == 2) {
            CBLQueryEnumerator* rows = liveQuery.rows;
            Log(@"Live query rows = %@", rows);
            if (rows != nil) {
                AssertEq(rows.count, (NSUInteger)1);
                AssertEqual(rows.nextRow.key, @"Peter");
                finished = true;
            }
        }
    }
    Assert(finished, @"Live query timed out!");
    
    [liveQuery stop];
    [liveQuery removeObserver:observer forKeyPath:@"rows"];
}


- (void) test15_LiveQueryAllDocs {
    [self createDocuments: 10];
    CBLQuery *allDocsQuery = [db createAllDocumentsQuery];
    CBLLiveQuery *allDocsQueryLive = [allDocsQuery asLiveQuery];
    [allDocsQueryLive start];
    Assert([allDocsQueryLive waitForRows]);

    CBLQueryEnumerator* rows = allDocsQueryLive.rows;
    AssertEq(rows.count, 10u);
    for (CBLQueryRow* row in rows) {
        Log(@"-- %@", row);
        CBLDocument* doc = row.document;
        Assert(doc != nil, @"Couldn't get document of %@", row);    // Test fix for #733
    }
}


- (void) test16_LiveQuery_BackgroundUpdate {
    CBLView* view = [db viewNamed: @"vu"];

    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    // Create a document:
    [self createDocumentWithProperties: @{@"sequence": @(0)} inDatabase: db];

    CBLQuery* query = [view createQuery];
    CBLQueryEnumerator* rows = [query run: NULL];
    AssertEq(rows.count, 1u);

    CBLLiveQuery* liveQuery = [query asLiveQuery];
    [self keyValueObservingExpectationForObject: liveQuery
                                        keyPath: @"rows"
                                        handler: ^BOOL(id object, NSDictionary *change) {
         return (((CBLLiveQuery*)object).rows.count == 10);
     }];
    [liveQuery start];

    // Create more documents in background:
    [dbmgr backgroundTellDatabaseNamed: db.name to: ^(CBLDatabase* bgdb) {
        [bgdb inTransaction: ^BOOL{
            for (unsigned i=1; i<10; i++) {
                @autoreleasepool {
                    [self createDocumentWithProperties: @{@"sequence": @(i)} inDatabase: bgdb];
                }
            }
            return YES;
        }];
    }];

    [self waitForExpectationsWithTimeout: 2.0 handler: ^(NSError *error) {
        AssertNil(error, @"Live query timed out!");
    }];
    
    [liveQuery stop];
}

#pragma mark - GEO


static NSDictionary* mkGeoPoint(double x, double y) {
    return CBLGeoPointToJSON((CBLGeoPoint){x,y});
}

static NSDictionary* mkGeoRect(double x0, double y0, double x1, double y1) {
    return CBLGeoRectToJSON((CBLGeoRect){{x0,y0}, {x1,y1}});
}

- (NSArray*) putGeoDocs {
    return @[
        [self createDocumentWithProperties: $dict({@"_id", @"22222"}, {@"key", @"two"})],
        [self createDocumentWithProperties: $dict({@"_id", @"44444"}, {@"key", @"four"})],
        [self createDocumentWithProperties: $dict({@"_id", @"11111"}, {@"key", @"one"})],
        [self createDocumentWithProperties: $dict({@"_id", @"33333"}, {@"key", @"three"})],
        [self createDocumentWithProperties: $dict({@"_id", @"55555"}, {@"key", @"five"})],
        [self createDocumentWithProperties: $dict({@"_id", @"pdx"},   {@"key", @"Portland"},
                                          {@"geoJSON", mkGeoPoint(-122.68, 45.52)})],
        [self createDocumentWithProperties: $dict({@"_id", @"aus"},   {@"key", @"Austin"},
                                          {@"geoJSON", mkGeoPoint(-97.75, 30.25)})],
        [self createDocumentWithProperties: $dict({@"_id", @"mv"},    {@"key", @"Mountain View"},
                                          {@"geoJSON", mkGeoPoint(-122.08, 37.39)})],
        [self createDocumentWithProperties: $dict({@"_id", @"hkg"}, {@"geoJSON", mkGeoPoint(-113.91, 45.52)})],
        [self createDocumentWithProperties: $dict({@"_id", @"diy"}, {@"geoJSON", mkGeoPoint(40.12, 37.53)})],
        [self createDocumentWithProperties: $dict({@"_id", @"snc"}, {@"geoJSON", mkGeoPoint(-2.205, -80.98)})],

        [self createDocumentWithProperties: $dict({@"_id", @"xxx"}, {@"geoJSON",
            mkGeoRect(-115,-10, -90, 12)})],
    ];
}

- (void) test17_GeoQuery {
    if (!self.isSQLiteDB)
        return;     //FIX: Geo support in ForestDB is not complete enough to pass this test

    RequireTestCase(CBLGeometry);
    RequireTestCase(CBL_View_Index);

    CBLView* view = [db viewNamed: @"geovu"];
    [view setMapBlock: MAPBLOCK({
        if (doc[@"key"])
            emit(doc[@"key"], nil);
        if (doc[@"geoJSON"])
            emit(CBLGeoJSONKey(doc[@"geoJSON"]), nil);
    }) version: @"1"];

    // Query before any docs are indexed:
    CBLQuery* query = [view createQuery];
    CBLGeoRect bbox = {{-100, 0}, {180, 90}};
    query.boundingBox = bbox;
    NSError* error;
    NSArray* rows = [[query run: &error] allObjects];
    AssertEqual(rows, @[]);

    // Create docs:
    [self putGeoDocs];

    // Bounding-box query:
    query = [view createQuery];
    query.boundingBox = bbox;
    rows = [[query run: &error] allObjects];
    NSArray* rowsAsDicts = [rows my_map: ^(CBLQueryRow* row) {return row.asJSONDictionary;}];
    NSArray* expectedRows = @[$dict({@"id", @"xxx"},
                                    {@"geometry", mkGeoRect(-115, -10, -90, 12)},
                                    {@"bbox", @[@-115, @-10, @-90, @12]}),
                               $dict({@"id", @"aus"},
                                     {@"geometry", mkGeoPoint(-97.75, 30.25)},
                                     {@"bbox", @[@-97.75, @30.25, @-97.75, @30.25]}),
                               $dict({@"id", @"diy"},
                                     {@"geometry", mkGeoPoint(40.12, 37.53)},
                                     {@"bbox", @[@40.12, @37.53, @40.12, @37.53]})];
    AssertEqualish(rowsAsDicts, expectedRows);

    CBLGeoQueryRow* row = rows[0];
    AssertEq(row.boundingBox.min.x, -115);
    AssertEq(row.boundingBox.min.y,  -10);
    AssertEq(row.boundingBox.max.x,  -90);
    AssertEq(row.boundingBox.max.y,   12);
    AssertEqual(row.geometryType, @"Polygon");
    AssertEqual(row.geometry, mkGeoRect(-115, -10, -90, 12));

    row = rows[1];
    AssertEq(row.boundingBox.min.x, -97.75);
    AssertEq(row.boundingBox.min.y,  30.25);
    AssertEqual(row.geometryType, @"Point");
    AssertEqual(row.geometry, mkGeoPoint(-97.75, 30.25));
}



#pragma mark - OTHER

// Make sure that a database's map/reduce functions are shared with the shadow database instance
// running in the background server.
- (void) test18_SharedMapBlocks {
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
    Assert(ok, @"Couldn't set map/reduce");

    CBLMapBlock map = view.mapBlock;
    CBLReduceBlock reduce = view.reduceBlock;
    CBLFilterBlock filter = [db filterNamed: @"phil"];
    CBLValidationBlock validation = [db validationNamed: @"val"];

    NSConditionLock* lock = [[NSConditionLock alloc] initWithCondition: 0];
    [dbmgr backgroundTellDatabaseNamed: db.name to: ^(CBLDatabase *serverDb) {
        Assert(serverDb != nil);
        CBLView* serverView = [serverDb viewNamed: @"view"];
        Assert(serverView != nil);
        AssertEq([serverDb filterNamed: @"phil"], filter);
        AssertEq([serverDb validationNamed: @"val"], validation);
        AssertEq(serverView.mapBlock, map);
        AssertEq(serverView.reduceBlock, reduce);
        [lock unlockWithCondition: 1]; // unblock main thread
    }];
    [lock lockWhenCondition: 1];  // wait till block finishes
    [lock unlock];
}


- (void) test19_CBLKeyPathForQueryRow {
    AssertEqual(CBLKeyPathForQueryRow(@"value"),           @"value");
    AssertEqual(CBLKeyPathForQueryRow(@"value.foo"),       @"value.foo");
    AssertEqual(CBLKeyPathForQueryRow(@"value[0]"),        @"value0");
    AssertEqual(CBLKeyPathForQueryRow(@"key[3].foo"),      @"key3.foo");
    AssertEqual(CBLKeyPathForQueryRow(@"value[0].foo"),    @"value0.foo");
    AssertEqual(CBLKeyPathForQueryRow(@"[2]"),             nil);
    AssertEqual(CBLKeyPathForQueryRow(@"sequence[2]"),     nil);
    AssertEqual(CBLKeyPathForQueryRow(@"value.addresses[2]"),nil);
    AssertEqual(CBLKeyPathForQueryRow(@"value["),          nil);
    AssertEqual(CBLKeyPathForQueryRow(@"value[0"),         nil);
    AssertEqual(CBLKeyPathForQueryRow(@"value[0"),         nil);
    AssertEqual(CBLKeyPathForQueryRow(@"value[0}"),        nil);
    AssertEqual(CBLKeyPathForQueryRow(@"value[d]"),        nil);
}


- (void) test20_DocTypes {
    CBLView* view1 = [db viewNamed: @"test/peepsNames"];
    view1.documentType = @"person";
    [view1 setMapBlock: MAPBLOCK({
        Log(@"view1 mapping: %@", doc);
        AssertEqual(doc[@"type"], @"person");
        emit(doc[@"name"], nil);
    }) version: @"1"];

    CBLView* view2 = [db viewNamed: @"test/aardvarks"];
    view2.documentType = @"aardvark";
    [view2 setMapBlock: MAPBLOCK({
        Log(@"view2 mapping: %@", doc);
        AssertEqual(doc[@"type"], @"aardvark");
        emit(doc[@"name"], nil);
    }) version: @"1"];

    // Create a new document which will not get indexed by the created view:
    [self createDocumentWithProperties: @{@"type": @"person", @"name": @"mick"}];
    [self createDocumentWithProperties: @{@"type": @"person", @"name": @"keef"}];
    CBLDocument* cerebus;
    cerebus = [self createDocumentWithProperties: @{@"type": @"aardvark", @"name": @"cerebus"}];

    CBLQuery* query = [view1 createQuery];
    CBLQueryEnumerator* rows = [query run: NULL];
    NSArray* allRows = rows.allObjects;
    AssertEq(allRows.count, 2u);
    AssertEqual([allRows[0] key], @"keef");
    AssertEqual([allRows[1] key], @"mick");

    query = [view2 createQuery];
    rows = [query run: NULL];
    allRows = rows.allObjects;
    AssertEq(allRows.count, 1u);
    AssertEqual([allRows[0] key], @"cerebus");

    // Make sure that documents that are updated to no longer match the view's documentType get
    // removed from its index:
    Log(@"---- Update cerebus.type = person ----");
    CBLRevision* rev = [cerebus update: ^BOOL(CBLUnsavedRevision* rev) {
        rev[@"type"] = @"person";
        return YES;
    } error: NULL];
    Assert(rev);

    rows = [query run: NULL];
    allRows = rows.allObjects;
    AssertEq(allRows.count, 0u);

    // Make sure a view without a docType will coexist:
    [self createDocumentWithProperties: @{@"type": @"elf", @"name": @"regency elf"}];
    CBLView* view3 = [db viewNamed: @"test/all"];
    [view3 setMapBlock: MAPBLOCK({
        Log(@"view3 mapping: %@", doc);
        emit(doc[@"name"], nil);
    }) version: @"1"];

    query = [view3 createQuery];
    rows = [query run: NULL];
    allRows = rows.allObjects;
    AssertEq(allRows.count, 4u);
}


- (void) test21_TotalRows {
    CBLView* view = [db viewNamed: @"vu"];
    Assert(view);
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];
    Assert(view.mapBlock != nil);
    AssertEq(view.totalRows, 0u);

    // Add 20 documents:
    [self createDocuments: 20];
    Assert(view.stale);
    AssertEq(view.totalRows, 20u);
    Assert(!view.stale);

    // Add another 20 documents, query, and check totalRows:
    [self createDocuments: 20];
    CBLQuery* query = [view createQuery];
    CBLQueryEnumerator* rows = [query run: NULL];
    AssertEq(rows.count, 40u);
    AssertEq(view.totalRows, 40u);
}


- (void) test22_MapFn_Conflicts {
    CBLView* view = [db viewNamed: @"vu"];
    Assert(view);
    [view setMapBlock: MAPBLOCK({
        // NSLog(@"%@", doc);
        emit(doc[@"_id"], doc[@"_conflicts"]);
    }) version: @"1"];
    Assert(view.mapBlock != nil);

    CBLDocument* doc = [self createDocumentWithProperties: @{@"foo": @"bar"}];
    CBLSavedRevision* rev1 = doc.currentRevision;
    NSMutableDictionary* properties = doc.properties.mutableCopy;
    properties[@"tag"] = @"1";
    NSError* error;
    CBLSavedRevision* rev2a = [doc putProperties: properties error: &error];
    Assert(rev2a);

    // No conflicts:
    CBLQuery* query = [view createQuery];
    CBLQueryEnumerator* rows = [query run: NULL];
    AssertEq(rows.count, 1u);
    CBLQueryRow* row = [rows rowAtIndex: 0];
    AssertEqual(row.key, doc.documentID);
    AssertNil(row.value);

    // Create a conflict revision:
    properties = rev1.properties.mutableCopy;
    properties[@"tag"] = @"2";
    CBLUnsavedRevision* newRev = [rev1 createRevision];
    newRev.properties = properties;
    CBLSavedRevision* rev2b = [newRev saveAllowingConflict: &error];
    Assert(rev2b);

    rows = [query run: NULL];
    AssertEq(rows.count, 1u);
    row = [rows rowAtIndex: 0];
    AssertEqual(row.key, doc.documentID);
    NSArray* conflicts = @[rev2a.revisionID];
    AssertEqual(row.value, conflicts);

    // Create another conflict revision:
    properties = rev1.properties.mutableCopy;
    properties[@"tag"] = @"3";
    newRev = [rev1 createRevision];
    newRev.properties = properties;
    CBLSavedRevision* rev2c = [newRev saveAllowingConflict: &error];
    Assert(rev2c);

    rows = [query run: NULL];
    AssertEq(rows.count, 1u);
    row = [rows rowAtIndex: 0];
    AssertEqual(row.key, doc.documentID);
    conflicts = @[rev2b.revisionID, rev2a.revisionID];
    AssertEqual(row.value, conflicts);
}


// https://github.com/couchbase/couchbase-lite-ios/issues/1082
- (void) test23_ViewWithDocDeletion {
    [self _testViewWithDocDeletionOrPurge: NO];
}

- (void) test24_ViewWithDocPurge {
    [self _testViewWithDocDeletionOrPurge: YES];
}

- (void) _testViewWithDocDeletionOrPurge: (BOOL)purge {
    CBLView* view = [db viewNamed: @"vu"];
    Assert(view);
    [view setMapBlock: MAPBLOCK({
        if ([doc[@"type"] isEqualToString: @"task"]) {
            id date = doc[@"created_at"];
            NSString* listID = doc[@"list_id"];
            emit(@[listID, date], doc);
        }
    }) version: @"1"];
    Assert(view.mapBlock != nil);
    AssertEq(view.totalRows, 0u);

    NSString* listId = @"list1";

    // Create 3 documents:
    CBLDocument* doc1 = [self createDocumentWithProperties:
                         @{@"_id": @"doc1",
                           @"type": @"task",
                           @"created_at": @"2016-01-29T22:25:01.000Z",
                           @"list_id": listId}];
    CBLDocument* doc2 = [self createDocumentWithProperties:
                         @{@"_id": @"doc2",
                           @"type": @"task",
                           @"created_at": @"2016-01-29T22:25:02.000Z",
                           @"list_id": listId}];
    CBLDocument* doc3 = [self createDocumentWithProperties:
                         @{@"_id": @"doc3",
                           @"type": @"task",
                           @"created_at": @"2016-01-29T22:25:03.000Z",
                           @"list_id": listId}];

    // Check query result:
    CBLQuery* query = [view createQuery];
    query.descending = YES;
    query.startKey = @[listId, @{}];
    query.endKey = @[listId];

    CBLQueryEnumerator* rows;
    rows = [query run: NULL];
    Log(@"First query: rows = %@", rows.allObjects);
    AssertEq(rows.count, 3u);
    AssertEqual([rows rowAtIndex:0].documentID, doc3.documentID);
    AssertEqual([rows rowAtIndex:1].documentID, doc2.documentID);
    AssertEqual([rows rowAtIndex:2].documentID, doc1.documentID);

    // Delete or purge doc2:
    Assert(doc2);
    NSError* error;
    if (purge)
        Assert([doc2 purgeDocument: &error]);
    else
        Assert([doc2 deleteDocument: &error]);
    Log(@"Deleted doc2");

    // Check ascending query result:
    query.descending = NO;
    query.startKey = @[listId];
    query.endKey = @[listId, @{}];
    rows = [query run: NULL];
    Log(@"Ascending query: rows = %@", rows.allObjects);
    AssertEq(rows.count, 2u);
    AssertEqual([rows rowAtIndex:0].documentID, doc1.documentID);
    AssertEqual([rows rowAtIndex:1].documentID, doc3.documentID);

    // Check descending query result:
    query.descending = YES;
    query.startKey = @[listId, @{}];
    query.endKey = @[listId];
    rows = [query run: NULL];
    Log(@"Descending query: rows = %@", rows.allObjects);
    AssertEq(rows.count, 2u);
    AssertEqual([rows rowAtIndex:0].documentID, doc3.documentID);
    AssertEqual([rows rowAtIndex:1].documentID, doc1.documentID);
}


@end
