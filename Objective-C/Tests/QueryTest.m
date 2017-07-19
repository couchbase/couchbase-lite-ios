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
#import "CBLQuerySelectResult.h"
#import "CBLQueryDataSource.h"
#import "CBLQueryOrdering.h"

#define kDOCID      [CBLQuerySelectResult expression: [CBLQueryExpression meta].documentID]
#define kSEQUENCE   [CBLQuerySelectResult expression: [CBLQueryExpression meta].sequence]

@interface QueryTest : CBLTestCase

@end

@implementation QueryTest


- (uint64_t) verifyQuery: (CBLQuery*)q
            randomAccess: (BOOL)randomAccess
                    test: (void (^)(uint64_t n, CBLQueryResult *result))block {
    NSError* error;
    CBLQueryResultSet* rs = [q run: &error];
    Assert(rs, @"Query failed: %@", error);
    uint64_t n = 0;
    for (CBLQueryResult *r in rs) {
        block(++n, r);
    }

    NSArray* all = rs.allObjects;
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
        CBLQuery* q = [CBLQuery select: @[kDOCID]
                                  from: [CBLQueryDataSource database: self.db]
                                 where: c[0]];
        NSPredicate* p = [NSPredicate predicateWithFormat: c[1]];
        NSMutableArray* result = [[numbers filteredArrayUsingPredicate: p] mutableCopy];
        uint64_t total = result.count;
        uint64_t rows = [self verifyQuery: q randomAccess: NO
                                     test: ^(uint64_t n, CBLQueryResult *r)
        {
            CBLDocument* doc = [self.db documentWithID: [r objectAtIndex: 0]];
            id dict = [doc toDictionary];
            Assert([result containsObject: dict]);
            [result removeObject: dict];
        }];
        AssertEqual(result.count, 0u);
        AssertEqual(rows, total);
    }
}


- (void) testNoWhereQuery {
    [self loadJSONResource: @"names_100"];
    
    CBLQuery* q = [CBLQuery select: @[kDOCID, kSEQUENCE]
                              from: [CBLQueryDataSource database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test:^(uint64_t n, CBLQueryResult *r)
    {
        NSString* docID = [r objectAtIndex: 0];
        NSString* expectedID = [NSString stringWithFormat: @"doc-%03llu", n];
        AssertEqualObjects(docID, expectedID);
        
        NSUInteger seq = [[r objectAtIndex: 1] unsignedIntegerValue];
        AssertEqual(seq, n);
        
        CBLDocument* doc = [self.db documentWithID: docID];
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
        CBLQuery *q = [CBLQuery select: @[kDOCID]
                                  from: [CBLQueryDataSource database: self.db]
                                 where: exp];
        uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                        test: ^(uint64_t n, CBLQueryResult* r)
        {
            if (expectedDocs.count <= n) {
                NSString* documentID = [r objectAtIndex: 0];
                CBLDocument* expDoc = expectedDocs[(NSUInteger)(n-1)];
                AssertEqualObjects(expDoc.documentID, documentID, @"Failed case: %@", exp);
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
    
    CBLQuery* q = [CBLQuery select: @[kDOCID]
                              from: [CBLQueryDataSource database: self.db]
                             where: [[CBLQueryExpression property: @"string"] is: @"string"]];
    
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
    {
        CBLDocument* doc = [self.db documentWithID: [r objectAtIndex: 0]];
        AssertEqualObjects(doc.documentID, doc1.documentID);
        AssertEqualObjects([doc objectForKey: @"string"], @"string");
    }];
    AssertEqual(numRows, 1u);
    
    q = [CBLQuery select: @[kDOCID]
                    from: [CBLQueryDataSource database: self.db]
                   where: [[CBLQueryExpression property: @"string"] isNot: @"string1"]];
    
    Assert(q);
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        CBLDocument* doc = [self.db documentWithID: [r objectAtIndex: 0]];
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
    CBLQuery* q = [CBLQuery select: @[kDOCID]
                              from: [CBLQueryDataSource database: self.db]
                             where: [firstName in: expected]
                           orderBy: @[[CBLQuerySortOrder property: @"name.first"]]];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test:^(uint64_t n, CBLQueryResult* r)
    {
        CBLDocument* doc = [self.db documentWithID: [r objectAtIndex: 0]];
        NSString* first = [[doc objectForKey: @"name"] objectForKey: @"first"];
        AssertEqualObjects(first, expected[(NSUInteger)(n-1)]);
    }];
    AssertEqual((int)numRows, (int)expected.count);
}


- (void) test_WhereLike {
    [self loadJSONResource: @"names_100"];
    
    CBLQueryExpression* where = [[CBLQueryExpression property: @"name.first"] like: @"%Mar%"];
    CBLQuery* q = [CBLQuery select: @[kDOCID]
                              from: [CBLQueryDataSource database: self.db]
                             where: where
                           orderBy: @[[[CBLQueryOrdering property: @"name.first"] ascending]]];
    
    NSMutableArray* firstNames = [NSMutableArray array];
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test:^(uint64_t n, CBLQueryResult* r) {
        CBLDocument* doc = [self.db documentWithID: [r objectAtIndex: 0]];
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
    CBLQuery* q = [CBLQuery select: @[kDOCID]
                              from: [CBLQueryDataSource database: self.db]
                             where: where
                           orderBy: @[[[CBLQueryOrdering property: @"name.first"] ascending]]];
    
    NSMutableArray* firstNames = [NSMutableArray array];
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test:^(uint64_t n, CBLQueryResult* r)
    {
        CBLDocument* doc = [self.db documentWithID: [r objectAtIndex: 0]];
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
    CBLQueryOrdering* order = [[CBLQueryOrdering property: @"rank(sentence)"] descending];
    CBLQuery* q = [CBLQuery select: @[]
                              from: [CBLQueryDataSource database: self.db]
                             where: where
                           orderBy: @[order]];
    uint64_t numRows = [self verifyQuery: q  randomAccess: YES
                                    test:^(uint64_t n, CBLQueryResult* r)
    {
        // TODO: Wait for the FTS API:
        // CBLFullTextQueryRow* ftsRow = (id)r;
        // NSString* text = ftsRow.fullTextMatched;
        //        Log(@"    full text = \"%@\"", text);
        //        Log(@"    matchCount = %u", (unsigned)ftsRow.matchCount);
        // Assert([text containsString: @"Dummie"]);
        // Assert([text containsString: @"woman"]);
        // AssertEqual(ftsRow.matchCount, 2ul);
    }];
    AssertEqual(numRows, 2u);
}


- (void) testOrderBy {
    [self loadJSONResource: @"names_100"];
    
    for (id ascending in @[@(YES), @(NO)]) {
        BOOL isAscending = [ascending boolValue];
        
        CBLQueryOrdering* order;
        if (isAscending)
            order = [[CBLQueryOrdering property: @"name.first"] ascending];
        else
            order = [[CBLQueryOrdering property: @"name.first"] descending];
        
        CBLQuery* q = [CBLQuery select: @[kDOCID]
                                  from: [CBLQueryDataSource database: self.db]
                                 where: nil
                               orderBy: @[order]];
        Assert(q);
        
        NSMutableArray* firstNames = [NSMutableArray array];
        uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                        test: ^(uint64_t n, CBLQueryResult* r)
        {
            CBLDocument* doc = [self.db documentWithID: [r objectAtIndex: 0]];
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
    
    CBLQuery* q = [CBLQuery selectDistinct: @[kDOCID]
                                      from: [CBLQueryDataSource database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSString* docID = [r objectAtIndex: 0];
        AssertEqualObjects(docID, doc1.documentID);
    }];
    AssertEqual(numRows, 1u);
}


- (void) testJoin {
    [self loadNumbers: 100];
    
    CBLDocument* joinme = [[CBLDocument alloc] initWithID: @"joinme"];
    [joinme setObject: @42 forKey: @"theone"];
    [self saveDocument: joinme];
    
    CBLQuerySelectResult* MAIN_DOC_ID =
        [CBLQuerySelectResult expression: [CBLQueryExpression metaFrom: @"main"].documentID];
    
    CBLQueryExpression* on = [[CBLQueryExpression property: @"number1" from: @"main"]
                              equalTo: [CBLQueryExpression property:@"theone" from:@"secondary"]];
    CBLQueryJoin* join = [CBLQueryJoin join: [CBLQueryDataSource database: self.db as: @"secondary"]
                                         on: on];
    CBLQuery* q = [CBLQuery select: @[MAIN_DOC_ID]
                              from: [CBLQueryDataSource database: self.db as: @"main"]
                              join: @[join]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
    {
        CBLDocument* doc = [self.db documentWithID: [r objectAtIndex: 0]];
        AssertEqual([doc integerForKey:@"number1"], 42);
    }];
    AssertEqual(numRows, 1u);
}


- (void) testAggregateFunctions {
    [self loadNumbers: 100];
    
    CBLQueryExpression* AVG = [CBLQueryFunction avg: [CBLQueryExpression property: @"number1"]];
    CBLQueryExpression* CNT = [CBLQueryFunction count: [CBLQueryExpression property: @"number1"]];
    CBLQueryExpression* MIN = [CBLQueryFunction min: [CBLQueryExpression property: @"number1"]];
    CBLQueryExpression* MAX = [CBLQueryFunction max: [CBLQueryExpression property: @"number1"]];
    CBLQueryExpression* SUM = [CBLQueryFunction sum: [CBLQueryExpression property: @"number1"]];
    
    NSArray* results = @[[CBLQuerySelectResult expression: AVG],
                         [CBLQuerySelectResult expression: CNT],
                         [CBLQuerySelectResult expression: MIN],
                         [CBLQuerySelectResult expression: MAX],
                         [CBLQuerySelectResult expression: SUM]];
    
    CBLQuery* q = [CBLQuery select: results
                              from: [CBLQueryDataSource database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqual([[r objectAtIndex:0] doubleValue], 50.5);
        AssertEqual([[r objectAtIndex:1] integerValue], 100);
        AssertEqual([[r objectAtIndex:2] integerValue], 1);
        AssertEqual([[r objectAtIndex:3] integerValue], 100);
        AssertEqual([[r objectAtIndex:4] integerValue], 5050);
    }];
    AssertEqual(numRows, 1u);
}


- (void) testGroupBy {
    NSArray* expectedStates  = @[@"AL",    @"CA",    @"CO",    @"FL",    @"IA"];
    NSArray* expectedCounts  = @[@1,       @6,       @1,       @1,       @3];
    NSArray* expectedMaxZips = @[@"35243", @"94153", @"81223", @"33612", @"50801"];
    
    [self loadJSONResource: @"names_100"];
    
    CBLQueryExpression* STATE  = [CBLQueryExpression property: @"contact.address.state"];
    CBLQueryExpression* COUNT  = [CBLQueryFunction count: @(1)];
    CBLQueryExpression* ZIP    = [CBLQueryExpression property: @"contact.address.zip"];
    CBLQueryExpression* MAXZIP = [CBLQueryFunction max: ZIP];
    CBLQueryExpression* GENDER = [CBLQueryExpression property: @"gender"];
    
    NSArray* results = @[[CBLQuerySelectResult expression: STATE],
                         [CBLQuerySelectResult expression: COUNT],
                         [CBLQuerySelectResult expression: MAXZIP]];
    
    CBLQuery* q = [CBLQuery select: results
                              from: [CBLQueryDataSource database: self.db]
                             where: [GENDER equalTo: @"female"]
                           groupBy: @[STATE]
                            having: nil
                           orderBy: @[[CBLQueryOrdering expression: STATE]]
                             limit: nil];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSString* state = [r objectAtIndex: 0];
        NSInteger count = [[r objectAtIndex: 1] integerValue];
        NSString* maxZip = [r objectAtIndex: 2];
        // Log(@"State = %@, count = %d, maxZip = %@", state, (int)count, maxZip);
        if (n-1 < expectedStates.count) {
            AssertEqualObjects(state,  expectedStates[(NSUInteger)(n-1)]);
            AssertEqual       (count,  [expectedCounts[(NSUInteger)(n-1)] integerValue]);
            AssertEqualObjects(maxZip, expectedMaxZips[(NSUInteger)(n-1)]);
        }
    }];
    AssertEqual(numRows, 31u);
    
    // With HAVING:
    expectedStates  = @[@"CA",    @"IA",     @"IN"];
    expectedCounts  = @[@6,       @3,        @2];
    expectedMaxZips = @[@"94153", @"50801",  @"47952"];
    
    q = [CBLQuery select: results
                    from: [CBLQueryDataSource database: self.db]
                   where: [GENDER equalTo: @"female"]
                 groupBy: @[STATE]
                  having: [COUNT greaterThan: @(1)]
                 orderBy: @[[CBLQueryOrdering expression: STATE]]
                   limit: nil];
    
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r) {
        NSString* state = [r objectAtIndex: 0];
        NSInteger count = [[r objectAtIndex: 1] integerValue];
        NSString* maxZip = [r objectAtIndex: 2];
        // Log(@"State = %@, count = %d, maxZip = %@", state, (int)count, maxZip);
        if (n-1 < expectedStates.count) {
            AssertEqualObjects(state,  expectedStates[(NSUInteger)(n-1)]);
            AssertEqual       (count,  [expectedCounts[(NSUInteger)(n-1)] integerValue]);
            AssertEqualObjects(maxZip, expectedMaxZips[(NSUInteger)(n-1)]);
        }
    }];
    AssertEqual(numRows, 15u);
}


- (void) testParameters {
    [self loadNumbers: 10];
    
    CBLQueryExpression* NUMBER1  = [CBLQueryExpression property: @"number1"];
    CBLQueryExpression* PARAM_N1 = [CBLQueryExpression parameterNamed: @"num1"];
    CBLQueryExpression* PARAM_N2 = [CBLQueryExpression parameterNamed: @"num2"];
    
    CBLQuery* q= [CBLQuery select: @[[CBLQuerySelectResult expression: NUMBER1]]
                             from: [CBLQueryDataSource database: self.db]
                            where: [NUMBER1 between: PARAM_N1 and: PARAM_N2]
                          orderBy: @[[CBLQueryOrdering expression: NUMBER1]]];
    
    [q.parameters setValue: @(2) forName: @"num1"];
    [q.parameters setValue: @(5) forName: @"num2"];
    
    NSArray* expectedNumbers = @[@2, @3, @4, @5];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r) {
        NSInteger number = [[r objectAtIndex: 0] integerValue];
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 4u);
}


- (void) testMeta {
    [self loadNumbers: 5];
    
    CBLQueryExpression* DOC_ID  = [CBLQueryExpression meta].documentID;
    CBLQueryExpression* DOC_SEQ = [CBLQueryExpression meta].sequence;
    CBLQueryExpression* NUMBER1  = [CBLQueryExpression property: @"number1"];
    
    CBLQuerySelectResult* RES_DOC_ID = [CBLQuerySelectResult expression: DOC_ID];
    CBLQuerySelectResult* RES_DOC_SEQ = [CBLQuerySelectResult expression: DOC_SEQ];
    CBLQuerySelectResult* RES_NUMBER1 = [CBLQuerySelectResult expression: NUMBER1];
    
    CBLQuery* q = [CBLQuery select: @[RES_DOC_ID, RES_DOC_SEQ, RES_NUMBER1]
                              from: [CBLQueryDataSource database: self.db]
                             where: nil
                           orderBy: @[[CBLQueryOrdering expression: DOC_SEQ]]];
    
    NSArray* expectedDocIDs  = @[@"doc1", @"doc2", @"doc3", @"doc4", @"doc5"];
    NSArray* expectedSeqs    = @[@1, @2, @3, @4, @5];
    NSArray* expectedNumbers = @[@1, @2, @3, @4, @5];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r) {
        NSString* docID = [r objectAtIndex: 0];
        NSInteger seq = [[r objectAtIndex: 1] integerValue];
        NSInteger number = [[r objectAtIndex: 2] integerValue];
        
        AssertEqualObjects(docID,  expectedDocIDs[(NSUInteger)(n-1)]);
        AssertEqual(seq, [expectedSeqs[(NSUInteger)(n-1)] integerValue]);
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 5u);
}


- (void) testLimit {
    [self loadNumbers: 10];
    
    CBLQueryExpression* NUMBER1  = [CBLQueryExpression property: @"number1"];
    
    CBLQuery* q= [CBLQuery select: @[[CBLQuerySelectResult expression: NUMBER1]]
                             from: [CBLQueryDataSource database: self.db]
                            where: nil groupBy: nil having: nil
                          orderBy: @[[CBLQueryOrdering expression: NUMBER1]]
                            limit: [CBLQueryLimit limit: @5]];
    
    NSArray* expectedNumbers = @[@1, @2, @3, @4, @5];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSInteger number = [[r objectAtIndex: 0] integerValue];
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 5u);
    
    q= [CBLQuery select: @[[CBLQuerySelectResult expression: NUMBER1]]
                   from: [CBLQueryDataSource database: self.db]
                  where: nil groupBy: nil having: nil
                orderBy: @[[CBLQueryOrdering expression: NUMBER1]]
                  limit: [CBLQueryLimit limit: [CBLQueryExpression parameterNamed: @"LIMIT_NUM"]]];
    [q.parameters setValue: @3 forName: @"LIMIT_NUM"];
    
    expectedNumbers = @[@1, @2, @3];
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSInteger number = [[r objectAtIndex: 0] integerValue];
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 3u);
}


- (void) testLimitOffset {
    [self loadNumbers: 10];
    
    CBLQueryExpression* NUMBER1  = [CBLQueryExpression property: @"number1"];
    
    CBLQuery* q= [CBLQuery select: @[[CBLQuerySelectResult expression: NUMBER1]]
                             from: [CBLQueryDataSource database: self.db]
                            where: nil groupBy: nil having: nil
                          orderBy: @[[CBLQueryOrdering expression: NUMBER1]]
                            limit: [CBLQueryLimit limit: @5 offset: @3]];
    
    NSArray* expectedNumbers = @[@4, @5, @6, @7, @8];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSInteger number = [[r objectAtIndex: 0] integerValue];
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 5u);
    
    q= [CBLQuery select: @[[CBLQuerySelectResult expression: NUMBER1]]
                   from: [CBLQueryDataSource database: self.db]
                  where: nil groupBy: nil having: nil
                orderBy: @[[CBLQueryOrdering expression: NUMBER1]]
                  limit: [CBLQueryLimit limit: [CBLQueryExpression parameterNamed: @"LIMIT_NUM"]
                                       offset: [CBLQueryExpression parameterNamed:@"OFFSET_NUM"]]];
    [q.parameters setValue: @3 forName: @"LIMIT_NUM"];
    [q.parameters setValue: @5 forName: @"OFFSET_NUM"];
    
    expectedNumbers = @[@6, @7, @8];
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSInteger number = [[r objectAtIndex: 0] integerValue];
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 3u);
}


- (void) testQueryResult {
    [self loadJSONResource: @"names_100"];
    
    CBLQueryExpression* FNAME = [CBLQueryExpression property: @"name.first"];
    CBLQueryExpression* LNAME = [CBLQueryExpression property: @"name.last"];
    CBLQueryExpression* GENDER = [CBLQueryExpression property: @"gender"];
    CBLQueryExpression* CITY = [CBLQueryExpression property: @"contact.address.city"];
    
    CBLQuerySelectResult* RES_FNAME = [CBLQuerySelectResult expression: FNAME as: @"firstname"];
    CBLQuerySelectResult* RES_LNAME = [CBLQuerySelectResult expression: LNAME as: @"lastname"];
    CBLQuerySelectResult* RES_GENDER = [CBLQuerySelectResult expression: GENDER];
    CBLQuerySelectResult* RES_CITY = [CBLQuerySelectResult expression: CITY];
    
    CBLQuery* q = [CBLQuery select: @[RES_FNAME, RES_LNAME, RES_GENDER, RES_CITY]
                              from: [CBLQueryDataSource database: self.db]];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqualObjects([r objectForKey: @"firstname"], [r objectAtIndex: 0]);
        AssertEqualObjects([r objectForKey: @"lastname"], [r objectAtIndex: 1]);
        AssertEqualObjects([r objectForKey: @"gender"], [r objectAtIndex: 2]);
        AssertEqualObjects([r objectForKey: @"city"], [r objectAtIndex: 3]);
    }];
    AssertEqual((int)numRows, 100);
}


- (void) testQueryProvResultKeys {
    [self loadNumbers: 100];
    
    CBLQueryExpression* AVG = [CBLQueryFunction avg: [CBLQueryExpression property: @"number1"]];
    CBLQueryExpression* CNT = [CBLQueryFunction count: [CBLQueryExpression property: @"number1"]];
    CBLQueryExpression* MIN = [CBLQueryFunction min: [CBLQueryExpression property: @"number1"]];
    CBLQueryExpression* MAX = [CBLQueryFunction max: [CBLQueryExpression property: @"number1"]];
    CBLQueryExpression* SUM = [CBLQueryFunction sum: [CBLQueryExpression property: @"number1"]];
    
    NSArray* results = @[[CBLQuerySelectResult expression: AVG],
                         [CBLQuerySelectResult expression: CNT],
                         [CBLQuerySelectResult expression: MIN as: @"min"],
                         [CBLQuerySelectResult expression: MAX],
                         [CBLQuerySelectResult expression: SUM as: @"sum"]];
    
    CBLQuery* q = [CBLQuery select: results
                              from: [CBLQueryDataSource database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqual([r doubleForKey: @"$1"], [r doubleAtIndex: 0]);
        AssertEqual([r integerForKey: @"$2"], [r integerAtIndex: 1]);
        AssertEqual([r integerForKey: @"min"], [r integerAtIndex: 2]);
        AssertEqual([r integerForKey: @"$3"], [r integerAtIndex: 3]);
        AssertEqual([r integerForKey: @"sum"], [r integerAtIndex: 4]);
    }];
    AssertEqual(numRows, 1u);
}


- (void) testLiveQuery {
    [self loadNumbers: 100];
    
    __block int count = 0;
    XCTestExpectation* x = [self expectationWithDescription: @"changes"];
    CBLLiveQuery* q = [[CBLQuery select: @[kDOCID]
                                   from: [CBLQueryDataSource database: self.db]
                                  where: [[CBLQueryExpression property: @"number1"] lessThan: @(10)]
                                orderBy: @[[CBLQueryOrdering property: @"number1"]]] toLive];
    id listener = [q addChangeListener:^(CBLLiveQueryChange* change) {
        count++;
        AssertNotNil(change.query);
        AssertNil(change.error);
        NSArray<CBLQueryResult*>* rows = [change.rows allObjects];
        if (count == 1) {
            AssertEqual(rows.count, 9u);
        } else {
            AssertEqual(rows.count, 10u);
            CBLDocument* doc = [self.db documentWithID: [rows[0] objectAtIndex: 0]];
            AssertEqualObjects([doc objectForKey: @"number1"], @(-1));
            [x fulfill];
        }
    }];
    
    [q start];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self createDocNumbered: -1 of: 100];
    });

    [self waitForExpectationsWithTimeout: 2.0 handler: ^(NSError *error) { }];
    NSLog(@"Done!");
    
    [q removeChangeListener: listener];
    [q stop];
}


- (void) testLiveQueryNoUpdate {
    [self loadNumbers: 100];
    
    __block int count = 0;
    CBLLiveQuery* q = [[CBLQuery select: @[]
                                   from: [CBLQueryDataSource database: self.db]
                                  where: [[CBLQueryExpression property: @"number1"] lessThan: @(10)]
                                orderBy: @[[CBLQueryOrdering property: @"number1"]]] toLive];
    
    id listener = [q addChangeListener:^(CBLLiveQueryChange* change) {
        count++;
        AssertNotNil(change.query);
        AssertNil(change.error);
        NSArray<CBLQueryResult*>* rows = [change.rows allObjects];
        if (count == 1) {
            AssertEqual(rows.count, 9u);
        } else {
            XCTFail(@"Unexpected update from LiveQuery");
        }
    }];
    
    [q start];

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
    [q stop];
}

@end
