//
//  QueryTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLQuery.h"
#import "CBLLiveQuery.h"
#import "CBLQuerySelect.h"
#import "CBLQueryDataSource.h"
#import "CBLQueryOrderBy.h"


@interface QueryTest : CBLTestCase

@end

@implementation QueryTest


- (uint64_t) verifyQuery: (CBLQuery*)q
            randomAccess: (BOOL)randomAccess
                    test: (void (^)(uint64_t n, CBLQueryRow *row))block {
    NSError* error;
    NSEnumerator* e = [q run: &error];
    Assert(e, @"Query failed: %@", error);
    uint64_t n = 0;
    for (CBLQueryRow *row in e) {
        //Log(@"Row: docID='%@', sequence=%llu", row.documentID, row.sequence);
        block(++n, row);
    }

    NSArray* all = e.allObjects;
    AssertEqual(all.count, n);
    if (randomAccess && n > 0) {
        // Note: the block's 1st parameter is 1-based, while NSArray is 0-based
        block(n,       all[(NSUInteger)(n-1)]);
        block(1,       all[0]);
        block(n/2 + 1, all[(NSUInteger)(n/2)]);
    }
    return n;
}


- (CBLDocument*) createDocNumbered: (NSInteger)i of: (NSInteger)num {
    NSString* docID= [NSString stringWithFormat: @"doc%ld", (long)i];
    CBLDocument* doc = [[CBLDocument alloc] initWithID: docID];
    [doc setObject: @(i) forKey: @"number1"];
    [doc setObject: @(num-i) forKey: @"number2"];
    NSError *error;
    BOOL saved = [_db saveDocument: doc error: &error];
    Assert(saved, @"Couldn't save document: %@", error);
    return doc;
}


- (NSArray*)loadNumbers:(NSInteger)num {
    NSMutableArray* numbers = [NSMutableArray array];
    NSError *batchError;
    BOOL ok = [self.db inBatch: &batchError do: ^{
        for (NSInteger i = 1; i <= num; i++) {
            CBLDocument* doc = [self createDocNumbered: i of: num];
            [numbers addObject: [doc toDictionary]];
        }
    }];
    Assert(ok, @"Error when inserting documents: %@", batchError);
    return numbers;
}


- (void) runTestWithNumbers: (NSArray*)numbers cases: (NSArray*)cases {
    for (NSArray* c in cases) {
        CBLQuery* q = [CBLQuery select: [CBLQuerySelect all]
                                  from: [CBLQueryDatabase database: self.db]
                                 where: c[0]];
        NSPredicate* p = [NSPredicate predicateWithFormat: c[1]];
        NSMutableArray* result = [[numbers filteredArrayUsingPredicate: p] mutableCopy];
        uint64_t total = result.count;
        uint64_t rows = [self verifyQuery: q randomAccess: NO
                                     test: ^(uint64_t n, CBLQueryRow *row) {
            id dict = [row.document toDictionary];
            Assert([result containsObject: dict]);
            [result removeObject: dict];
        }];
        AssertEqual(result.count, 0u);
        AssertEqual(rows, total);
    }
}


- (void) testNoWhereQuery {
    [self loadJSONResource: @"names_100"];
    
    CBLQuery* q = [CBLQuery select: [CBLQuerySelect all]
                              from: [CBLQueryDatabase database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test:^(uint64_t n, CBLQueryRow *row) {
        NSString* expectedID = [NSString stringWithFormat: @"doc-%03llu", n];
        AssertEqualObjects(row.documentID, expectedID);
        AssertEqual(row.sequence, n);
        CBLDocument* doc = row.document;
        AssertEqualObjects(doc.documentID, expectedID);
        AssertEqual(doc.sequence, n);
    }];
    AssertEqual(numRows, 100llu);
}


- (void) testWhereComparison {
    CBLQueryExpression* n1 = [CBLQueryExpression property: @"number1"];
    NSArray* cases = @[
        @[[n1 lessThan: @(3)], @"number1 < 3"],
        @[[n1 notLessThan: @(3)], @"number1 >= 3"],
        @[[n1 lessThanOrEqualTo: @(3)], @"number1 <= 3"],
        @[[n1 notLessThanOrEqualTo: @(3)], @"number1 > 3"],
        @[[n1 greaterThan: @(6)], @"number1 > 6"],
        @[[n1 notGreaterThan: @(6)], @"number1 <= 6"],
        @[[n1 greaterThanOrEqualTo: @(6)], @"number1 >= 6"],
        @[[n1 notGreaterThanOrEqualTo: @(6)], @"number1 < 6"],
        @[[n1 equalTo: @(7)], @"number1 == 7"],
        @[[n1 notEqualTo: @(7)], @"number1 != 7"]
    ];
    NSArray* numbers = [self loadNumbers: 10];
    [self runTestWithNumbers: numbers cases: cases];
}


- (void) testWhereArithmetic {
    CBLQueryExpression* n1 = [CBLQueryExpression property: @"number1"];
    CBLQueryExpression* n2 = [CBLQueryExpression property: @"number2"];
    NSArray* cases = @[
        @[[[n1 multiply: @(2)] greaterThan: @(8)], @"(number1 * 2) > 8"],
        @[[[n1 divide: @(2)] greaterThan: @(3)], @"(number1 / 2) > 3"],
        @[[[n1 modulo: @(2)] equalTo: @(0)], @"modulus:by:(number1, 2) == 0"],
        @[[[n1 add: @(5)] greaterThan: @(10)], @"(number1 + 5) > 10"],
        @[[[n1 subtract: @(5)] greaterThan: @(0)], @"(number1 - 5) > 0"],
        @[[[n1 multiply: n2] greaterThan: @(10)], @"(number1 * number2) > 10"],
        @[[[n2 divide: n1] greaterThan: @(3)], @"(number2 / number1) > 3"],
        @[[[n2 modulo: n1] equalTo: @(0)], @"modulus:by:(number2, number1) == 0"],
        @[[[n1 add: n2] equalTo: @(10)], @"(number1 + number2) == 10"],
        @[[[n1 subtract: n2] greaterThan: @(0)], @"(number1 - number2) > 0"]
    ];
    NSArray* numbers = [self loadNumbers: 10];
    [self runTestWithNumbers: numbers cases: cases];
}


- (void) testWhereAndOr {
    CBLQueryExpression* n1 = [CBLQueryExpression property: @"number1"];
    CBLQueryExpression* n2 = [CBLQueryExpression property: @"number2"];
    NSArray* cases = @[
        @[[[n1 greaterThan: @(3)] and: [n2 greaterThan: @(3)]], @"number1 > 3 AND number2 > 3"],
        @[[[n1 lessThan: @(3)] or: [n2 lessThan: @(3)]], @"number1 < 3 OR number2 < 3"]
    ];
    NSArray* numbers = [self loadNumbers: 10];
    [self runTestWithNumbers: numbers cases: cases];
}


- (void) failingTest_WhereCheckNull {
    // https://github.com/couchbase/couchbase-lite-ios/issues/1670
    NSError* error;
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    [doc1 setObject: @"Scott" forKey: @"name"];
    [doc1 setObject: [NSNull null] forKey: @"address"];
    Assert([_db saveDocument: doc1 error: &error], @"Error when saving a document: %@", error);
    
    CBLDocument* doc2 = [self.db documentWithID: @"doc2"];
    [doc2 setObject: @"Scott" forKey: @"name"];
    [doc2 setObject: @"123 1st ave." forKey: @"address"];
    [doc2 setObject: @(20) forKey: @"age"];
    Assert([_db saveDocument: doc2 error: &error], @"Error when saving a document: %@", error);
    
    CBLQueryExpression* name = [CBLQueryExpression property: @"name"];
    CBLQueryExpression* address = [CBLQueryExpression property: @"address"];
    CBLQueryExpression* age = [CBLQueryExpression property: @"age"];
    CBLQueryExpression* work = [CBLQueryExpression property: @"work"];
    
    NSArray* tests = @[
       @[[name notNull],    @[doc1, doc2]],
       @[[name isNull],     @[]],
       @[[address notNull], @[doc2]],
       @[[address isNull],  @[doc1]],
       @[[age notNull],     @[doc2]],
       @[[age isNull],      @[doc1]],
       @[[work notNull],    @[]],
       @[[work isNull],     @[doc1, doc2]],
    ];
    
    for (NSArray* test in tests) {
        CBLQueryExpression* exp = test[0];
        NSArray* expectedDocs = test[1];
        CBLQuery *q = [CBLQuery select: [CBLQuerySelect all]
                                  from: [CBLQueryDatabase database: self.db]
                                 where: exp];
        uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                        test:^(uint64_t n, CBLQueryRow *row) {
            if (expectedDocs.count <= n) {
                CBLDocument* doc = expectedDocs[(NSUInteger)(n-1)];
                AssertEqualObjects(doc.documentID, row.documentID, @"Failed case: %@", exp);
            }
        }];
        AssertEqual((int)numRows, (int)expectedDocs.count, @"Failed case: %@", exp);
    }
}


- (void) testWhereIs {
    NSError* error;
    CBLDocument* doc1 = [[CBLDocument alloc] init];
    [doc1 setObject: @"string" forKey: @"string"];
    Assert([_db saveDocument: doc1 error: &error], @"Error when creating a document: %@", error);
    
    CBLQuery* q = [CBLQuery select: [CBLQuerySelect all]
                              from: [CBLQueryDatabase database: self.db]
                             where: [[CBLQueryExpression property: @"string"] is: @"string"]];
    
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        AssertEqualObjects(doc.documentID, doc1.documentID);
        AssertEqualObjects([doc objectForKey: @"string"], @"string");
    }];
    AssertEqual(numRows, 1u);
    
    q = [CBLQuery select: [CBLQuerySelect all]
                    from: [CBLQueryDatabase database: self.db]
                   where: [[CBLQueryExpression property: @"string"] isNot: @"string1"]];
    
    Assert(q);
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        AssertEqualObjects(doc.documentID, doc1.documentID);
        AssertEqualObjects([doc objectForKey: @"string"], @"string");
    }];
    AssertEqual(numRows, 1u);
}


- (void) testWhereBetween {
    CBLQueryExpression* n1 = [CBLQueryExpression property: @"number1"];
    NSArray* cases = @[
        @[[n1 between: @(3) and: @(7)], @"number1 BETWEEN {3,7}"]
    ];
    NSArray* numbers = [self loadNumbers: 10];
    [self runTestWithNumbers: numbers cases: cases];
}


- (void) testWhereIn {
    [self loadJSONResource: @"names_100"];
    
    NSArray* expected = @[@"Marcy", @"Margaretta", @"Margrett", @"Marlen", @"Maryjo"];
    CBLQueryExpression* firstName = [CBLQueryExpression property: @"name.first"];
    CBLQuery* q = [CBLQuery select: [CBLQuerySelect all]
                              from: [CBLQueryDataSource database: self.db]
                             where: [firstName in: expected]
                           orderBy: [CBLQuerySortOrder property: @"name.first"]];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test:^(uint64_t n, CBLQueryRow *row) {
        NSString* first = [[row.document objectForKey: @"name"] objectForKey: @"first"];
        AssertEqualObjects(first, expected[(NSUInteger)(n-1)]);
    }];
    AssertEqual((int)numRows, (int)expected.count);
}


- (void) test_WhereLike {
    [self loadJSONResource: @"names_100"];
    
    CBLQueryExpression* where = [[CBLQueryExpression property: @"name.first"] like: @"%Mar%"];
    CBLQuery* q = [CBLQuery select: [CBLQuerySelect all]
                              from: [CBLQueryDatabase database: self.db]
                             where: where
                           orderBy: [[CBLQueryOrderBy property: @"name.first"] ascending]];
    
    NSMutableArray* firstNames = [NSMutableArray array];
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test:^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        NSString* firstName = [[doc objectForKey:@"name"] objectForKey: @"first"];
        if (firstName)
            [firstNames addObject: firstName];
    }];
    AssertEqual(numRows, 5u);
    AssertEqual(firstNames.count, 5u);
}


- (void) test_WhereRegex {
    [self loadJSONResource: @"names_100"];
    
    CBLQueryExpression* where = [[CBLQueryExpression property: @"name.first"] regex: @"^Mar.*"];
    CBLQuery* q = [CBLQuery select: [CBLQuerySelect all]
                              from: [CBLQueryDatabase database: self.db]
                             where: where
                           orderBy: [[CBLQueryOrderBy property: @"name.first"] ascending]];
    
    NSMutableArray* firstNames = [NSMutableArray array];
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test:^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        NSString* firstName = [[doc objectForKey:@"name"] objectForKey: @"first"];
        if (firstName)
            [firstNames addObject: firstName];
    }];
    AssertEqual(numRows, 5u);
    AssertEqual(firstNames.count, 5u);
}


- (void) testWhereMatch {
    [self loadJSONResource: @"sentences"];
    
    NSError* error;
    Assert([_db createIndexOn: @[@"sentence"] type: kCBLFullTextIndex options: NULL error: &error]);
    
    CBLQueryExpression* where = [[CBLQueryExpression property: @"sentence"] match: @"'Dummie woman'"];
    CBLQueryOrderBy* order = [[CBLQueryOrderBy property: @"rank(sentence)"] descending];
    CBLQuery* q = [CBLQuery select: [CBLQuerySelect all]
                              from: [CBLQueryDatabase database: self.db]
                             where: where
                           orderBy: order];
    uint64_t numRows = [self verifyQuery: q  randomAccess: YES
                                    test:^(uint64_t n, CBLQueryRow *row) {
        CBLFullTextQueryRow* ftsRow = (id)row;
        NSString* text = ftsRow.fullTextMatched;
        //        Log(@"    full text = \"%@\"", text);
        //        Log(@"    matchCount = %u", (unsigned)ftsRow.matchCount);
        Assert([text containsString: @"Dummie"]);
        Assert([text containsString: @"woman"]);
        AssertEqual(ftsRow.matchCount, 2ul);
    }];
    AssertEqual(numRows, 2u);
}


- (void) testOrderBy {
    [self loadJSONResource: @"names_100"];
    
    for (id ascending in @[@(YES), @(NO)]) {
        BOOL isAscending = [ascending boolValue];
        
        CBLQueryOrderBy* order;
        if (isAscending)
            order = [[CBLQueryOrderBy property: @"name.first"] ascending];
        else
            order = [[CBLQueryOrderBy property: @"name.first"] descending];
        
        CBLQuery* q = [CBLQuery select: [CBLQuerySelect all]
                                  from: [CBLQueryDatabase database: self.db]
                                 where: nil
                               orderBy: order];
        Assert(q);
        
        NSMutableArray* firstNames = [NSMutableArray array];
        uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                        test:^(uint64_t n, CBLQueryRow *row) {
            CBLDocument* doc = row.document;
            NSString* firstName = [[doc objectForKey:@"name"] objectForKey: @"first"];
            if (firstName)
                [firstNames addObject: firstName];
        }];
        AssertEqual(numRows, 100llu);
        AssertEqual(numRows, firstNames.count);
        
        NSSortDescriptor* desc = [NSSortDescriptor sortDescriptorWithKey: nil
                                                               ascending: isAscending
                                                                selector: @selector(localizedCompare:)];
        AssertEqualObjects(firstNames, [firstNames sortedArrayUsingDescriptors: @[desc]]);
    }
}


- (void) failingTest_SelectDistinct {
    // https://github.com/couchbase/couchbase-lite-ios/issues/1669
    NSError* error;
    CBLDocument* doc1 = [[CBLDocument alloc] init];
    [doc1 setObject: @(1) forKey: @"number"];
    Assert([_db saveDocument: doc1 error: &error], @"Error when creating a document: %@", error);
    
    CBLDocument* doc2 = [[CBLDocument alloc] init];
    [doc2 setObject: @(1) forKey: @"number"];
    Assert([_db saveDocument: doc2 error: &error], @"Error when creating a document: %@", error);
    
    CBLQuery* q = [CBLQuery selectDistinct: [CBLQuerySelect all]
                                     from: [CBLQueryDatabase database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryRow *row) {
        AssertEqualObjects(row.documentID, doc1.documentID);
    }];
    AssertEqual(numRows, 1u);
}


- (void) testLiveQuery {
    [self loadNumbers: 100];
    
    __block int count = 0;
    XCTestExpectation* x = [self expectationWithDescription: @"changes"];
    CBLLiveQuery* q = [[CBLQuery select: [CBLQuerySelect all]
                                   from: [CBLQueryDatabase database: self.db]
                                  where: [[CBLQueryExpression property: @"number1"] lessThan: @(10)]
                                orderBy: [CBLQueryOrderBy property: @"number1"]] toLive];
    id listener = [q addChangeListener:^(CBLLiveQueryChange* change) {
        count++;
        AssertNotNil(change.query);
        AssertNil(change.error);
        NSArray<CBLQueryRow*>* rows = [change.rows allObjects];
        if (count == 1) {
            AssertEqual(rows.count, 9u);
        } else {
            AssertEqual(rows.count, 10u);
            AssertEqualObjects([rows[0].document objectForKey: @"number1"], @(-1));
            [x fulfill];
        }
    }];
    
    [q run];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self createDocNumbered: -1 of: 100];
    });

    [self waitForExpectationsWithTimeout: 2.0 handler: ^(NSError *error) { }];
    NSLog(@"Done!");
    
    [q removeChangeListener: listener];
}


- (void) testLiveQueryNoUpdate {
    [self loadNumbers: 100];
    
    __block int count = 0;
    CBLLiveQuery* q = [[CBLQuery select: [CBLQuerySelect all]
                                   from: [CBLQueryDatabase database: self.db]
                                  where: [[CBLQueryExpression property: @"number1"] lessThan: @(10)]
                                orderBy: [CBLQueryOrderBy property: @"number1"]] toLive];
    
    id listener = [q addChangeListener:^(CBLLiveQueryChange* change) {
        count++;
        AssertNotNil(change.query);
        AssertNil(change.error);
        NSArray<CBLQueryRow*>* rows = [change.rows allObjects];
        if (count == 1) {
            AssertEqual(rows.count, 9u);
        } else {
            XCTFail(@"Unexpected update from LiveQuery");
        }
    }];
    
    [q run];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // This change will not affect the query results because 'number1 < 10' is not true.
        [self createDocNumbered: 111 of: 100];
    });

    // Wait 2 seconds, then fulfil the expectation:
    XCTestExpectation *x = [self expectationWithDescription: @"Timeout"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [x fulfill];
    });
    
    NSLog(@"Waiting...");
    [self waitForExpectationsWithTimeout: 5.0 handler: ^(NSError *error) { }];
    NSLog(@"Done!");
    
    AssertEqual(count, 1);
    
    [q removeChangeListener: listener];
}

@end
