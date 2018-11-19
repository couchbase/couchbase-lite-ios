//
//  QueryTest.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLTestCase.h"
#import "CBLLiveQuery.h"
#import "CBLQuery+internal.h"
#import "CBLQueryBuilder.h"
#import "CBLQuerySelectResult.h"
#import "CBLQueryDataSource.h"
#import "CBLQueryOrdering.h"

#define kDOCID      [CBLQuerySelectResult expression: [CBLQueryMeta id]]
#define kSEQUENCE   [CBLQuerySelectResult expression: [CBLQueryMeta sequence]]

@interface QueryTest : CBLTestCase

@end

@implementation QueryTest


- (uint64_t) verifyQuery: (CBLQuery*)q
            randomAccess: (BOOL)randomAccess
                    test: (void (^)(uint64_t n, CBLQueryResult *result))block {
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    uint64_t n = 0;
    for (CBLQueryResult *r in rs) {
        block(++n, r);
    }
    
    rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
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


- (CBLMutableDocument*) createDocNumbered: (NSInteger)i of: (NSInteger)num {
    NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)i];
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: docID];
    [doc setValue: @(i) forKey: @"number1"];
    [doc setValue: @(num-i) forKey: @"number2"];
    [self saveDocument: doc];
    return doc;
}


- (NSArray*)loadNumbers:(NSInteger)num {
    NSMutableArray* numbers = [NSMutableArray array];
    NSError *batchError;
    BOOL ok = [self.db inBatch: &batchError usingBlock: ^{
        for (NSInteger i = 1; i <= num; i++) {
            CBLMutableDocument* doc = [self createDocNumbered: i of: num];
            [numbers addObject: [doc toDictionary]];
        }
    }];
    Assert(ok, @"Error when inserting documents: %@", batchError);
    return numbers;
}


- (void) runTestWithNumbers: (NSArray*)numbers cases: (NSArray*)cases {
    for (NSArray* c in cases) {
        CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                         from: [CBLQueryDataSource database: self.db]
                                        where: c[0]];
        NSPredicate* p = [NSPredicate predicateWithFormat: c[1]];
        NSMutableArray* result = [[numbers filteredArrayUsingPredicate: p] mutableCopy];
        uint64_t total = result.count;
        uint64_t rows = [self verifyQuery: q randomAccess: NO
                                     test: ^(uint64_t n, CBLQueryResult *r)
        {
            CBLDocument* doc = [self.db documentWithID: [r valueAtIndex: 0]];
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
    
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID, kSEQUENCE]
                                     from: [CBLQueryDataSource database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test:^(uint64_t n, CBLQueryResult *r)
    {
        NSString* docID = [r valueAtIndex: 0];
        NSString* expectedID = [NSString stringWithFormat: @"doc-%03llu", n];
        AssertEqualObjects(docID, expectedID);
        
        NSUInteger seq = [[r valueAtIndex: 1] unsignedIntegerValue];
        AssertEqual(seq, n);
        
        CBLDocument* doc = [self.db documentWithID: docID];
        AssertEqualObjects(doc.id, expectedID);
        AssertEqual(doc.sequence, n);
    }];
    AssertEqual(numRows, 100llu);
}


- (void) testWhereComparison {
    CBLQueryExpression* n1 = [CBLQueryExpression property: @"number1"];
    NSArray* cases = @[
        @[[n1 lessThan: [CBLQueryExpression integer: 3]], @"number1 < 3"],
        @[[n1 lessThanOrEqualTo: [CBLQueryExpression integer: 3]], @"number1 <= 3"],
        @[[n1 greaterThan: [CBLQueryExpression integer: 6]], @"number1 > 6"],
        @[[n1 greaterThanOrEqualTo: [CBLQueryExpression integer: 6]], @"number1 >= 6"],
        @[[n1 equalTo: [CBLQueryExpression integer: 7]], @"number1 == 7"],
    ];
    NSArray* numbers = [self loadNumbers: 10];
    [self runTestWithNumbers: numbers cases: cases];
}


- (void) testWhereArithmetic {
    CBLQueryExpression* n1 = [CBLQueryExpression property: @"number1"];
    CBLQueryExpression* n2 = [CBLQueryExpression property: @"number2"];
    NSArray* cases = @[
        @[[[n1 multiply: [CBLQueryExpression integer: 2]] greaterThan: [CBLQueryExpression integer: 8]], @"(number1 * 2) > 8"],
        @[[[n1 divide: [CBLQueryExpression integer: 2]] greaterThan: [CBLQueryExpression integer: 3]], @"(number1 / 2) > 3"],
        @[[[n1 modulo: [CBLQueryExpression integer: 2]] equalTo: [CBLQueryExpression integer: 0]], @"modulus:by:(number1, 2) == 0"],
        @[[[n1 add: [CBLQueryExpression integer: 5]] greaterThan: [CBLQueryExpression integer: 10]], @"(number1 + 5) > 10"],
        @[[[n1 subtract: [CBLQueryExpression integer: 5]] greaterThan: [CBLQueryExpression integer: 0]], @"(number1 - 5) > 0"],
        @[[[n1 multiply: n2] greaterThan: [CBLQueryExpression integer: 10]], @"(number1 * number2) > 10"],
        @[[[n2 divide: n1] greaterThan: [CBLQueryExpression integer: 3]], @"(number2 / number1) > 3"],
        @[[[n2 modulo: n1] equalTo: [CBLQueryExpression integer: 0]], @"modulus:by:(number2, number1) == 0"],
        @[[[n1 add: n2] equalTo: [CBLQueryExpression integer: 10]], @"(number1 + number2) == 10"],
        @[[[n1 subtract: n2] greaterThan: [CBLQueryExpression integer: 0]], @"(number1 - number2) > 0"]
    ];
    NSArray* numbers = [self loadNumbers: 10];
    [self runTestWithNumbers: numbers cases: cases];
}


- (void) testWhereAndOr {
    CBLQueryExpression* n1 = [CBLQueryExpression property: @"number1"];
    CBLQueryExpression* n2 = [CBLQueryExpression property: @"number2"];
    NSArray* cases = @[
        @[[[n1 greaterThan: [CBLQueryExpression integer: 3]] andExpression: [n2 greaterThan: [CBLQueryExpression integer: 3]]], @"number1 > 3 AND number2 > 3"],
        @[[[n1 lessThan: [CBLQueryExpression integer: 3]] orExpression: [n2 lessThan: [CBLQueryExpression integer: 3]]], @"number1 < 3 OR number2 < 3"]
    ];
    NSArray* numbers = [self loadNumbers: 10];
    [self runTestWithNumbers: numbers cases: cases];
}


- (void) testWhereNullOrMissing {
    // https://github.com/couchbase/couchbase-lite-ios/issues/1670
    CBLMutableDocument* doc1 = [self createDocument: @"doc1"];
    [doc1 setValue: @"Scott" forKey: @"name"];
    [doc1 setValue: nil forKey: @"address"];
    [self saveDocument: doc1];
    
    CBLMutableDocument* doc2 = [self createDocument: @"doc2"];
    [doc2 setValue: @"Scott" forKey: @"name"];
    [doc2 setValue: @"123 1st ave." forKey: @"address"];
    [doc2 setValue: @(20) forKey: @"age"];
    [self saveDocument: doc2];
    
    CBLQueryExpression* name = [CBLQueryExpression property: @"name"];
    CBLQueryExpression* address = [CBLQueryExpression property: @"address"];
    CBLQueryExpression* age = [CBLQueryExpression property: @"age"];
    CBLQueryExpression* work = [CBLQueryExpression property: @"work"];
    
    NSArray* tests = @[
       @[[name isNullOrMissing],     @[]],
       @[[name notNullOrMissing],    @[doc1, doc2]],
       @[[address isNullOrMissing],  @[doc1]],
       @[[address notNullOrMissing], @[doc2]],
       @[[age isNullOrMissing],      @[doc1]],
       @[[age notNullOrMissing],     @[doc2]],
       @[[work isNullOrMissing],     @[doc1, doc2]],
       @[[work notNullOrMissing],    @[]],
    ];
    
    for (NSArray* test in tests) {
        CBLQueryExpression* exp = test[0];
        NSArray* expectedDocs = test[1];
        CBLQuery *q = [CBLQueryBuilder select: @[kDOCID]
                                         from: [CBLQueryDataSource database: self.db]
                                        where: exp];
        uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                        test: ^(uint64_t n, CBLQueryResult* r)
        {
            if (expectedDocs.count <= n) {
                NSString* documentID = [r valueAtIndex: 0];
                CBLMutableDocument* expDoc = expectedDocs[(NSUInteger)(n-1)];
                AssertEqualObjects(expDoc.id, documentID, @"Failed case: %@", exp);
            }
        }];
        AssertEqual((int)numRows, (int)expectedDocs.count, @"Failed case: %@", exp);
    }
}


- (void) testWhereIs {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] init];
    [doc1 setValue: @"string" forKey: @"string"];
    Assert([_db saveDocument: doc1 error: &error], @"Error when creating a document: %@", error);
    
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [[CBLQueryExpression property: @"string"] is: [CBLQueryExpression string: @"string"]]];
    
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
                        {
                            CBLDocument* doc = [self.db documentWithID: [r valueAtIndex: 0]];
                            AssertEqualObjects(doc.id, doc1.id);
                            AssertEqualObjects([doc valueForKey: @"string"], @"string");
                        }];
    AssertEqual(numRows, 1u);
    
    q = [CBLQueryBuilder select: @[kDOCID]
                           from: [CBLQueryDataSource database: self.db]
                          where: [[CBLQueryExpression property: @"string"] isNot: [CBLQueryExpression string: @"string1"]]];
    
    Assert(q);
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
               {
                   CBLDocument* doc = [self.db documentWithID: [r valueAtIndex: 0]];
                   AssertEqualObjects(doc.id, doc1.id);
                   AssertEqualObjects([doc valueForKey: @"string"], @"string");
               }];
    AssertEqual(numRows, 1u);
}


- (void) testWhereBetween {
    CBLQueryExpression* n1 = [CBLQueryExpression property: @"number1"];
    NSArray* cases = @[
        @[[n1 between: [CBLQueryExpression integer: 3] and: [CBLQueryExpression integer: 7]], @"number1 BETWEEN {3,7}"]
    ];
    NSArray* numbers = [self loadNumbers: 10];
    [self runTestWithNumbers: numbers cases: cases];
}


- (void) testWhereIn {
    [self loadJSONResource: @"names_100"];
    
    NSArray* expected = @[@"Marcy", @"Margaretta", @"Margrett", @"Marlen", @"Maryjo"];
    NSArray* names = @[[CBLQueryExpression string: @"Marcy"],
                       [CBLQueryExpression string: @"Margaretta"],
                       [CBLQueryExpression string: @"Margrett"],
                       [CBLQueryExpression string: @"Marlen"],
                       [CBLQueryExpression string: @"Maryjo"]];
    CBLQueryExpression* firstName = [CBLQueryExpression property: @"name.first"];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [firstName in: names]
                                  orderBy: @[[CBLQuerySortOrder property: @"name.first"]]];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test:^(uint64_t n, CBLQueryResult* r)
    {
        CBLDocument* doc = [self.db documentWithID: [r valueAtIndex: 0]];
        NSString* first = [[doc valueForKey: @"name"] valueForKey: @"first"];
        AssertEqualObjects(first, expected[(NSUInteger)(n-1)]);
    }];
    AssertEqual((int)numRows, (int)expected.count);
}


- (void) testWhereLike {
    [self loadJSONResource: @"names_100"];
    
    CBLQueryExpression* where = [[CBLQueryExpression property: @"name.first"] like: [CBLQueryExpression string: @"%Mar%"]];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: where
                                  orderBy: @[[[CBLQueryOrdering property: @"name.first"] ascending]]];
    
    NSMutableArray* firstNames = [NSMutableArray array];
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test:^(uint64_t n, CBLQueryResult* r) {
        CBLDocument* doc = [self.db documentWithID: [r valueAtIndex: 0]];
        NSString* firstName = [[doc valueForKey:@"name"] valueForKey: @"first"];
        if (firstName)
            [firstNames addObject: firstName];
    }];
    AssertEqual(numRows, 5u);
    AssertEqual(firstNames.count, 5u);
}


- (void) testWhereRegex {
    [self loadJSONResource: @"names_100"];
    
    CBLQueryExpression* where = [[CBLQueryExpression property: @"name.first"] regex: [CBLQueryExpression string: @"^Mar.*"]];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: where
                                  orderBy: @[[[CBLQueryOrdering property: @"name.first"] ascending]]];
    
    NSMutableArray* firstNames = [NSMutableArray array];
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test:^(uint64_t n, CBLQueryResult* r)
    {
        CBLDocument* doc = [self.db documentWithID: [r valueAtIndex: 0]];
        NSString* firstName = [[doc valueForKey:@"name"] valueForKey: @"first"];
        if (firstName)
            [firstNames addObject: firstName];
    }];
    AssertEqual(numRows, 5u);
    AssertEqual(firstNames.count, 5u);
}


- (void) testWhereMatch {
    [self loadJSONResource: @"sentences"];
    
    CBLQueryFullTextExpression* SENTENCE = [CBLQueryFullTextExpression indexWithName: @"sentence"];
    CBLQuerySelectResult* S_SENTENCE = [CBLQuerySelectResult property: @"sentence"];
    
    NSError* error;
    CBLFullTextIndex* index = [CBLIndexBuilder fullTextIndexWithItems: @[[CBLFullTextIndexItem property: @"sentence"]]];
    Assert([self.db createIndex: index withName: @"sentence" error: &error],
           @"Error when creating the index: %@", error);
    
    
    CBLQueryExpression* where = [SENTENCE match: @"'Dummie woman'"];
    CBLQueryOrdering* order = [[CBLQueryOrdering expression: [CBLQueryFullTextFunction rank: @"sentence"]]
                               descending];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID, S_SENTENCE]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: where
                                  orderBy: @[order]];
    uint64_t numRows = [self verifyQuery: q  randomAccess: YES
                                    test:^(uint64_t n, CBLQueryResult* r)
    {
        // AssertNotNil([r stringAtIndex:0]);
        // AssertNotNil([r stringAtIndex:1]);
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
        
        CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                         from: [CBLQueryDataSource database: self.db]
                                        where: nil
                                      orderBy: @[order]];
        Assert(q);
        
        NSMutableArray* firstNames = [NSMutableArray array];
        uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                        test: ^(uint64_t n, CBLQueryResult* r)
        {
            CBLDocument* doc = [self.db documentWithID: [r valueAtIndex: 0]];
            NSString* firstName = [[doc valueForKey:@"name"] valueForKey: @"first"];
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


- (void) testSelectDistinct {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] init];
    [doc1 setValue: @(20) forKey: @"number"];
    Assert([_db saveDocument: doc1 error: &error], @"Error when creating a document: %@", error);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] init];
    [doc2 setValue: @(20) forKey: @"number"];
    Assert([_db saveDocument: doc2 error: &error], @"Error when creating a document: %@", error);
    
    CBLQueryExpression* NUMBER  = [CBLQueryExpression property: @"number"];
    CBLQuerySelectResult* S_NUMBER = [CBLQuerySelectResult expression: NUMBER];
    
    CBLQuery* q = [CBLQueryBuilder selectDistinct: @[S_NUMBER]
                                             from: [CBLQueryDataSource database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqual([r integerAtIndex: 0], 20);
    }];
    AssertEqual(numRows, 1u);
}


- (void) testJoin {
    [self loadNumbers: 100];
    
    CBLMutableDocument* joinme = [[CBLMutableDocument alloc] initWithID: @"joinme"];
    [joinme setValue: @42 forKey: @"theone"];
    [self saveDocument: joinme];
    
    CBLQuerySelectResult* MAIN_DOC_ID =
        [CBLQuerySelectResult expression: [CBLQueryMeta idFrom: @"main"]];
    
    CBLQueryExpression* on = [[CBLQueryExpression property: @"number1" from: @"main"]
                              equalTo: [CBLQueryExpression property:@"theone" from:@"secondary"]];
    CBLQueryJoin* join = [CBLQueryJoin join: [CBLQueryDataSource database: self.db as: @"secondary"]
                                         on: on];
    CBLQuery* q = [CBLQueryBuilder select: @[MAIN_DOC_ID]
                                     from: [CBLQueryDataSource database: self.db as: @"main"]
                                     join: @[join]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
    {
        CBLDocument* doc = [self.db documentWithID: [r valueAtIndex: 0]];
        AssertEqual([doc integerForKey:@"number1"], 42);
    }];
    AssertEqual(numRows, 1u);
}

- (void) testLeftJoin {
    [self loadNumbers: 100];
    
    CBLMutableDocument* joinme = [[CBLMutableDocument alloc] initWithID: @"joinme"];
    [joinme setValue: @42 forKey: @"theone"];
    [self saveDocument: joinme];
    
    CBLQueryExpression* on = [[CBLQueryExpression property: @"number1" from: @"main"]
                              equalTo: [CBLQueryExpression property:@"theone" from:@"secondary"]];
    
    CBLQueryJoin* join = [CBLQueryJoin leftJoin: [CBLQueryDataSource database: self.db as: @"secondary"]
                                         on: on];
    
    CBLQueryExpression* NUMBER1  = [CBLQueryExpression property: @"number2" from:@"main"];
    CBLQueryExpression* NUMBER2  = [CBLQueryExpression property: @"theone" from:@"secondary"];
    
    NSArray* results = @[[CBLQuerySelectResult expression: NUMBER1],
                         [CBLQuerySelectResult expression: NUMBER2]];
    
    CBLQuery* q = [CBLQueryBuilder select: results
                                     from: [CBLQueryDataSource database: self.db as: @"main"]
                                     join: @[join]];
    Assert(q);
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
    {
        if ([r integerAtIndex: 1] == 42) {
            AssertEqual ([r integerAtIndex: 0], 58);
            AssertEqual ([r integerAtIndex: 1], 42);
        } else {
            AssertNil ([r valueAtIndex: 1]);
        }
    }];
    
    AssertEqual(numRows, 101u);
}


// https://github.com/couchbase/couchbase-lite-core/issues/497
- (void) testLeftJoinWithSelectAll {
    [self loadNumbers: 100];
    
    CBLMutableDocument* joinme = [[CBLMutableDocument alloc] initWithID: @"joinme"];
    [joinme setValue: @42 forKey: @"theone"];
    [self saveDocument: joinme];
    
    CBLQueryExpression* on = [[CBLQueryExpression property: @"number1" from: @"main"]
                              equalTo: [CBLQueryExpression property:@"theone" from:@"secondary"]];
    
    CBLQueryJoin* join = [CBLQueryJoin leftJoin: [CBLQueryDataSource database: self.db as: @"secondary"]
                                             on: on];
    
    NSArray* results = @[[CBLQuerySelectResult allFrom: @"main"],
                         [CBLQuerySelectResult allFrom: @"secondary"]];
    
    CBLQuery* q = [CBLQueryBuilder select: results
                                     from: [CBLQueryDataSource database: self.db as: @"main"]
                                     join: @[join]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
    {
        CBLDictionary* main = [r dictionaryAtIndex: 0];
        CBLDictionary* secondary = [r dictionaryAtIndex: 1];
        
        NSInteger number1 = [main integerForKey: @"number1"];
        if (number1 == 42) {
            AssertNotNil(secondary);
            AssertEqual ([secondary integerForKey: @"theone"], number1);
        } else {
            AssertNil(secondary);
        }
    }];
    AssertEqual(numRows, 101u);
}


- (void) testCrossJoin {
    [self loadNumbers: 10];
    
    CBLQueryJoin* join = [CBLQueryJoin crossJoin: [CBLQueryDataSource database: self.db as: @"secondary"]];
    
    CBLQueryExpression* NUMBER1  = [CBLQueryExpression property: @"number1" from:@"main"];
    CBLQueryExpression* NUMBER2  = [CBLQueryExpression property: @"number2" from:@"secondary"];
    
    NSArray* results = @[[CBLQuerySelectResult expression: NUMBER1],
                         [CBLQuerySelectResult expression: NUMBER2]];
    
    
    
    CBLQuery* q = [CBLQueryBuilder select: results
                                     from: [CBLQueryDataSource database: self.db as: @"main"]
                                     join: @[join]];
    Assert(q);
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSInteger num1 = [r integerAtIndex:0];
        NSInteger num2 = [r integerAtIndex:1];
        AssertEqual ((num1 - 1) % 10,(long)(n - 1)/10 );
        AssertEqual ((10 - num2) % 10,(long)n % 10 );
        
    }];
    
    AssertEqual(numRows, 100u);
}


- (void) testCrossJoin2 {
    [self loadJSONResource:@"join"];
    CBLQueryExpression* FIRSTNAME  = [CBLQueryExpression property: @"firstname" from:@"employeeDS"];
    CBLQueryExpression* LASTNAME  = [CBLQueryExpression property: @"lastname" from:@"employeeDS"];
    CBLQueryExpression* DEPTNAME  = [CBLQueryExpression property: @"name" from:@"departmentDS"];

    NSArray* results = @[[CBLQuerySelectResult expression: FIRSTNAME],
                         [CBLQuerySelectResult expression: LASTNAME],
                         [CBLQuerySelectResult expression: DEPTNAME]];


    [CBLQuerySelectResult expression: [CBLQueryMeta idFrom: @"employeeDS"]];


    CBLQueryExpression* expr1 = [[CBLQueryExpression property:@"type" from:@"employeeDS"]  equalTo: [CBLQueryExpression string:@"employee"]];
    CBLQueryExpression* expr2 = [[CBLQueryExpression property:@"type" from:@"departmentDS"] equalTo :[CBLQueryExpression string:@"department"]];

    CBLQueryJoin* join = [CBLQueryJoin crossJoin:[CBLQueryDataSource database: self.db as: @"departmentDS"]];
    CBLQuery* q = [CBLQueryBuilder select: results
                                     from: [CBLQueryDataSource database: self.db as: @"employeeDS"]
                                     join: @[join]
                                    where:[expr1 andExpression:expr2]];


    Assert(q);
    NSError* error;

    NSLog(@"%@",[q explain:nil]);

    CBLQueryResultSet* rs = [q execute: &error];

    NSUInteger i = 0;
    NSArray* res = [rs allResults];
    for (CBLQueryResult* r in res) {
        NSLog(@" %@",[r toDictionary]);

        i++;
    }

}
- (void) testGroupBy {
    NSArray* expectedStates  = @[@"AL",    @"CA",    @"CO",    @"FL",    @"IA"];
    NSArray* expectedCounts  = @[@1,       @6,       @1,       @1,       @3];
    NSArray* expectedMaxZips = @[@"35243", @"94153", @"81223", @"33612", @"50801"];
    
    [self loadJSONResource: @"names_100"];
    
    CBLQueryExpression* STATE  = [CBLQueryExpression property: @"contact.address.state"];
    CBLQueryExpression* COUNT  = [CBLQueryFunction count: [CBLQueryExpression integer: 1]];
    CBLQueryExpression* ZIP    = [CBLQueryExpression property: @"contact.address.zip"];
    CBLQueryExpression* MAXZIP = [CBLQueryFunction max: ZIP];
    CBLQueryExpression* GENDER = [CBLQueryExpression property: @"gender"];
    
    NSArray* results = @[[CBLQuerySelectResult expression: STATE],
                         [CBLQuerySelectResult expression: COUNT],
                         [CBLQuerySelectResult expression: MAXZIP]];
    
    CBLQuery* q = [CBLQueryBuilder select: results
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [GENDER equalTo: [CBLQueryExpression string: @"female"]]
                                  groupBy: @[STATE]
                                   having: nil
                                  orderBy: @[[CBLQueryOrdering expression: STATE]]
                                    limit: nil];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSString* state = [r valueAtIndex: 0];
        NSInteger count = [[r valueAtIndex: 1] integerValue];
        NSString* maxZip = [r valueAtIndex: 2];
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
    
    q = [CBLQueryBuilder select: results
                           from: [CBLQueryDataSource database: self.db]
                          where: [GENDER equalTo: [CBLQueryExpression string: @"female"]]
                        groupBy: @[STATE]
                         having: [COUNT greaterThan: [CBLQueryExpression integer: 1]]
                        orderBy: @[[CBLQueryOrdering expression: STATE]]
                          limit: nil];
    
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r) {
        NSString* state = [r valueAtIndex: 0];
        NSInteger count = [[r valueAtIndex: 1] integerValue];
        NSString* maxZip = [r valueAtIndex: 2];
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
    
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: NUMBER1]]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [NUMBER1 between: PARAM_N1 and: PARAM_N2]
                                  orderBy: @[[CBLQueryOrdering expression: NUMBER1]]];
    
    CBLQueryParameters* params = [[CBLQueryParameters alloc] init];
    [params setValue: @(2) forName: @"num1"];
    [params setValue: @(5) forName: @"num2"];
    
    q.parameters = params;
    
    NSArray* expectedNumbers = @[@2, @3, @4, @5];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r) {
        NSInteger number = [[r valueAtIndex: 0] integerValue];
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 4u);
}


- (void) testMeta {
    [self loadNumbers: 5];
    
    CBLQueryExpression* DOC_ID  = [CBLQueryMeta id];
    CBLQueryExpression* DOC_SEQ = [CBLQueryMeta sequence];
    CBLQueryExpression* NUMBER1  = [CBLQueryExpression property: @"number1"];
    
    CBLQuerySelectResult* S_DOC_ID = [CBLQuerySelectResult expression: DOC_ID];
    CBLQuerySelectResult* S_DOC_SEQ = [CBLQuerySelectResult expression: DOC_SEQ];
    CBLQuerySelectResult* S_NUMBER1 = [CBLQuerySelectResult expression: NUMBER1];
    
    CBLQuery* q = [CBLQueryBuilder select: @[S_DOC_ID, S_DOC_SEQ, S_NUMBER1]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: nil
                                  orderBy: @[[CBLQueryOrdering expression: DOC_SEQ]]];
    
    NSArray* expectedDocIDs  = @[@"doc1", @"doc2", @"doc3", @"doc4", @"doc5"];
    NSArray* expectedSeqs    = @[@1, @2, @3, @4, @5];
    NSArray* expectedNumbers = @[@1, @2, @3, @4, @5];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r) {
        NSString* id1 = [r stringAtIndex: 0];
        NSString* id2 = [r stringForKey: @"id"];
        
        NSInteger sequence1 = [r integerAtIndex: 1];
        NSInteger sequence2 = [r integerForKey: @"sequence"];
        
        NSInteger number = [[r valueAtIndex: 2] integerValue];
        
        AssertEqualObjects(id1,  id2);
        AssertEqualObjects(id1,  expectedDocIDs[(NSUInteger)(n-1)]);
        
        AssertEqual(sequence1, sequence2);
        AssertEqual(sequence1, [expectedSeqs[(NSUInteger)(n-1)] integerValue]);
        
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 5u);
}


- (void) testLimit {
    [self loadNumbers: 10];
    
    CBLQueryExpression* NUMBER1  = [CBLQueryExpression property: @"number1"];
    
    CBLQuery* q= [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: NUMBER1]]
                                    from: [CBLQueryDataSource database: self.db]
                                   where: nil groupBy: nil having: nil
                                 orderBy: @[[CBLQueryOrdering expression: NUMBER1]]
                                   limit: [CBLQueryLimit limit: [CBLQueryExpression integer: 5]]];
    
    NSArray* expectedNumbers = @[@1, @2, @3, @4, @5];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSInteger number = [[r valueAtIndex: 0] integerValue];
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 5u);
    
    q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: NUMBER1]]
                           from: [CBLQueryDataSource database: self.db]
                          where: nil groupBy: nil having: nil
                        orderBy: @[[CBLQueryOrdering expression: NUMBER1]]
                          limit: [CBLQueryLimit limit: [CBLQueryExpression parameterNamed: @"LIMIT_NUM"]]];
    
    CBLQueryParameters* params = [[CBLQueryParameters alloc] init];
    [params setValue: @3 forName: @"LIMIT_NUM"];
    q.parameters = params;
    
    expectedNumbers = @[@1, @2, @3];
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSInteger number = [[r valueAtIndex: 0] integerValue];
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 3u);
}


- (void) testLimitOffset {
    [self loadNumbers: 10];
    
    CBLQueryExpression* NUMBER1  = [CBLQueryExpression property: @"number1"];
    
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: NUMBER1]]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: nil groupBy: nil having: nil
                                  orderBy: @[[CBLQueryOrdering expression: NUMBER1]]
                                    limit: [CBLQueryLimit limit: [CBLQueryExpression integer: 5]
                                                         offset: [CBLQueryExpression integer: 3]]];
    
    NSArray* expectedNumbers = @[@4, @5, @6, @7, @8];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSInteger number = [[r valueAtIndex: 0] integerValue];
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 5u);
    
    q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: NUMBER1]]
                           from: [CBLQueryDataSource database: self.db]
                          where: nil groupBy: nil having: nil
                        orderBy: @[[CBLQueryOrdering expression: NUMBER1]]
                          limit: [CBLQueryLimit limit: [CBLQueryExpression parameterNamed: @"LIMIT_NUM"]
                                               offset: [CBLQueryExpression parameterNamed:@"OFFSET_NUM"]]];
    
    CBLQueryParameters* params = [[CBLQueryParameters alloc] init];
    [params setValue: @3 forName: @"LIMIT_NUM"];
    [params setValue: @5 forName: @"OFFSET_NUM"];
    q.parameters = params;
    
    expectedNumbers = @[@6, @7, @8];
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        NSInteger number = [[r valueAtIndex: 0] integerValue];
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
    
    CBLQuerySelectResult* S_FNAME = [CBLQuerySelectResult expression: FNAME as: @"firstname"];
    CBLQuerySelectResult* S_LNAME = [CBLQuerySelectResult expression: LNAME as: @"lastname"];
    CBLQuerySelectResult* S_GENDER = [CBLQuerySelectResult expression: GENDER];
    CBLQuerySelectResult* S_CITY = [CBLQuerySelectResult expression: CITY];
    
    CBLQuery* q = [CBLQueryBuilder select: @[S_FNAME, S_LNAME, S_GENDER, S_CITY]
                                     from: [CBLQueryDataSource database: self.db]];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqual(r.count, 4u);
        AssertEqualObjects([r valueForKey: @"firstname"], [r valueAtIndex: 0]);
        AssertEqualObjects([r valueForKey: @"lastname"], [r valueAtIndex: 1]);
        AssertEqualObjects([r valueForKey: @"gender"], [r valueAtIndex: 2]);
        AssertEqualObjects([r valueForKey: @"city"], [r valueAtIndex: 3]);
    }];
    AssertEqual((int)numRows, 100);
}


- (void) testQueryProjectingKeys {
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
    
    CBLQuery* q = [CBLQueryBuilder select: results
                                     from: [CBLQueryDataSource database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqual(r.count, 5u);
        AssertEqual([r doubleForKey: @"$1"], [r doubleAtIndex: 0]);
        AssertEqual([r integerForKey: @"$2"], [r integerAtIndex: 1]);
        AssertEqual([r integerForKey: @"min"], [r integerAtIndex: 2]);
        AssertEqual([r integerForKey: @"$3"], [r integerAtIndex: 3]);
        AssertEqual([r integerForKey: @"sum"], [r integerAtIndex: 4]);
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
    
    CBLQuery* q = [CBLQueryBuilder select: results
                                     from: [CBLQueryDataSource database: self.db]];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
                        {
                            AssertEqual([[r valueAtIndex:0] doubleValue], 50.5);
                            AssertEqual([[r valueAtIndex:1] integerValue], 100);
                            AssertEqual([[r valueAtIndex:2] integerValue], 1);
                            AssertEqual([[r valueAtIndex:3] integerValue], 100);
                            AssertEqual([[r valueAtIndex:4] integerValue], 5050);
                        }];
    AssertEqual(numRows, 1u);
}


- (void) testArrayFunctions {
    CBLMutableDocument* doc = [self createDocument:@"doc1"];
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [array addValue: @"650-123-0001"];
    [array addValue: @"650-123-0002"];
    [doc setValue: array forKey: @"array"];
    [self saveDocument: doc];
    
    CBLQueryExpression* ARRAY_LENGTH = [CBLQueryArrayFunction length:
                                        [CBLQueryExpression property: @"array"]];
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: ARRAY_LENGTH]]
                                     from: [CBLQueryDataSource database: self.db]];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
                        {
                            AssertEqual([r integerAtIndex: 0], 2);
                        }];
    AssertEqual(numRows, 1u);
    
    CBLQueryExpression* ARRAY_CONTAINS1 = [CBLQueryArrayFunction contains: [CBLQueryExpression property: @"array"]
                                                                    value: [CBLQueryExpression string: @"650-123-0001"]];
    CBLQueryExpression* ARRAY_CONTAINS2 = [CBLQueryArrayFunction contains: [CBLQueryExpression property: @"array"]
                                                                    value: [CBLQueryExpression string: @"650-123-0003"]];
    q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: ARRAY_CONTAINS1],
                                   [CBLQuerySelectResult expression: ARRAY_CONTAINS2]]
                           from: [CBLQueryDataSource database: self.db]];
    
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
               {
                   AssertEqual([r booleanAtIndex: 0], YES);
                   AssertEqual([r booleanAtIndex: 1], NO);
               }];
    AssertEqual(numRows, 1u);
}


- (void) testMathFunctions {
    double num = 0.6;
    CBLMutableDocument* doc = [self createDocument:@"doc1"];
    [doc setValue: @(num) forKey: @"number"];
    [self saveDocument: doc];
    
    NSArray* expectedValues = @[@(0.6),
                                @(acos(num)),
                                @(asin(num)),
                                @(atan(num)),
                                @(atan2(90.0, num)),
                                @(ceil(num)),
                                @(cos(num)),
                                @(num * 180.0 / M_PI),
                                @(exp(num)),
                                @(floor(num)),
                                @(log(num)),
                                @(log10(num)),
                                @(pow(num, 2)),
                                @(num * M_PI / 180.0),
                                @(round(num)),
                                @(round(num * 10.0) / 10.0),
                                @(1),
                                @(sin(num)),
                                @(sqrt(num)),
                                @(tan(num)),
                                @(trunc(num)),
                                @(trunc(num * 10.0) / 10.0)];
    
    CBLQueryExpression* p = [CBLQueryExpression property: @"number"];
    NSArray* functions = @[[CBLQueryFunction abs: p],
                           [CBLQueryFunction acos: p],
                           [CBLQueryFunction asin: p],
                           [CBLQueryFunction atan: p],
                           [CBLQueryFunction atan2: p y: [CBLQueryExpression integer: 90]],
                           [CBLQueryFunction ceil: p],
                           [CBLQueryFunction cos: p],
                           [CBLQueryFunction degrees: p],
                           [CBLQueryFunction exp: p],
                           [CBLQueryFunction floor: p],
                           [CBLQueryFunction ln: p],
                           [CBLQueryFunction log: p],
                           [CBLQueryFunction power: p exponent: [CBLQueryExpression integer: 2]],
                           [CBLQueryFunction radians: p],
                           [CBLQueryFunction round: p],
                           [CBLQueryFunction round: p digits: [CBLQueryExpression integer: 1]],
                           [CBLQueryFunction sign: p],
                           [CBLQueryFunction sin: p],
                           [CBLQueryFunction sqrt: p],
                           [CBLQueryFunction tan: p],
                           [CBLQueryFunction trunc: p],
                           [CBLQueryFunction trunc: p digits: [CBLQueryExpression integer: 1]]];
    
    int index = 0;
    for (CBLQueryExpression *f in functions) {
        CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: f]]
                                         from: [CBLQueryDataSource database: self.db]];
        
        uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
                            {
                                double expected = [expectedValues[index] doubleValue];
                                AssertEqual([r doubleAtIndex: 0], expected);
                            }];
        AssertEqual(numRows, 1u);
        index++;
    }
}


- (void) testStringFunctions {
    NSString* str = @"  See you 18r  ";
    CBLMutableDocument* doc = [self createDocument:@"doc1"];
    [doc setValue: str forKey: @"greeting"];
    [self saveDocument: doc];
    
    CBLQueryExpression* p = [CBLQueryExpression property: @"greeting"];
    
    // Contains:
    CBLQueryExpression* CONTAINS1 = [CBLQueryFunction contains: p substring: [CBLQueryExpression string: @"8"]];
    CBLQueryExpression* CONTAINS2 = [CBLQueryFunction contains: p substring: [CBLQueryExpression string: @"9"]];
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: CONTAINS1],
                                             [CBLQuerySelectResult expression: CONTAINS2]]
                                     from: [CBLQueryDataSource database: self.db]];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
                        {
                            AssertEqual([r booleanAtIndex: 0], YES);
                            AssertEqual([r booleanAtIndex: 1], NO);
                        }];
    AssertEqual(numRows, 1u);
    
    // Length:
    CBLQueryExpression* LENGTH = [CBLQueryFunction length: p];
    q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: LENGTH]]
                           from: [CBLQueryDataSource database: self.db]];
    
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
               {
                   AssertEqual([r integerAtIndex: 0], (NSInteger)str.length);
               }];
    AssertEqual(numRows, 1u);
    
    // Lower, Ltrim, Rtrim, Trim, Upper:
    CBLQueryExpression* LOWER = [CBLQueryFunction lower: p];
    CBLQueryExpression* LTRIM = [CBLQueryFunction ltrim: p];
    CBLQueryExpression* RTRIM = [CBLQueryFunction rtrim: p];
    CBLQueryExpression* TRIM = [CBLQueryFunction trim: p];
    CBLQueryExpression* UPPER = [CBLQueryFunction upper: p];
    
    q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: LOWER],
                                   [CBLQuerySelectResult expression: LTRIM],
                                   [CBLQuerySelectResult expression: RTRIM],
                                   [CBLQuerySelectResult expression: TRIM],
                                   [CBLQuerySelectResult expression: UPPER]]
                           from: [CBLQueryDataSource database: self.db]];
    
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
               {
                   AssertEqualObjects([r stringAtIndex: 0], [str lowercaseString]);
                   AssertEqualObjects([r stringAtIndex: 1], @"See you 18r  ");
                   AssertEqualObjects([r stringAtIndex: 2], @"  See you 18r");
                   AssertEqualObjects([r stringAtIndex: 3], @"See you 18r");
                   AssertEqualObjects([r stringAtIndex: 4], [str uppercaseString]);
               }];
    AssertEqual(numRows, 1u);
}


- (void) testQuantifiedOperators {
    [self loadJSONResource: @"names_100"];
    
    CBLQueryExpression* DOC_ID = [CBLQueryMeta id];
    CBLQuerySelectResult* S_DOC_ID = [CBLQuerySelectResult expression: DOC_ID];
    
    CBLQueryExpression* LIKES  = [CBLQueryExpression property: @"likes"];
    CBLQueryVariableExpression* LIKE = [CBLQueryArrayExpression variableWithName: @"LIKE"];
    
    // ANY:
    CBLQuery* q = [CBLQueryBuilder select: @[S_DOC_ID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [CBLQueryArrayExpression any: LIKE
                                                                     in: LIKES
                                                              satisfies: [LIKE equalTo: [CBLQueryExpression string: @"climbing"]]]];
    
    NSLog(@"%@", [q explain: nil]);
    
    
    NSArray* expected = @[@"doc-017", @"doc-021", @"doc-023", @"doc-045", @"doc-060"];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqualObjects([r stringAtIndex: 0], expected[n-1]);
    }];
    AssertEqual(numRows, expected.count);
    
    // EVERY:
    q = [CBLQueryBuilder select: @[S_DOC_ID]
                           from: [CBLQueryDataSource database: self.db]
                          where: [CBLQueryArrayExpression every: LIKE
                                                             in: LIKES
                                                      satisfies: [LIKE equalTo: [CBLQueryExpression string: @"taxes"]]]];
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        if (n == 1) {
            AssertEqualObjects([r stringAtIndex: 0], @"doc-007");
        }
    }];
    AssertEqual(numRows, 42u);
    
    // ANY AND EVERY
    q = [CBLQueryBuilder select: @[S_DOC_ID]
                           from: [CBLQueryDataSource database: self.db]
                          where: [CBLQueryArrayExpression anyAndEvery: LIKE
                                                                   in: LIKES
                                                            satisfies: [LIKE equalTo: [CBLQueryExpression string: @"taxes"]]]];
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r) { }];
    AssertEqual(numRows, 0u);
}


- (void) testQuantifiedOperatorVariableKeyPath {
    NSArray* data = @[
       @[@{@"city": @"San Francisco"}, @{@"city": @"Palo Alto"}, @{@"city": @"San Jose"}],
       @[@{@"city": @"Mountain View"}, @{@"city": @"Palo Alto"}, @{@"city": @"Belmont"}],
       @[@{@"city": @"San Francisco"}, @{@"city": @"Redwood City"}, @{@"city": @"San Mateo"}]
    ];
    
    // Create documents:
    NSInteger i = 0;
    for (NSArray* cities in data) {
        NSString* docID = [NSString stringWithFormat: @"doc-%ld", (long)i++];
        CBLMutableDocument* doc = [self createDocument: docID];
        [doc setValue: cities forKey: @"paths"];
        
        NSData* d = [NSJSONSerialization dataWithJSONObject: [doc toDictionary] options: 0 error: nil];
        NSString* str = [[NSString alloc] initWithData: d encoding:NSUTF8StringEncoding];
        NSLog(@"%@", str);
        [self saveDocument: doc];
    }
    
    CBLQueryExpression* DOC_ID  = [CBLQueryMeta id];
    CBLQuerySelectResult* S_DOC_ID = [CBLQuerySelectResult expression: DOC_ID];
    
    CBLQueryExpression* PATHS  = [CBLQueryExpression property: @"paths"];
    CBLQueryVariableExpression* PATH  = [CBLQueryArrayExpression variableWithName: @"path"];
    CBLQueryVariableExpression* PATH_CITY  = [CBLQueryArrayExpression variableWithName: @"path.city"];
    CBLQueryExpression* where = [CBLQueryArrayExpression any: PATH
                                                          in: PATHS
                                                   satisfies: [PATH_CITY equalTo: [CBLQueryExpression string: @"San Francisco"]]];
    
    CBLQuery* q = [CBLQueryBuilder select: @[S_DOC_ID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: where];
    
    NSArray* expected = @[@"doc-0", @"doc-2"];
    uint64_t numRows = [self verifyQuery: q randomAccess: NO test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqualObjects([r stringAtIndex: 0], expected[n-1]);
    }];
    AssertEqual(numRows, expected.count);
}


- (void) testSelectAll {
    [self loadNumbers: 100];
    
    CBLQueryExpression* NUMBER1 = [CBLQueryExpression property: @"number1"];
    CBLQuerySelectResult* S_NUMBER1 = [CBLQuerySelectResult expression: NUMBER1];
    CBLQuerySelectResult* S_STAR = [CBLQuerySelectResult all];
    
    CBLQueryExpression* TESTDB_NUMBER1 = [CBLQueryExpression property: @"number1" from: @"testdb"];
    CBLQuerySelectResult* S_TESTDB_NUMBER1 = [CBLQuerySelectResult expression: TESTDB_NUMBER1];
    CBLQuerySelectResult* S_TESTDB_STAR = [CBLQuerySelectResult allFrom: @"testdb"];
    
    // SELECT *
    CBLQuery* q = [CBLQueryBuilder select: @[S_STAR]
                                     from: [CBLQueryDataSource database: self.db]];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqual(r.count, 1u);
        CBLMutableDictionary* a1 = [r valueAtIndex: 0];
        CBLMutableDictionary* a2 = [r valueForKey: self.db.name];
        AssertEqual([a1 integerForKey: @"number1"], (NSInteger)n);
        AssertEqual([a1 integerForKey: @"number2"], (NSInteger)(100 - n));
        AssertEqual([a2 integerForKey: @"number1"], (NSInteger)n);
        AssertEqual([a2 integerForKey: @"number2"], (NSInteger)(100 - n));
    }];
    AssertEqual(numRows, 100u);
    
    // SELECT testdb.*
    q = [CBLQueryBuilder select: @[S_TESTDB_STAR]
                           from: [CBLQueryDataSource database: self.db as: @"testdb"]];
    
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqual(r.count, 1u);
        CBLMutableDictionary* a1 = [r valueAtIndex: 0];
        CBLMutableDictionary* a2 = [r valueForKey: @"testdb"];
        AssertEqual([a1 integerForKey: @"number1"], (NSInteger)n);
        AssertEqual([a1 integerForKey: @"number2"], (NSInteger)(100 - n));
        AssertEqual([a2 integerForKey: @"number1"], (NSInteger)n);
        AssertEqual([a2 integerForKey: @"number2"], (NSInteger)(100 - n));
    }];
    AssertEqual(numRows, 100u);
    
    // SELECT *, number1
    q = [CBLQueryBuilder select: @[S_STAR, S_NUMBER1]
                           from: [CBLQueryDataSource database: self.db]];
    
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqual(r.count, 2u);
        CBLMutableDictionary* a1 = [r valueAtIndex: 0];
        CBLMutableDictionary* a2 = [r valueForKey: self.db.name];
        AssertEqual([a1 integerForKey: @"number1"], (NSInteger)n);
        AssertEqual([a1 integerForKey: @"number2"], (NSInteger)(100 - n));
        AssertEqual([a2 integerForKey: @"number1"], (NSInteger)n);
        AssertEqual([a2 integerForKey: @"number2"], (NSInteger)(100 - n));
        AssertEqual([r integerAtIndex: 1], (NSInteger)n);
        AssertEqual([r integerForKey: @"number1"], (NSInteger)n);
    }];
    AssertEqual(numRows, 100u);
    
    // SELECT testdb.*, testdb.number1
    q = [CBLQueryBuilder select: @[S_TESTDB_STAR, S_TESTDB_NUMBER1]
                           from: [CBLQueryDataSource database: self.db as: @"testdb"]];
    
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqual(r.count, 2u);
        CBLMutableDictionary* a1 = [r valueAtIndex: 0];
        CBLMutableDictionary* a2 = [r valueForKey: @"testdb"];
        AssertEqual([a1 integerForKey: @"number1"], (NSInteger)n);
        AssertEqual([a1 integerForKey: @"number2"], (NSInteger)(100 - n));
        AssertEqual([a2 integerForKey: @"number1"], (NSInteger)n);
        AssertEqual([a2 integerForKey: @"number2"], (NSInteger)(100 - n));
        AssertEqual([r integerAtIndex: 1], (NSInteger)n);
        AssertEqual([r integerForKey: @"number1"], (NSInteger)n);
    }];
    AssertEqual(numRows, 100u);
}


- (void) testGenerateJSONCollation {
    NSArray* collations =
        @[[CBLQueryCollation asciiWithIgnoreCase: NO],
          [CBLQueryCollation asciiWithIgnoreCase: YES],
          [CBLQueryCollation unicodeWithLocale: nil   ignoreCase: NO  ignoreAccents: NO],
          [CBLQueryCollation unicodeWithLocale: nil   ignoreCase: YES ignoreAccents: NO],
          [CBLQueryCollation unicodeWithLocale: nil   ignoreCase: YES ignoreAccents: YES],
          [CBLQueryCollation unicodeWithLocale: @"en" ignoreCase: NO  ignoreAccents: NO],
          [CBLQueryCollation unicodeWithLocale: @"en" ignoreCase: YES ignoreAccents: NO],
          [CBLQueryCollation unicodeWithLocale: @"en" ignoreCase: YES ignoreAccents: YES]];
    
    NSString* deviceLocale = [NSLocale currentLocale].localeIdentifier;
    NSArray* expected =
        @[
          @{@"UNICODE": @(NO),  @"LOCALE": [NSNull null] ,@"CASE": @(YES), @"DIAC": @(YES)},
          @{@"UNICODE": @(NO),  @"LOCALE": [NSNull null] ,@"CASE": @(NO) , @"DIAC": @(YES)},
          @{@"UNICODE": @(YES), @"LOCALE": deviceLocale  ,@"CASE": @(YES), @"DIAC": @(YES)},
          @{@"UNICODE": @(YES), @"LOCALE": deviceLocale  ,@"CASE": @(NO),  @"DIAC": @(YES)},
          @{@"UNICODE": @(YES), @"LOCALE": deviceLocale  ,@"CASE": @(NO),  @"DIAC": @(NO)},
          @{@"UNICODE": @(YES), @"LOCALE": @"en"         ,@"CASE": @(YES), @"DIAC": @(YES)},
          @{@"UNICODE": @(YES), @"LOCALE": @"en"         ,@"CASE": @(NO),  @"DIAC": @(YES)},
          @{@"UNICODE": @(YES), @"LOCALE": @"en"         ,@"CASE": @(NO),  @"DIAC": @(NO)}
          ];
    
    NSInteger i = 0;
    for (CBLQueryCollation* c in collations) {
        AssertEqualObjects([c asJSON], expected[i++]);
    }
}


- (void) testUnicodeCollationWithLocale {
    NSArray* letters = @[@"B", @"A", @"Z", @"Å"];
    for (NSString* letter in letters) {
        CBLMutableDocument* doc = [self createDocument];
        [doc setValue: letter forKey: @"string"];
        [self saveDocument: doc];
    }
    
    CBLQueryExpression* STRING = [CBLQueryExpression property: @"string"];
    CBLQuerySelectResult* S_STRING = [CBLQuerySelectResult expression: STRING];
    
    // Without locale:
    CBLQueryCollation* NO_LOCALE = [CBLQueryCollation unicodeWithLocale: nil
                                                             ignoreCase: NO
                                                          ignoreAccents: NO];
    CBLQuery* q = [CBLQueryBuilder select: @[S_STRING]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: nil
                                  orderBy: @[[CBLQueryOrdering expression: [STRING collate: NO_LOCALE]]]];
    
    NSArray* expected = @[@"A", @"Å", @"B", @"Z"];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqualObjects([r stringAtIndex: 0], expected[n-1]);
    }];
    AssertEqual(numRows, expected.count);
    
    // With locale:
    CBLQueryCollation* WITH_LOCALE = [CBLQueryCollation unicodeWithLocale: @"se"
                                                               ignoreCase: NO
                                                            ignoreAccents: NO];
    q = [CBLQueryBuilder select: @[S_STRING]
                           from: [CBLQueryDataSource database: self.db]
                          where: nil
                        orderBy: @[[CBLQueryOrdering expression: [STRING collate: WITH_LOCALE]]]];
    
    expected = @[@"A", @"B", @"Z", @"Å"];
    numRows = [self verifyQuery: q randomAccess: NO test: ^(uint64_t n, CBLQueryResult* r)
    {
        AssertEqualObjects([r stringAtIndex: 0], expected[n-1]);
    }];
    AssertEqual(numRows, expected.count);
}


- (void) testCompareWithUnicodeCollation {
    id bothSensitive = [CBLQueryCollation unicodeWithLocale: nil ignoreCase: NO ignoreAccents: NO];
    id accentSensitive = [CBLQueryCollation unicodeWithLocale: nil ignoreCase: YES ignoreAccents: NO];
    id caseSensitive = [CBLQueryCollation unicodeWithLocale: nil ignoreCase: NO ignoreAccents: YES];
    id noSensitive = [CBLQueryCollation unicodeWithLocale: nil ignoreCase: YES ignoreAccents: YES];
    
    NSArray* testData =
    @[// Edge cases: empty and 1-char strings:
      @[@"", @"", @YES, bothSensitive],
      @[@"", @"a", @NO, bothSensitive],
      @[@"a", @"a", @YES, bothSensitive],
      
      // Case sensitive: lowercase come first by unicode rules:
      @[@"a", @"A", @NO, bothSensitive],
      @[@"abc", @"abc", @YES, bothSensitive],
      @[@"Aaa", @"abc", @NO, bothSensitive],
      @[@"abc", @"abC", @NO, bothSensitive],
      @[@"AB", @"abc", @NO, bothSensitive],
      
      // Case insenstive:
      @[@"ABCDEF", @"ZYXWVU", @NO, accentSensitive],
      @[@"ABCDEF", @"Z", @NO, accentSensitive],
      
      @[@"a", @"A", @YES, accentSensitive],
      @[@"abc", @"ABC", @YES, accentSensitive],
      @[@"ABA", @"abc", @NO, accentSensitive],
      
      @[@"commonprefix1", @"commonprefix2", @NO, accentSensitive],
      @[@"commonPrefix1", @"commonprefix2", @NO, accentSensitive],
      
      @[@"abcdef", @"abcdefghijklm", @NO, accentSensitive],
      @[@"abcdeF", @"abcdefghijklm", @NO, accentSensitive],
      
      // Now bring in non-ASCII characters:
      @[@"a", @"á", @NO, accentSensitive],
      @[@"", @"á", @NO, accentSensitive],
      @[@"á", @"á", @YES, accentSensitive],
      @[@"•a", @"•A", @YES, accentSensitive],
      
      @[@"test a", @"test á", @NO, accentSensitive],
      @[@"test á", @"test b", @NO, accentSensitive],
      @[@"test á", @"test Á", @YES, accentSensitive],
      @[@"test á1", @"test Á2", @NO, accentSensitive],
      
      // Case sensitive, diacritic sensitive:
      @[@"ABCDEF", @"ZYXWVU", @NO, bothSensitive],
      @[@"ABCDEF", @"Z", @NO, bothSensitive],
      @[@"a", @"A", @NO, bothSensitive],
      @[@"abc", @"ABC", @NO, bothSensitive],
      @[@"•a", @"•A", @NO, bothSensitive],
      @[@"test a", @"test á", @NO, bothSensitive],
      @[@"Ähnlichkeit", @"apple", @NO, bothSensitive], // Because 'h'-vs-'p' beats 'Ä'-vs-'a'
      @[@"ax", @"Äz", @NO, bothSensitive],
      @[@"test a", @"test Á", @NO, bothSensitive],
      @[@"test Á", @"test e", @NO, bothSensitive],
      @[@"test á", @"test Á", @NO, bothSensitive],
      @[@"test á", @"test b", @NO, bothSensitive],
      @[@"test u", @"test Ü", @NO, bothSensitive],
      
      // Case sensitive, diacritic insensitive
      @[@"abc", @"ABC", @NO, caseSensitive],
      @[@"test á", @"test a", @YES, caseSensitive],
      @[@"test á", @"test A", @NO, caseSensitive],
      @[@"test á", @"test b", @NO, caseSensitive],
      @[@"test á", @"test Á", @NO, caseSensitive],
      
      // Case and diacritic insensitive
      @[@"test á", @"test Á", @YES, noSensitive]
    ];
    
    for (NSArray* data in testData) {
        CBLMutableDocument* doc = [self createDocument];
        [doc setValue: data[0] forKey: @"value"];
        [self saveDocument: doc];
        
        CBLQueryExpression* VALUE = [CBLQueryExpression property: @"value"];
        CBLQueryExpression* comparison = [data[2] boolValue] ?
            [[VALUE collate: data[3]] equalTo: [CBLQueryExpression value: data[1]]] :
            [[VALUE collate: data[3]] lessThan: [CBLQueryExpression value: data[1]]];
        
        // NSLog(@"Compare %@ and %@, result = %@", data[0], data[1], data[2]);
        
        CBLQuery* q = [CBLQueryBuilder select: @[]
                                         from: [CBLQueryDataSource database: self.db]
                                        where: comparison];
        uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                        test: ^(uint64_t n, CBLQueryResult* r) { }];
        AssertEqual(numRows, 1u);
        
        Assert([self.db deleteDocument: doc error: nil]);
    }
}


- (void) testLiveQuery {
    [self loadNumbers: 100];
    
    __block int count = 0;
    XCTestExpectation* x = [self expectationWithDescription: @"changes"];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [[CBLQueryExpression property: @"number1"] lessThan: [CBLQueryExpression integer: 10]]
                                  orderBy: @[[CBLQueryOrdering property: @"number1"]]];
    
    id token = [q addChangeListener: ^(CBLQueryChange* change) {
        count++;
        AssertNotNil(change.query);
        AssertNil(change.error);
        NSArray<CBLQueryResult*>* rows = [change.results allObjects];
        if (count == 1) {
            AssertEqual(rows.count, 9u);
        } else {
            AssertEqual(rows.count, 10u);
            CBLDocument* doc = [self.db documentWithID: [rows[0] valueAtIndex: 0]];
            AssertEqualObjects([doc valueForKey: @"number1"], @(-1));
            [x fulfill];
        }
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self createDocNumbered: -1 of: 100];
    });

    [self waitForExpectationsWithTimeout: 10.0 handler: ^(NSError *error) { }];
    
    [q removeChangeListenerWithToken: token];
}


- (void) testLiveQueryNoUpdate {
    [self loadNumbers: 100];
    
    __block int count = 0;
    CBLQuery* q = [CBLQueryBuilder select: @[]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [[CBLQueryExpression property: @"number1"] lessThan: [CBLQueryExpression integer: 10]]
                                  orderBy: @[[CBLQueryOrdering property: @"number1"]]];
    
    id token = [q addChangeListener:^(CBLQueryChange* change) {
        count++;
        AssertNotNil(change.query);
        AssertNil(change.error);
        NSArray<CBLQueryResult*>* rows = [change.results allObjects];
        if (count == 1) {
            AssertEqual(rows.count, 9u);
        } else {
            XCTFail(@"Unexpected update from LiveQuery");
        }
    }];

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
    
    [q removeChangeListenerWithToken: token];
}

- (void) testCloseDatabaseWithActiveLiveQuery {
    // Add a live query to the DB:
    XCTestExpectation* x = [self expectationWithDescription: @"changes"];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]];
    id token = [q addChangeListener: ^(CBLQueryChange* change) {
        [x fulfill];
    }];
    [self waitForExpectations: @[x] timeout: 2.0];
    
    // Confirm the addition of query:
    AssertEqual(self.db.liveQueries.count,(unsigned long)1);
    
    // Close Database:
    [self expectError: CBLErrorDomain code: CBLErrorBusy in: ^BOOL(NSError** err) {
        return [self.db close: err];
    }];
    
    // Remove the listener:
    [q removeChangeListenerWithToken: token];
    
    AssertEqual(self.db.liveQueries.count,(unsigned long)0);
    
    // Close Database:
    NSError* error;
    Assert([self.db close: &error], @"Cannot close database: %@", error);
    
    sleep(2);
}


- (void) testDeleteDatabaseWithActiveLiveQuery {
    // Add a live query to the DB:
    XCTestExpectation* x = [self expectationWithDescription: @"changes"];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]];
    id token = [q addChangeListener: ^(CBLQueryChange* change) {
        [x fulfill];
    }];
    [self waitForExpectations: @[x] timeout: 2.0];
    
    // Confirm the addition of query:
    AssertEqual(self.db.liveQueries.count,(unsigned long)1);

    // Delete Database:
    [self expectError: CBLErrorDomain code: CBLErrorBusy in: ^BOOL(NSError** err) {
        return [self.db delete: err];
    }];
    
    // Remove the listener:
    [q removeChangeListenerWithToken: token];
    AssertEqual(self.db.liveQueries.count,(unsigned long)0);
    
    // Delete Database:
    NSError* error;
    Assert([self.db delete: &error], @"Cannot delete database: %@", error);
}


- (void) testResultSetEnumeration {
    [self loadNumbers: 5];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: nil
                                  orderBy: @[[CBLQueryOrdering property: @"number1"]]];
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    
    // Enumeration:
    NSUInteger i = 0;
    CBLQueryResult *r;
    while ((r = [rs nextObject])) {
        NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)(i+1)];
        AssertEqualObjects([r valueAtIndex: 0], docID);
        i++;
    }
    AssertEqual(i, 5u);
    AssertNil([rs nextObject]);
    AssertEqual([rs allObjects].count, 0u);
    AssertEqual([rs allResults].count, 0u);
    
    // Fast enumeration:
    i = 0;
    rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);

    for (r in rs) {
        NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)(i+1)];
        AssertEqualObjects([r valueAtIndex: 0], docID);
        i++;
    }
    AssertEqual(i, 5u);
    AssertNil([rs nextObject]);
    AssertEqual([rs allObjects].count, 0u);
    AssertEqual([rs allResults].count, 0u);
}


- (void) testGetAllResults {
    [self loadNumbers: 5];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: nil
                                  orderBy: @[[CBLQueryOrdering property: @"number1"]]];
    
    // Get all results:
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);

    NSUInteger i = 0;
    NSArray* results = [rs allResults];
    for (CBLQueryResult* r in results) {
        NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)(i+1)];
        AssertEqualObjects([r valueAtIndex: 0], docID);
        i++;
    }
    AssertEqual(results.count, 5u);
    AssertNil([rs nextObject]);
    AssertEqual([rs allObjects].count, 0u);
    AssertEqual([rs allResults].count, 0u);
    
    // Partial enumerating then get all results:
    rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    
    AssertNotNil([rs nextObject]);
    AssertNotNil([rs nextObject]);
    
    i = 0;
    results = [rs allResults];
    for (CBLQueryResult* r in results) {
        NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)(i+3)];
        AssertEqualObjects([r valueAtIndex: 0], docID);
        i++;
    }
    AssertEqual(results.count, 3u);
    AssertNil([rs nextObject]);
    AssertEqual([rs allObjects].count, 0u);
    AssertEqual([rs allResults].count, 0u);
}


- (void) testMissingValue {
    CBLMutableDocument* doc1 = [self createDocument: @"doc1"];
    [doc1 setValue: @"Scott" forKey: @"name"];
    [doc1 setValue: nil forKey: @"address"];
    [self saveDocument: doc1];
    
    CBLQuery *q = [CBLQueryBuilder select: @[[CBLQuerySelectResult property: @"name"],
                                             [CBLQuerySelectResult property: @"address"],
                                             [CBLQuerySelectResult property: @"age"]]
                                     from: [CBLQueryDataSource database: self.db]];
    
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    
    CBLQueryResult* r = [rs nextObject];
    
    // Array:
    AssertEqual(r.count, 3u);
    AssertEqualObjects([r stringAtIndex: 0], @"Scott");
    AssertNil([r valueAtIndex: 1]);
    AssertNil([r valueAtIndex: 2]);
    AssertEqualObjects([r toArray], (@[@"Scott", [NSNull null], [NSNull null]]));
    
    // Dictionary:
    AssertEqualObjects([r stringForKey: @"name"], @"Scott");
    AssertNil([r stringForKey: @"address"]);
    Assert([r containsValueForKey: @"address"]);
    AssertNil([r stringForKey: @"age"]);
    AssertFalse([r containsValueForKey: @"age"]);
    AssertEqualObjects([r toDictionary], (@{@"name": @"Scott", @"address": [NSNull null]}));
}


- (void) testForumJoin {
    [self loadJSONString:
     @"{\"id\":\"ecc:102\",\"type\":\"category\",\"items\":[\"eci:742\",\"eci:743\",\"eci:744\"],\"name\":\"Skills\"}\n"
      "{\"id\":\"eci:742\",\"type\":\"item\",\"chinese\":\"技术\",\"english\":\"technique\",\"pinyin\":\"jìshù\"}\n"
      "{\"id\":\"eci:743\",\"type\":\"item\",\"chinese\":\"技术\",\"english\":\"skill\",\"pinyin\":\"jìqiǎo\"}"
                   named: @"forum.json"];


    CBLQuerySelectResult* ITEM_DOC_ID =
    [CBLQuerySelectResult expression: [CBLQueryMeta idFrom: @"itemDS"] as:@"ITEMID"];


    CBLQuerySelectResult* CATEGORY_DOC_ID =
    [CBLQuerySelectResult expression: [CBLQueryMeta idFrom: @"categoryDS"] as:@"CATEGORYID"];

    CBLQueryExpression* ITEMID  = [CBLQueryExpression property:@"id" from: @"itemDS"];

    CBLQueryExpression* CATEGORYITEMS  = [CBLQueryExpression property: @"items" from:@"categoryDS"] ;
    CBLQueryVariableExpression* CATEGORYITEMVAR = [CBLQueryArrayExpression variableWithName: @"item"];

    CBLQueryExpression* on = [CBLQueryArrayExpression
                              any: CATEGORYITEMVAR
                              in: CATEGORYITEMS
                              satisfies: [CATEGORYITEMVAR equalTo: ITEMID]];


    CBLQueryJoin* join = [CBLQueryJoin join: [CBLQueryDataSource database: self.db as: @"itemDS"]
                                         on: on];
    CBLQuery* q = [CBLQueryBuilder select: @[ITEM_DOC_ID, CATEGORY_DOC_ID]
                                     from: [CBLQueryDataSource database: self.db as: @"categoryDS"]
                                     join: @[join]];
    Assert(q);
    NSError* error;

    NSLog(@"%@",[q explain:nil]);

    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs);

    int i = 0;
    for (CBLQueryResult* r in rs) {
        NSLog(@" %@",[r toDictionary]);
        i++;
    }
    AssertEqual(i, 2);
}


@end
