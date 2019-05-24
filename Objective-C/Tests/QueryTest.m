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

#import "QueryTest.h"

@implementation QueryTest

#pragma mark - Helper methods

- (CBLMutableDocument*) createDocNumbered: (NSInteger)i of: (NSInteger)num {
    NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)i];
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: docID];
    [doc setValue: @(i) forKey: @"number1"];
    [doc setValue: @(num-i) forKey: @"number2"];
    [self saveDocument: doc];
    return doc;
}

- (NSArray*) loadNumbers:(NSInteger)num {
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

- (void) loadStudents {
    NSError* error;
    NSTimeInterval aDayInterval = 24 * 60 * 60;
    NSDate* twoWeeksBack = [NSDate dateWithTimeIntervalSinceNow: -2 * 7 * aDayInterval];
    
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] init];
    [doc1 setString: @"Jason" forKey: @"name"];
    [doc1 setString: @"santa clara" forKey: @"city"];
    [doc1 setNumber: @(100) forKey: @"code"];
    [doc1 setInteger: 2016 forKey: @"year"];
    [doc1 setLongLong: 123456789 forKey: @"id"];
    [doc1 setFloat: 67.89f forKey: @"score"];
    [doc1 setDouble: 3.4 forKey: @"gpa"];
    [doc1 setBoolean: YES forKey: @"isFullTime"];
    [doc1 setDate: twoWeeksBack forKey: @"startDate"];
    Assert([_db saveDocument: doc1 error: &error], @"Error when creating a document: %@", error);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] init];
    [doc2 setString: @"Bob" forKey: @"name"];
    [doc2 setString: @"santa clara" forKey: @"city"];
    [doc2 setNumber: @(101) forKey: @"code"];
    [doc2 setInteger: 2016 forKey: @"year"];
    [doc2 setLongLong: 123456790 forKey: @"id"];
    [doc2 setFloat: 60.89f forKey: @"score"];
    [doc2 setDouble: 3.23 forKey: @"gpa"];
    [doc2 setBoolean: YES forKey: @"isFullTime"];
    [doc2 setDate: [twoWeeksBack dateByAddingTimeInterval: aDayInterval] forKey: @"startDate"];
    Assert([_db saveDocument: doc2 error: &error], @"Error when creating a document: %@", error);
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] init];
    [doc3 setString: @"Alice" forKey: @"name"];
    [doc3 setString: @"santa clara" forKey: @"city"];
    [doc3 setNumber: @(102) forKey: @"code"];
    [doc3 setInteger: 2017 forKey: @"year"];
    [doc3 setLongLong: 123456791 forKey: @"id"];
    [doc3 setFloat: 70.90f forKey: @"score"];
    [doc3 setDouble: 3.30 forKey: @"gpa"];
    [doc3 setBoolean: YES forKey: @"isFullTime"];
    [doc3 setDate: twoWeeksBack forKey: @"startDate"];
    Assert([_db saveDocument: doc3 error: &error], @"Error when creating a document: %@", error);
    
    CBLMutableDocument* doc4 = [[CBLMutableDocument alloc] init];
    [doc4 setString: @"Peter" forKey: @"name"];
    [doc4 setString: @"santa clara" forKey: @"city"];
    [doc4 setNumber: @(103) forKey: @"code"];
    [doc4 setInteger: 2017 forKey: @"year"];
    [doc4 setLongLong: 123456792 forKey: @"id"];
    [doc4 setFloat: 59.90f forKey: @"score"];
    [doc4 setDouble: 4.01 forKey: @"gpa"];
    [doc4 setBoolean: YES forKey: @"isFullTime"];
    [doc4 setDate: twoWeeksBack forKey: @"startDate"];
    Assert([_db saveDocument: doc4 error: &error], @"Error when creating a document: %@", error);
    
    CBLMutableDocument* doc5 = [[CBLMutableDocument alloc] init];
    [doc1 setString: @"Sheryl" forKey: @"name"];
    [doc5 setString: @"santa clara" forKey: @"city"];
    [doc5 setNumber: @(104) forKey: @"code"];
    [doc5 setInteger: 2017 forKey: @"year"];
    [doc5 setLongLong: 123456793 forKey: @"id"];
    [doc5 setFloat: 65.90f forKey: @"score"];
    [doc5 setDouble: 3.52 forKey: @"gpa"];
    [doc5 setBoolean: YES forKey: @"isFullTime"];
    [doc5 setDate: [twoWeeksBack dateByAddingTimeInterval: 2 * aDayInterval] forKey: @"startDate"];
    Assert([_db saveDocument: doc5 error: &error], @"Error when creating a document: %@", error);
    
    CBLMutableDocument* doc6 = [[CBLMutableDocument alloc] init];
    [doc6 setString: @"Tom" forKey: @"name"];
    [doc6 setString: @"santa clara" forKey: @"city"];
    [doc6 setNumber: @(105) forKey: @"code"];
    [doc6 setInteger: 2017 forKey: @"year"];
    [doc6 setLongLong: 123456794 forKey: @"id"];
    [doc6 setFloat: 65.92f forKey: @"score"];
    [doc6 setDouble: 4.02 forKey: @"gpa"];
    [doc6 setBoolean: NO forKey: @"isFullTime"];
    [doc6 setDate: [twoWeeksBack dateByAddingTimeInterval: 2 * aDayInterval] forKey: @"startDate"];
    Assert([_db saveDocument: doc6 error: &error], @"Error when creating a document: %@", error);
    
    CBLMutableDocument* doc7 = [[CBLMutableDocument alloc] init];
    [doc7 setString: @"Casper" forKey: @"name"];
    [doc7 setString: @"santa clara" forKey: @"city"];
    [doc7 setNumber: @(106) forKey: @"code"];
    [doc7 setInteger: 2017 forKey: @"year"];
    [doc7 setLongLong: 123456795 forKey: @"id"];
    [doc7 setFloat: 65.92f forKey: @"score"];
    [doc7 setDouble: 4.02 forKey: @"gpa"];
    [doc7 setBoolean: YES forKey: @"isFullTime"];
    [doc7 setDate: twoWeeksBack forKey: @"startDate"];
    Assert([_db saveDocument: doc7 error: &error], @"Error when creating a document: %@", error);
    
    CBLMutableDocument* doc8 = [[CBLMutableDocument alloc] init];
    [doc8 setString: @"Casper" forKey: @"name"];
    [doc8 setString: @"santa clara" forKey: @"city"];
    [doc8 setNumber: @(106) forKey: @"code"];
    [doc8 setInteger: 2017 forKey: @"year"];
    [doc8 setLongLong: 123456796 forKey: @"id"];
    [doc8 setFloat: 65.92f forKey: @"score"];
    [doc8 setDouble: 4.02 forKey: @"gpa"];
    [doc8 setBoolean: YES forKey: @"isFullTime"];
    [doc8 setDate: [twoWeeksBack dateByAddingTimeInterval: 1 * aDayInterval] forKey: @"startDate"];
    Assert([_db saveDocument: doc8 error: &error], @"Error when creating a document: %@", error);
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

@end
