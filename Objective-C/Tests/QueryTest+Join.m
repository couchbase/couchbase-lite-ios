//
//  QueryTest+Join.m
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

@interface QueryTestWithJoin : QueryTest

@end

@implementation QueryTestWithJoin

#pragma mark - JOIN

- (void) testJoin {
    [self loadNumbers: 100];
    
    CBLMutableDocument* joinme = [[CBLMutableDocument alloc] initWithID: @"joinme"];
    [joinme setValue: @42 forKey: @"theone"];
    [self saveDocument: joinme];
    
    CBLMutableDocument* joinmeCopy = [[CBLMutableDocument alloc] initWithID: @"joinmeCopy"];
    [joinmeCopy setValue: @42 forKey: @"theone"];
    [self saveDocument: joinmeCopy];
    
    CBLQueryExpression* propNum1 = [CBLQueryExpression property: @"number1" from: @"main"];
    CBLQueryExpression* propNum2 = [CBLQueryExpression property: @"number2" from: @"main"];
    CBLQueryExpression* propTheOne = [CBLQueryExpression property: @"theone" from: @"secondary"];
    
    CBLQueryJoin* join = [CBLQueryJoin join: [CBLQueryDataSource database: self.db as: @"secondary"]
                                         on: [propNum1 equalTo: propTheOne]];
    
    // there is no particular reason for using inner-join and join. Just for the sake of using
    // two different statement with same result only.
    CBLQueryJoin* innerJoin;
    innerJoin = [CBLQueryJoin innerJoin: [CBLQueryDataSource database: self.db as: @"secondary"]
                                     on: [propNum1 equalTo: propTheOne]];
    
    // select from join: this should return 2 similar rows with same value.
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: propNum2]]
                                     from: [CBLQueryDataSource database: self.db as: @"main"]
                                     join: @[join]];
    Assert(q);
    uint64_t numRows = 0;
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r) {
        AssertEqual([r integerForKey: @"number2"], 58, @"because that was the number stored in \
                    'number2' of the matching doc");
    }];
    AssertEqual(numRows, 2u);
    
    // select distinct from join: this should return only single row!!
    q = [CBLQueryBuilder selectDistinct: @[[CBLQuerySelectResult expression: propNum1]]
                                   from: [CBLQueryDataSource database: self.db as: @"main"]
                                   join: @[innerJoin]];
    Assert(q);
    numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r) {
        AssertEqual([r integerForKey: @"number1"], 42);
    }];
    AssertEqual(numRows, 1u);
}

- (void) testSelectFromJoinWhere {
    [self loadNumbers: 100];
    
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] init];
    [doc1 setValue: @42 forKey: @"theone"];
    [self saveDocument: doc1];
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] init];
    [doc2 setValue: @42 forKey: @"theone"];
    [self saveDocument: doc2];
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] init];
    [doc3 setValue: @32 forKey: @"theone"];
    [self saveDocument: doc3];
    
    CBLQuerySelectResult* MAIN_DOC_ID =
    [CBLQuerySelectResult expression: [CBLQueryMeta idFrom: @"main"]];
    
    CBLQueryExpression* on = [[CBLQueryExpression property: @"number1" from: @"main"]
                              equalTo: [CBLQueryExpression property:@"theone" from:@"secondary"]];
    CBLQueryJoin* join = [CBLQueryJoin join: [CBLQueryDataSource database: self.db as: @"secondary"]
                                         on: on];
    CBLQuery* q = [CBLQueryBuilder select: @[MAIN_DOC_ID]
                                     from: [CBLQueryDataSource database: self.db as: @"main"]
                                     join: @[join]
                                    where: [[CBLQueryExpression property: @"number1"
                                                                    from: @"main"]
                                            greaterThan: [CBLQueryExpression value: @(35)]]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
                        {
                            CBLDocument* doc = [self.db documentWithID: [r valueAtIndex: 0]];
                            AssertEqual([doc integerForKey:@"number1"], 42);
                        }];
    AssertEqual(numRows, 2u);
    
    q = [CBLQueryBuilder selectDistinct: @[[CBLQuerySelectResult
                                            expression: [CBLQueryExpression property: @"number1"
                                                                                from: @"main"]]]
                                   from: [CBLQueryDataSource database: self.db as: @"main"]
                                   join: @[join]
                                  where: [[CBLQueryExpression property: @"number1"
                                                                  from: @"main"]
                                          greaterThan: [CBLQueryExpression value: @(35)]]];
    Assert(q);
    numRows = [self verifyQuery: q randomAccess: YES
                           test: ^(uint64_t n, CBLQueryResult* r)
               {
                   AssertEqual([r integerForKey: @"number1"], 42);
               }];
    AssertEqual(numRows, 1u);
}

- (void) testSelectFromJoinWhereGroupByHaving {
    [self loadNumbers: 100];
    
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] init];
    [doc1 setValue: @42 forKey: @"theone"];
    [doc1 setValue: @"Tom" forKey: @"name"];
    [self saveDocument: doc1];
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] init];
    [doc2 setValue: @43 forKey: @"theone"];
    [doc2 setValue: @"Tom" forKey: @"name"];
    [self saveDocument: doc2];
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] init];
    [doc3 setValue: @32 forKey: @"theone"];
    [doc3 setValue: @"Bob" forKey: @"name"];
    [self saveDocument: doc3];
    
    CBLQueryExpression* COUNT  = [CBLQueryFunction count: [CBLQueryExpression integer: 1]];
    CBLQuerySelectResult* MAIN_DOC_ID =
    [CBLQuerySelectResult expression: [CBLQueryMeta idFrom: @"main"]];
    
    CBLQueryExpression* on = [[CBLQueryExpression property: @"number1" from: @"main"]
                              equalTo: [CBLQueryExpression property:@"theone" from:@"secondary"]];
    CBLQueryJoin* join = [CBLQueryJoin join: [CBLQueryDataSource database: self.db as: @"secondary"]
                                         on: on];
    CBLQuery* q = [CBLQueryBuilder select: @[MAIN_DOC_ID, [CBLQuerySelectResult expression: COUNT as: @"count"]]
                                     from: [CBLQueryDataSource database: self.db as: @"main"]
                                     join: @[join]
                                    where: nil
                                  groupBy: @[[CBLQueryExpression property: @"theone" from: @"secondary"]]
                                   having: [COUNT lessThan: [CBLQueryExpression integer: 2]]];
    Assert(q);
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r)
                        {
                            AssertEqual([r integerForKey:@"count"], 1);
                        }];
    AssertEqual(numRows, 3u);
    
    CBLQueryExpression* NAME  = [CBLQueryExpression property: @"name" from: @"secondary"];
    CBLQuerySelectResult* S_NAME = [CBLQuerySelectResult expression: NAME];
    q = [CBLQueryBuilder selectDistinct: @[S_NAME, [CBLQuerySelectResult expression: COUNT as: @"count"]]
                                   from: [CBLQueryDataSource database: self.db as: @"main"]
                                   join: @[join]
                                  where: nil
                                groupBy: @[[CBLQueryExpression property: @"theone" from: @"secondary"]]
                                 having: [COUNT lessThan: [CBLQueryExpression integer: 2]]];
    Assert(q);
    numRows = [self verifyQuery: q randomAccess: YES
                           test: ^(uint64_t n, CBLQueryResult* r)
               {
                   CBLDocument* doc = [self.db documentWithID: [r valueAtIndex: 0]];
                   AssertEqual([r integerForKey:@"count"], 1);
                   Assert([doc integerForKey:@"number1"] != 42);
               }];
    AssertEqual(numRows, 2u);
}

- (void) testSelectFromJoinWhereOrderBy {
    [self loadNumbers: 100];
    
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] init];
    [doc1 setValue: @97 forKey: @"theone"];
    [self saveDocument: doc1];
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] init];
    [doc2 setValue: @12 forKey: @"theone"];
    [self saveDocument: doc2];
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] init];
    [doc3 setValue: @12 forKey: @"theone"];
    [self saveDocument: doc3];
    
    CBLQueryExpression* numb = [CBLQueryExpression property:@"number1" from:@"main"];
    CBLQuerySelectResult* MAIN_DOC_ID =
    [CBLQuerySelectResult expression: [CBLQueryMeta idFrom: @"main"]];
    
    CBLQueryExpression* on = [[CBLQueryExpression property: @"number1" from: @"main"]
                              equalTo: [CBLQueryExpression property:@"theone" from:@"secondary"]];
    CBLQueryJoin* join = [CBLQueryJoin join: [CBLQueryDataSource database: self.db as: @"secondary"]
                                         on: on];
    CBLQuery* q = [CBLQueryBuilder select: @[MAIN_DOC_ID, [CBLQuerySelectResult expression: numb]]
                                     from: [CBLQueryDataSource database: self.db as: @"main"]
                                     join: @[join]
                                    where: nil
                                  orderBy: @[[CBLQueryOrdering expression: numb]]];
    Assert(q);
    NSError* error;
    NSArray* allResults = [q execute: &error].allResults;
    AssertEqual([allResults.firstObject integerForKey: @"number1"], 12);
    AssertEqual([allResults.lastObject integerForKey: @"number1"], 97);
    AssertEqual(allResults.count, 3u);
    
    q = [CBLQueryBuilder selectDistinct: @[MAIN_DOC_ID, [CBLQuerySelectResult expression: numb]]
                                   from: [CBLQueryDataSource database: self.db as: @"main"]
                                   join: @[join]
                                  where: nil
                                orderBy: @[[CBLQueryOrdering expression: numb]]];
    Assert(q);
    allResults = [q execute: &error].allResults;
    AssertEqual([allResults.firstObject integerForKey: @"number1"], 12);
    AssertEqual([allResults.lastObject integerForKey: @"number1"], 97);
    AssertEqual(allResults.count, 2u);
}

- (void) testSelectFromJoinWhereGroupByHavingOrderByLimit {
    [self loadNumbers: 100];
    
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] init];
    [doc1 setValue: @42 forKey: @"theone"];
    [doc1 setValue: @"Tom" forKey: @"name"];
    [self saveDocument: doc1];
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] init];
    [doc2 setValue: @43 forKey: @"theone"];
    [doc2 setValue: @"Tom" forKey: @"name"];
    [self saveDocument: doc2];
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] init];
    [doc3 setValue: @32 forKey: @"theone"];
    [doc3 setValue: @"Bob" forKey: @"name"];
    [self saveDocument: doc3];
    
    CBLQueryExpression* numb = [CBLQueryExpression property:@"number1" from:@"main"];
    CBLQueryExpression* COUNT  = [CBLQueryFunction count: [CBLQueryExpression integer: 1]];
    CBLQuerySelectResult* MAIN_DOC_ID =
    [CBLQuerySelectResult expression: [CBLQueryMeta idFrom: @"main"]];
    
    CBLQueryExpression* on = [[CBLQueryExpression property: @"number1" from: @"main"]
                              equalTo: [CBLQueryExpression property:@"theone" from:@"secondary"]];
    CBLQueryJoin* join = [CBLQueryJoin join: [CBLQueryDataSource database: self.db as: @"secondary"]
                                         on: on];
    CBLQuery* q = [CBLQueryBuilder select: @[MAIN_DOC_ID,
                                             [CBLQuerySelectResult expression: numb],
                                             [CBLQuerySelectResult expression: COUNT as: @"count"]]
                                     from: [CBLQueryDataSource database: self.db as: @"main"]
                                     join: @[join]
                                    where: nil
                                  groupBy: @[[CBLQueryExpression property: @"theone"
                                                                     from: @"secondary"]]
                                   having: nil
                                  orderBy: @[[CBLQueryOrdering expression: numb]]
                                    limit: [CBLQueryLimit limit: [CBLQueryExpression integer: 10]]];
    Assert(q);
    NSError* error;
    NSArray* allResults = [q execute: &error].allResults;
    AssertEqual([allResults.firstObject integerForKey:@"number1"], 32u);
    AssertEqual([allResults.lastObject integerForKey:@"number1"], 43u);
    AssertEqual(allResults.count, 3u);
    
    CBLQueryExpression* NAME  = [CBLQueryExpression property: @"name" from: @"secondary"];
    CBLQuerySelectResult* S_NAME = [CBLQuerySelectResult expression: NAME];
    q = [CBLQueryBuilder selectDistinct: @[S_NAME,
                                           [CBLQuerySelectResult expression: COUNT as: @"count"]]
                                   from: [CBLQueryDataSource database: self.db as: @"main"]
                                   join: @[join]
                                  where: nil
                                groupBy: @[[CBLQueryExpression property: @"theone"
                                                                   from: @"secondary"]]
                                 having: [COUNT lessThan: [CBLQueryExpression integer: 2]]
                                orderBy: @[[CBLQueryOrdering expression: NAME]]
                                  limit: [CBLQueryLimit limit: [CBLQueryExpression integer: 10]]];
    Assert(q);
    allResults = [q execute: &error].allResults;
    AssertEqualObjects([allResults.firstObject valueForKey:@"name"], @"Bob");
    AssertEqualObjects([allResults.lastObject valueForKey:@"name"], @"Tom");
    AssertEqual(allResults.count, 2u);
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

- (void) testJoinByDocID {
    [self loadNumbers: 100];
    
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"joinme"];
    [doc1 setInteger: 42 forKey: @"theone"];
    [doc1 setString: @"doc1" forKey: @"numberID"];
    [self saveDocument: doc1];
    
    // datasources
    CBLQueryDataSource* mainDS = [CBLQueryDataSource database: self.db as: @"main"];
    CBLQueryDataSource* secondaryDS = [CBLQueryDataSource database: self.db as: @"secondary"];
    
    // create the join statement
    CBLQueryExpression* mainPropExpr = [CBLQueryMeta idFrom: @"main"];
    CBLQueryExpression* secondaryExpr = [CBLQueryExpression property: @"numberID"
                                                                from: @"secondary"];
    CBLQueryExpression* joinExpr = [mainPropExpr equalTo: secondaryExpr];
    CBLQueryJoin* join = [CBLQueryJoin innerJoin: secondaryDS on: joinExpr];
    
    // select result statement
    CBLQuerySelectResult* mainDocID = [CBLQuerySelectResult expression: mainPropExpr
                                                                    as: @"mainDocID"];
    CBLQuerySelectResult* secondaryDocID = [CBLQuerySelectResult expression: [CBLQueryMeta
                                                                              idFrom: @"secondary"]
                                                                         as: @"secondaryDocID"];
    CBLQuerySelectResult* secondaryTheOne = [CBLQuerySelectResult
                                             expression: [CBLQueryExpression property: @"theone"
                                                                                 from:@"secondary"]];
    
    // query
    CBLQuery* q = [CBLQueryBuilder select: @[mainDocID, secondaryDocID, secondaryTheOne]
                                     from: mainDS
                                     join: @[join]];
    uint64_t numRows = [self verifyQuery: q randomAccess: NO test:^(uint64_t n, CBLQueryResult * _Nonnull result) {
        AssertEqual(n, 1u);
        NSString* docID = [result stringForKey: @"mainDocID"];
        CBLDocument* doc = [self.db documentWithID: docID];
        AssertEqual([doc integerForKey: @"number1"], 1u);
        AssertEqual([doc integerForKey: @"number2"], 99u);
        
        AssertEqualObjects([result stringForKey: @"secondaryDocID"], @"joinme");
        AssertEqual([result integerForKey: @"theone"], 42u);
    }];
    AssertEqual(numRows, 1u);
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
