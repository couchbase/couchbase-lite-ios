//
//  QueryTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLQuery.h"
#import "CBLQuerySelect.h"
#import "CBLQueryDataSource.h"
#import "CBLQueryOrderBy.h"


@interface QueryTest : CBLTestCase

@end

@implementation QueryTest


- (uint64_t) verifyQuery: (CBLQuery*)q test: (void (^)(uint64_t n, CBLQueryRow *row))block {
    NSError* error;
    NSEnumerator* e = [q run: &error];
    Assert(e, @"Query failed: %@", error);
    uint64_t n = 0;
    for (CBLQueryRow *row in e) {
        //Log(@"Row: docID='%@', sequence=%llu", row.documentID, row.sequence);
        block(++n, row);
    }
    return n;
}


- (NSArray*)loadNumbers:(NSInteger)num {
    NSMutableArray* numbers = [NSMutableArray array];
    NSError *batchError;
    BOOL ok = [self.db inBatch: &batchError do: ^{
        for (NSInteger i = 1; i <= num; i++) {
            NSError* error;
            NSString* docId= [NSString stringWithFormat: @"doc%ld", (long)i];
            CBLDocument* doc = [self.db documentWithID: docId];
            doc[@"number1"] = @(i);
            doc[@"number2"] = @(num-i);
            bool saved = [doc save: &error];
            Assert(saved, @"Couldn't save document: %@", error);
            [numbers addObject: doc.properties];
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
        NSInteger total = result.count;
        NSInteger rows = [self verifyQuery: q test: ^(uint64_t n, CBLQueryRow *row) {
            id props = row.document.properties;
            Assert([result containsObject: props]);
            [result removeObject: props];
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
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
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
    doc1[@"name"] = @"Scott";
    doc1[@"address"] = [NSNull null];
    Assert([doc1 save: &error], @"Error when saving a document: %@", error);
    
    CBLDocument* doc2 = [self.db documentWithID: @"doc2"];
    doc2[@"name"] = @"Tiger";
    doc2[@"address"] = @"123 1st ave.";
    doc2[@"age"] = @(20);
    Assert([doc2 save: &error], @"Error when saving a document: %@", error);
    
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
        uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
            if (expectedDocs.count <= n) {
                CBLDocument* doc = expectedDocs[n-1];
                AssertEqualObjects(doc.documentID, row.documentID, @"Failed case: %@", exp);
            }
        }];
        AssertEqual((int)numRows, (int)expectedDocs.count, @"Failed case: %@", exp);
    }
}


- (void) testWhereIs {
    NSError* error;
    CBLDocument* doc1 = [self.db document];
    doc1 [@"string"] = @"string";
    Assert([doc1 save: &error], @"Error when creating a document: %@", error);
    
    CBLQuery* q = [CBLQuery select: [CBLQuerySelect all]
                              from: [CBLQueryDatabase database: self.db]
                             where: [[CBLQueryExpression property: @"string"] is: @"string"]];
    
    Assert(q);
    uint64_t numRows = [self verifyQuery: q test: ^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        AssertEqualObjects(doc.documentID, doc1.documentID);
        AssertEqualObjects(doc[@"string"], @"string");
    }];
    AssertEqual(numRows, 1u);
    
    q = [CBLQuery select: [CBLQuerySelect all]
                    from: [CBLQueryDatabase database: self.db]
                   where: [[CBLQueryExpression property: @"string"] isNot: @"string1"]];
    
    Assert(q);
    numRows = [self verifyQuery: q test: ^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        AssertEqualObjects(doc.documentID, doc1.documentID);
        AssertEqualObjects(doc[@"string"], @"string");
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
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        AssertEqualObjects(row.document[@"name"][@"first"], expected[n-1]);
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
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        NSString* firstName = doc[@"name"][@"first"];
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
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        NSString* firstName = doc[@"name"][@"first"];
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
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
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
        uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
            CBLDocument* doc = row.document;
            NSString* firstName = doc[@"name"][@"first"];
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
    CBLDocument* doc1 = [self.db document];
    doc1[@"number"] = @(1);
    Assert([doc1 save: &error], @"Error when creating a document: %@", error);
    
    CBLDocument* doc2 = [self.db document];
    doc2[@"number"] = @(1);
    Assert([doc2 save: &error], @"Error when creating a document: %@", error);
    
    CBLQuery* q = [CBLQuery selectDistinct: [CBLQuerySelect all]
                                     from: [CBLQueryDatabase database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q test: ^(uint64_t n, CBLQueryRow *row) {
        AssertEqualObjects(row.documentID, doc1.documentID);
    }];
    AssertEqual(numRows, 1u);
}


@end
