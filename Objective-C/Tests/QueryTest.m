//
//  XQueryTest.m
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
        [self verifyQuery: q test: ^(uint64_t n, CBLQueryRow *row) {
            id props = row.document.properties;
            Assert([result containsObject: props]);
            [result removeObject: props];
        }];
        AssertEqual(result.count, 0u);
    }
}


- (void) test_NoWhereQuery {
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


- (void) test_WhereComparison {
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


- (void) test_WhereWithArithmetic {
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


- (void) test_WhereAndOr {
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
    NSError* error;
    CBLDocument* doc1 = [self.db document];
    doc1[@"number"] = @(1);
    Assert([doc1 save: &error], @"Error when creating a document: %@", error);
    
    CBLDocument* doc2 = [self.db document];
    doc2[@"string"] = @"string";
    Assert([doc2 save: &error], @"Error when creating a document: %@", error);
    
    CBLQuery* q = [CBLQuery select: [CBLQuerySelect all]
                              from: [CBLQueryDatabase database: self.db]
                             where: [[CBLQueryExpression property: @"number"] notNull]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q test: ^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        AssertEqualObjects(doc.documentID, doc1.documentID);
        AssertEqualObjects(doc[@"number"], @(1));
    }];
    AssertEqual(numRows, 1u);
    
    q = [CBLQuery select: [CBLQuerySelect all]
                    from: [CBLQueryDatabase database: self.db]
                   where: [[CBLQueryExpression property: @"number"] isNull]];
    Assert(q);
    numRows = [self verifyQuery: q test: ^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        AssertEqualObjects(doc.documentID, doc1.documentID);
        AssertEqualObjects(doc[@"string"], @"string");
    }];
    AssertEqual(numRows, 1u);
}


- (void) test_WhereIs {
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


- (void) test_WhereBetween {
    CBLQueryExpression* n1 = [CBLQueryExpression property: @"number1"];
    NSArray* cases = @[
        @[[n1 between: @(3) and: @(7)], @"number1 BETWEEN {3,7}"]
    ];
    NSArray* numbers = [self loadNumbers: 10];
    [self runTestWithNumbers: numbers cases: cases];
}


- (void) failingTest08_WhereIn {
    CBLQueryExpression* n1 = [CBLQueryExpression property: @"number1"];
    NSArray* cases = @[
        @[[n1 inExpressions:@[@(3), @(5), @(7), @(9)]], @"number1 IN {3, 5, 7 , 9}"]
    ];
    NSArray* numbers = [self loadNumbers: 10];
    [self runTestWithNumbers: numbers cases: cases];
}


- (void) failingTest_WhereLike {
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
    AssertEqual((int)numRows, 5);
}


- (void) failingTest_WhereRegex {
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
    AssertEqual((int)numRows, 5);
}


- (void) test_WhereMatch {
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
    AssertEqual((int)numRows, 2);
}


- (void) test_OrderBy {
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


- (void) failingTest13_SelectDistinct {
    NSError* error;
    CBLDocument* doc1 = [self.db document];
    doc1[@"number"] = @(1);
    Assert([doc1 save: &error], @"Error when creating a document: %@", error);
    
    CBLDocument* doc2 = [self.db document];
    doc2[@"number"] = @(1);
    Assert([doc2 save: &error], @"Error when creating a document: %@", error);
    
    CBLQuery* q = [CBLQuery selectDistict: [CBLQuerySelect all]
                                     from: [CBLQueryDatabase database: self.db]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q test: ^(uint64_t n, CBLQueryRow *row) {
        CBLDocument* doc = row.document;
        AssertEqualObjects(doc.documentID, doc1.documentID);
    }];
    AssertEqual(numRows, 1u);
}

@end
