//
//  View_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/19/14.
//
//

#import "CBLTestCase.h"
#import "MYBlockUtils.h"


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


- (void) test05_ViewCustomSort {
    RequireTestCase(CBLQuery_KeyPathForQueryRow);
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"name"], doc[@"skin"]);
    }) version: @"1"];

    Assert(view.mapBlock != nil);

    [db inTransaction: ^BOOL {
        [self createDocumentWithProperties: @{@"name": @"Barry", @"skin": @"none"}];
        [self createDocumentWithProperties: @{@"name": @"Terry", @"skin": @"furry"}];
        [self createDocumentWithProperties: @{@"name": @"Wanda", @"skin": @"scaly"}];
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


- (void) test06_ViewCustomFilter {
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"name"], doc[@"skin"]);
    }) version: @"1"];

    Assert(view.mapBlock != nil);

    [db inTransaction: ^BOOL {
        [self createDocumentWithProperties: @{@"name": @"Barry", @"skin": @"none"}];
        [self createDocumentWithProperties: @{@"name": @"Terry", @"skin": @"furry"}];
        [self createDocumentWithProperties: @{@"name": @"Wanda", @"skin": @"scaly"}];
        return YES;
    }];

    CBLQuery* query = [view createQuery];
    query.postFilter = [NSPredicate predicateWithFormat: @"value endswith 'y'"];
    CBLQueryEnumerator* rows = [query run: NULL];

    AssertEqual(rows.nextRow.value, @"furry");
    AssertEqual(rows.nextRow.value, @"scaly");
    AssertNil(rows.nextRow);
}


- (void) test06_AllDocsCustomFilter {
    [db inTransaction: ^BOOL {
        [self createDocumentWithProperties: @{@"_id": @"1", @"name": @"Barry", @"skin": @"none"}];
        [self createDocumentWithProperties: @{@"_id": @"2", @"name": @"Terry", @"skin": @"furry"}];
        [self createDocumentWithProperties: @{@"_id": @"3", @"name": @"Wanda", @"skin": @"scaly"}];
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

    CBLLiveQuery* query = [[view createQuery] asLiveQuery];
    query.updateInterval = 0.25;
    Log(@"Created %@", query);

    TestLiveQueryObserver* observer = [TestLiveQueryObserver new];
    [query addObserver: observer forKeyPath: @"rows" options: NSKeyValueObservingOptionNew
                   context: NULL];

    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    while (timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]])
            break;
        [self createDocuments: 1];
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
        emit(doc[@"sequence"], nil);
    }) version: @"1"];

    static const NSUInteger kNDocs = 50;
    [self createDocuments: kNDocs];

    CBLQuery* query = [view createQuery];
    query.startKey = @23;
    query.endKey = @33;

    __block bool finished = false;
    NSThread* curThread = [NSThread currentThread];
    [query runAsync: ^(CBLQueryEnumerator *rows, NSError* error) {
        Log(@"Async query finished!");
        AssertEq([NSThread currentThread], curThread);
        Assert(rows);
        AssertNil(error);
        AssertEq(rows.count, (NSUInteger)11);

        int expectedKey = 23;
        for (CBLQueryRow* row in rows) {
            AssertEq(row.document.database, db);
            AssertEq([row.key intValue], expectedKey);
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
    Assert(finished, @"Async query timed out!");
}

// Ensure that when the view mapblock changes, a related live query
// will be notified and automatically updated
- (void) test12_LiveQuery_UpdatesWhenViewChanges {
    CBLView* view = [db viewNamed: @"vu"];
    
    [view setMapBlock: MAPBLOCK({
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
    [view setMapBlock: MAPBLOCK({
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


// Make sure that a database's map/reduce functions are shared with the shadow database instance
// running in the background server.
- (void) test13_SharedMapBlocks {
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


- (void) test_CBLKeyPathForQueryRow {
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


@end
