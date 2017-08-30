//
//  ConcurrentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/17/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CollectionUtils.h"

#define kDocumentTestBlob @"i'm blob"

@interface ConcurrentTest : CBLTestCase

@end

@implementation ConcurrentTest


- (void) updateDictionary: (id <CBLDictionary>)dictionary
                   custom: (nullable NSDictionary*)custom
                   number: (NSUInteger)number
{
    // String:
    NSString* string = [NSString stringWithFormat: @"String%lu", (unsigned long)number];
    [dictionary setObject: string forKey: @"string"];
    
    // Number:
    [dictionary setObject: @(number + 1) forKey: @"integer"];
    [dictionary setObject: @(number + 1.9) forKey: @"float"];
    
    // Boolean:
    [dictionary setObject: @(YES) forKey: @"true"];
    [dictionary setObject: @(NO) forKey: @"false"];
    [dictionary setObject: @((number % 2) == 0) forKey: @"even"];
    
    // Blob:
    NSData* data = [@"Concurrent Test" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: data];
    [dictionary setObject: blob forKey: @"blob"];
    
    // Dictionary:
    CBLDictionary* dict = [dictionary objectForKey: @"dict"];
    if (!dict) {
        dict = [[CBLDictionary alloc] init];
        [dict setObject: @"1 Main street" forKey: @"street"];
        [dict setObject: @"Mountain View" forKey: @"city"];
        [dict setObject: @"CA" forKey: @"state"];
    } else {
        NSString* street = [NSString stringWithFormat: @"%lu street.", (unsigned long)number];
        [dict setObject: street forKey: @"street"];
    }
    [dictionary setObject: dict forKey: @"dict"];
    
    // Another Dictionary:
    CBLDictionary* anotherDict = [[CBLDictionary alloc] init];
    [anotherDict setObject: @"string" forKey: @"string"];
    [anotherDict setObject: @(1.5) forKey: @"number"];
    [anotherDict setObject: @(YES) forKey: @"boolean"];
    [anotherDict setObject: [NSDate date] forKey: @"date"];
    [dictionary setObject: anotherDict forKey: @"anotherDict"];
    
    // Array:
    CBLArray* array = [dictionary objectForKey: @"array"];
    if (!array) {
        array = [[CBLArray alloc] init];
        [array addObject: @"650-123-0001"];
        [array addObject: @"650-123-0002"];
    } else {
        NSString* nuNumber = [NSString stringWithFormat: @"650-000-%lu", (unsigned long)number];
        [array setObject: nuNumber atIndex: 0];
    }
    [dictionary setObject: array forKey: @"array"];
    
    // Another Array:
    CBLArray* anotherArray = [[CBLArray alloc] init];
    [anotherArray addObject: @"string"];
    [anotherArray addObject: @(1.5)];
    [anotherArray addObject: @(YES)];
    [anotherArray addObject: [NSDate date]];
    [dictionary setObject: anotherArray forKey: @"anotherArray"];
    
    // Date:
    [dictionary setObject: [NSDate date] forKey: @"date"];
    
    // Custom:
    for (NSString* key in custom) {
        [dictionary setObject: custom[key] forKey: key];
    }
}


- (void) readDictionary: (id<CBLDictionary>)dictionary {
    // String:
    AssertNotNil([dictionary objectForKey: @"string"]);
    AssertNotNil([dictionary stringForKey: @"string"]);
    
    // Number:
    Assert([dictionary integerForKey: @"integer"] >= 1);
    Assert([dictionary doubleForKey: @"float"] >= 1.0);
    Assert([dictionary floatForKey: @"float"] >= 1.0f);
    
    // Boolean:
    Assert([dictionary booleanForKey: @"true"]);
    AssertFalse([dictionary booleanForKey: @"false"]);
    Assert([dictionary objectForKey: @"even"]);
    
    // Blob:
    CBLBlob* blob = [dictionary blobForKey: @"blob"];
    NSString* blobStr = [[NSString alloc] initWithData: blob.content
                                              encoding: NSUTF8StringEncoding];
    Assert(blobStr.length > 0);
    
    // Dictionary:
    CBLDictionary* dict = [dictionary dictionaryForKey: @"dict"];
    AssertEqual(dict.count, 3u);
    AssertNotNil([dict stringForKey: @"street"]);
    AssertNotNil([dict stringForKey: @"city"]);
    AssertNotNil([dict stringForKey: @"state"]);
    
    // Another Dictionary:
    CBLDictionary* anotherDict = [dictionary dictionaryForKey: @"anotherDict"];
    AssertEqual(anotherDict.count, 4u);
    AssertEqualObjects([anotherDict stringForKey: @"string"], @"string");
    AssertEqual([anotherDict doubleForKey: @"number"], 1.5);
    Assert([anotherDict booleanForKey: @"boolean"]);
    AssertNotNil([anotherDict dateForKey: @"date"]);
    
    // Array:
    CBLArray* array = [dictionary arrayForKey: @"array"];
    AssertEqual(array.count, 2u);
    AssertNotNil([array stringAtIndex: 0]);
    AssertNotNil([array stringAtIndex: 1]);
    
    // Another Array:
    CBLArray* anotherArray = [dictionary arrayForKey: @"anotherArray"];
    AssertEqual(anotherArray.count, 4u);
    AssertEqualObjects([anotherArray objectAtIndex: 0], @"string");
    AssertEqual([anotherArray doubleAtIndex: 1], 1.5);
    Assert([anotherArray booleanAtIndex: 2]);
    AssertNotNil([anotherArray dateAtIndex: 3]);
    
    // Date:
    AssertNotNil([dictionary dateForKey: @"date"]);
}


- (CBLDocument*) createDoc {
    CBLDocument* doc = [[CBLDocument alloc] init];
    [self updateDictionary: doc custom: nil number: 0];
    return doc;
}


- (NSArray*) createAndSaveDocs: (NSUInteger)nDocs  error: (NSError**)error {
    NSMutableArray* docs = [NSMutableArray arrayWithCapacity: nDocs];
    for (NSUInteger i = 0; i < nDocs; i++) {
        CBLDocument* doc = [self createDoc];
        if (![self.db saveDocument: doc error: error])
            return nil;
        [docs addObject: doc];
    }
    return docs;
}


- (BOOL) tryCreateAndSaveDocs: (NSUInteger)nDocs  error: (NSError**)error {
    for (NSUInteger i = 0; i < nDocs; i++) {
        CBLDocument* doc = [self createDoc];
        if (![self.db saveDocument: doc error: error])
            return NO;
    }
    return YES;
}


- (BOOL) updateDoc: (CBLDocument*)doc
            custom: (nullable NSDictionary*)custom
            number: (NSUInteger)number
             error: (NSError**)error
{
    [self updateDictionary: doc custom: custom number: number];
    if (![self.db saveDocument: doc error: error]) {
        return NO;
    }
    return YES;
}


- (BOOL) updateDocIDs: (NSArray*)docIds
               rounds: (NSUInteger)rounds
               custom: (nullable NSDictionary*)custom
                error: (NSError**)error
{
    NSUInteger n = 0;
    for (NSUInteger r = 0; r < rounds; r++) {
        for (NSString* docId in docIds) {
            CBLDocument* doc = [self.db documentWithID: docId];
            [self updateDoc: doc custom: custom number: n++ error: error];
        }
    }
    return YES;
}


- (BOOL) updateDocs: (NSArray*)docs
             rounds: (NSUInteger)rounds
             custom: (nullable NSDictionary*)custom
              error: (NSError**)error
{
    NSUInteger n = 0;
    for (NSUInteger r = 0; r < rounds; r++) {
        for (CBLDocument* doc in docs) {
            [self updateDoc: doc custom: custom number: n++ error: error];
        }
    }
    return YES;
}


- (void) readDocIDs: (NSArray<NSString*>*)docIDs rounds: (NSUInteger)rounds {
    for (NSUInteger r = 0; r < rounds; r++) {
        for (NSString* docID in docIDs) {
            CBLDocument* doc = [_db documentWithID: docID];
            AssertNotNil(doc);
            AssertEqualObjects(doc.id, docID);
            [self readDictionary: doc];
        }
    }
}


- (void) verifyWhere: (nullable CBLQueryExpression*)expr
                test: (void (^)(uint64_t n, CBLQueryRow *row))block {
    CBLQuery* q = [CBLQuery select: @[[CBLQuerySelectResult expression: [CBLQueryExpression meta].id]]
                              from: [CBLQueryDataSource database: self.db]
                             where: expr];
    NSError* error;
    NSEnumerator* e = [q run: &error];
    Assert(e, @"Query failed: %@", error);
    uint64_t n = 0;
    for (CBLQueryRow *row in e) {
        block(++n, row);
    }
}


- (void) concurrentRuns: (NSUInteger)nRuns
          waitUntilDone: (BOOL)wait
              withBlock: (void (^)(NSUInteger rIndex))block
{
    NSMutableArray* expects = [NSMutableArray arrayWithCapacity: nRuns];
    for (NSUInteger i = 0; i < nRuns; i++) {
        NSString* name = [NSString stringWithFormat: @"Queue-%ld", (long)i];
        XCTestExpectation* exp = [self expectationWithDescription: name];
        [expects addObject: exp];
        dispatch_queue_t queue = dispatch_queue_create([name UTF8String],  NULL);
        dispatch_async(queue, ^{
            block(i);
            [exp fulfill];
        });
    }
    
    if (wait && expects.count > 0) {
        [self waitForExpectations: expects timeout: 60.0];
    }
}


#pragma mark - Database


- (void) testConcurrentCreateDocs {
    const NSUInteger kNDocs = 100;
    const NSUInteger kNConcurrents = 5;
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        NSError* error;
        Assert([self createAndSaveDocs: kNDocs error: &error],
               @"Error creating docs: %@", error);
    }];
    
    AssertEqual(self.db.count, kNDocs * kNConcurrents);
}


- (void) testConcurrentUpdateSeperateDocInstances {
    const NSUInteger kNDocs = 1;
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 5;
    
    NSArray* docs = [self createAndSaveDocs: kNDocs error: nil];
    NSArray* docIDs = [docs my_map: ^id(CBLDocument* doc) {
        return doc.id;
    }];
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        NSString* tag = [NSString stringWithFormat:@"Update%ld", (long)rIndex];
        NSError* error;
        Assert([self updateDocIDs: docIDs rounds: kNRounds custom: @{@"tag": tag} error: &error],
               @"Error updating doc: %@", error);
    }];
    
    __block NSUInteger count = 0;
    
    for (NSUInteger i = 0; i < kNConcurrents; i++) {
        NSString* tag = [NSString stringWithFormat:@"Update%ld", (long)i];
        CBLQueryExpression* expr = [[CBLQueryExpression property: @"tag"] equalTo: tag];
        [self verifyWhere: expr test: ^(uint64_t n, CBLQueryRow *row) {
            count++;
        }];
    }
    
    AssertEqual(count, kNDocs);
}


// Enable when CBLDictionary is thread safe:
- (void) testConcurrentUpateDocs {
    const NSUInteger kNDocs = 1;
    const NSUInteger kNRounds = 1;
    const NSUInteger kNConcurrents = 1;
    
    NSArray* docs = [self createAndSaveDocs: kNDocs error: nil];
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        NSError* error;
        Assert([self updateDocs: docs rounds: kNRounds custom: nil error: &error],
               @"Error when updating docs: %@", error);
    }];
    
    // Verify:
    NSArray* docIDs = [docs my_map: ^id(CBLDocument* doc) {
        return doc.id;
    }];
    [self readDocIDs: docIDs rounds: kNRounds];
}


- (void) _testConcurrentGetDocs {
    const NSUInteger kNDocs = 1;
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 5;
    
    NSArray* docs = [self createAndSaveDocs: kNDocs error: nil];
    NSArray* docIDs = [docs my_map: ^id(CBLDocument* doc) {
        return doc.id;
    }];
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        [self readDocIDs: docIDs rounds: kNRounds];
    }];
}


- (void) testConcurrentDeleteDocs {
    const NSUInteger kNDocs = 5;
    const NSUInteger kNConcurrents = 5;
    
    NSArray* docs = [self createAndSaveDocs: kNDocs error: nil];
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        for (CBLDocument* doc in docs) {
            NSError* error;
            Assert([self.db deleteDocument: doc error: &error], @"Error when delete: %@", error);
        }
    }];
    
    AssertEqual(self.db.count, 0u);
}


- (void) testConcurrentInBatch {
    const NSUInteger kNDocs = 100;
    const NSUInteger kNConcurrents = 5;
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        NSError* error;
        [self.db inBatch: &error do: ^{
            NSError* err;
            Assert([self createAndSaveDocs: kNDocs error: &err],
                   @"Error creating docs: %@", err);
        }];
    }];
    
    AssertEqual(self.db.count, kNDocs * kNConcurrents);
}


- (void) testConcurrentPurgeDocs {
    const NSUInteger kNDocs = 100;
    const NSUInteger kNConcurrents = 5;
    
    NSArray* docs = [self createAndSaveDocs: kNDocs error: nil];
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        for (CBLDocument* doc in docs) {
            NSError* error;
            if (![self.db purgeDocument: doc error: &error])
                AssertEqual(error.code, 404);
        }
    }];
    AssertEqual(self.db.count, 0u);
}


- (void) testConcurrentCompact {
    const NSUInteger kNDocs = 100;
    const NSUInteger kNRounds = 10;
    const NSUInteger kNConcurrents = 5;
    
    [self createAndSaveDocs: kNDocs error: nil];
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        for (NSUInteger i = 0; i < kNRounds; i++) {
            NSError* error;
            Assert([self.db compact: &error], @"Error when compact: %@", error);
        }
    }];
}


- (void) testConcurrentCreateDocsAndCloseDB {
    const NSUInteger kNDocs = 1000;
    const NSUInteger kNConcurrents = 1;
    
    __block BOOL hasException = NO;
    [self concurrentRuns: kNConcurrents waitUntilDone: NO withBlock: ^(NSUInteger rIndex) {
        ++gC4ExpectExceptions;
        @try {
            [self tryCreateAndSaveDocs: kNDocs error: nil];
        }
        @catch(NSException* exception) {
            AssertEqualObjects(exception.name, @"NSInternalInconsistencyException");
            hasException = YES;
        }
        --gC4ExpectExceptions;
    }];
    
    NSError* error;
    Assert([self.db close: &error], @"Error when closing the database: %@", error);
    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
    
    Assert(hasException);
}


- (void) testConcurrentCreateDocsAndDeleteDB {
    const NSUInteger kNDocs = 1000;
    const NSUInteger kNConcurrents = 1;
    
    __block BOOL hasException = NO;
    [self concurrentRuns: kNConcurrents waitUntilDone: NO withBlock: ^(NSUInteger rIndex) {
        ++gC4ExpectExceptions;
        @try {
            [self tryCreateAndSaveDocs: kNDocs error: nil];
        }
        @catch(NSException* exception) {
            AssertEqualObjects(exception.name, @"NSInternalInconsistencyException");
            hasException = YES;
        }
        --gC4ExpectExceptions;
    }];
    
    NSError* error;
    Assert([self.db deleteDatabase: &error], @"Error when deleting the database: %@", error);
    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
    
    Assert(hasException);
}


- (void) testDatabaseChange {
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Create"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Change"];
    [self.db addChangeListener: ^(CBLDatabaseChange *change) {
        [self waitForExpectations: @[exp1] timeout: 5.0]; // Test deadlock
        [exp2 fulfill];
    }];
    
    [self concurrentRuns: 1 waitUntilDone: NO withBlock: ^(NSUInteger rIndex) {
        [_db saveDocument: [[CBLDocument alloc] initWithID: @"doc1"]  error: nil];
        [exp1 fulfill];
    }];
    
    [self waitForExpectationsWithTimeout: 10.0 handler:^(NSError * _Nullable error) { }];
}


- (void) testDocumentChange {
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Create"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Change"];
    [self.db addChangeListenerForDocumentID: @"doc1" usingBlock:^(CBLDocumentChange *change) {
        [self waitForExpectations: @[exp1] timeout: 5.0]; // Test deadlock
        [exp2 fulfill];
    }];
    
    [self concurrentRuns: 1 waitUntilDone: NO withBlock: ^(NSUInteger rIndex) {
        [_db saveDocument: [[CBLDocument alloc] initWithID: @"doc1"]  error: nil];
        [exp1 fulfill];
    }];
    
    [self waitForExpectationsWithTimeout: 10.0 handler:^(NSError * _Nullable error) { }];
}


#pragma mark - Dictionary


- (void) updateDictionary: (CBLDictionary*)dict rounds: (NSUInteger)rounds  {
    for (NSUInteger r = 0; r < rounds; r++) {
        [self updateDictionary: dict custom: nil number: r];
    }
}


- (void) readDictionary: (CBLDictionary*)dict rounds: (NSUInteger)rounds {
    for (NSUInteger r = 1; r <= rounds; r++) {
        [self readDictionary: dict];
    }
}


// Enable when CBLDictionary is thread safe:
- (void) _testConcurrentUpdateNewDictionary {
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 10;
    
    __block CBLDictionary* dict = [[CBLDictionary alloc] init];
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        [self updateDictionary: dict rounds:kNRounds];
    }];
    
    // Verify:
    [self readDictionary: dict rounds: 1];
}


// Enable when CBLDictionary is thread safe:
- (void) _testConcurrentUpdateExistingDictionary {
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 10;
    
    CBLDictionary* dict = [[CBLDictionary alloc] init];
    [self updateDictionary: dict rounds: 1];
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: dict forKey: @"dict"];
    [self saveDocument: doc];
    
    doc = [self.db documentWithID: @"doc1"];
    dict = [doc dictionaryForKey: @"dict"];
    Assert(dict);
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        [self updateDictionary: dict rounds:kNRounds];
    }];
    
    // Verify:
    [self readDictionary: dict rounds: 1];
}


- (void) _testConcurrentReadNewDictionary {
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 10;
    
    CBLDictionary* dict = [[CBLDictionary alloc] init];
    [self updateDictionary: dict rounds: 1];
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        [self readDictionary: dict rounds: kNRounds];
    }];
}


- (void) _testConcurrentReadExistingDictionary {
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 10;
    
    CBLDictionary* dict = [[CBLDictionary alloc] init];
    [self updateDictionary: dict rounds: 1];
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: dict forKey: @"dict"];
    [self saveDocument: doc];
    
    doc = [self.db documentWithID: @"doc1"];
    dict = [doc dictionaryForKey: @"dict"];
    Assert(dict);
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        [self readDictionary: dict rounds: kNRounds];
    }];
}


#pragma mark - Array


- (void) updateArray: (CBLArray*)array rounds: (NSUInteger)rounds  {
    for (NSUInteger r = 0; r < rounds; r++) {
        [array addObject: @"an added string"];
        [array insertObject: @"an inserted string" atIndex: 0];
        [array removeObjectAtIndex: 0];
    }
}


- (void) readArray: (CBLArray*)array rounds: (NSUInteger)rounds {
    for (NSUInteger r = 0; r < rounds; r++) {
        NSUInteger count = array.count;
        Assert(count > 0); // Assume something in there
        
        for (NSUInteger i = 0; i < count; i++) {
            Assert([array objectAtIndex: i]);
        }
        
        NSUInteger nums = 0;
        for (id obj in array) {
            Assert(obj);
            nums++;
        }
        AssertEqual(nums, count);
    }
}


// Enable when CBLArray is thread safe:
- (void) _testConcurrentUpdateNewArray {
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 10;
    
    CBLArray* array = [[CBLArray alloc] init];
    [array addObject: @"a string"];
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        [self updateArray: array rounds: kNRounds];
    }];
    
    AssertEqual(array.count, (1 + kNRounds * kNConcurrents));
}


// Enable when CBLArray is thread safe:
- (void) _testConcurrentUpdateExistingArray {
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 10;
    
    CBLArray* array = [[CBLArray alloc] init];
    [self updateArray: array rounds: 1];
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: array forKey: @"array"];
    [self saveDocument: doc];
    
    doc = [self.db documentWithID: @"doc1"];
    array = [doc arrayForKey: @"array"];
    Assert(array);
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        [self updateArray: array rounds: kNRounds];
    }];
    
    AssertEqual(array.count, (1 + kNRounds * kNConcurrents));
}


// Enable when CBLArray is thread safe:
- (void) _testConcurrentReadNewArray {
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 10;
    
    CBLArray* array = [[CBLArray alloc] init];
    [self updateArray: array rounds: 100];
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        [self readArray: array rounds: kNRounds];
    }];
}


// Enable when CBLArray is thread safe:
- (void) _testConcurrentReadExistingArray {
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 10;
    
    CBLArray* array = [[CBLArray alloc] init];
    [self updateArray: array rounds: 100];
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: array forKey: @"array"];
    [self saveDocument: doc];
    
    doc = [self.db documentWithID: @"doc1"];
    array = [doc arrayForKey: @"array"];
    Assert(array);
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        [self readArray: array rounds: kNRounds];
    }];
}

@end

