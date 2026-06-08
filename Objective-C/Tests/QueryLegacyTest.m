//
//  QueryLegacyTest.m
//  CouchbaseLite
//
//  Copyright (c) 2026 Couchbase, Inc All rights reserved.
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

/**
 Minimal smoke tests for the deprecated Query APIs:
 - CBLQueryDataSource +database: / +database:as:
 - CBLQueryExpression -isNullOrMissing / -notNullOrMissing
 - CBLQueryFullTextFunction +rank: / +matchWithIndexName:query:
 - CBLQueryFullTextExpression +indexWithName: / -match:

 The goal is only to touch each deprecated entry point and confirm its basic
 behavior, NOT to re-cover the full query test suites (which now use the
 collection-based / non-deprecated APIs).
 */
@interface QueryLegacyTest : QueryTest
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation QueryLegacyTest

// MARK: - CBLQueryDataSource +database: / +database:as:

- (void) testDataSourceDatabaseAndAlias {
    CBLMutableDocument* doc1 = [self createDocument: @"doc1"];
    [doc1 setValue: @"Scott" forKey: @"name"];
    [self saveDocument: doc1 collection: self.defaultCollection];

    CBLMutableDocument* doc2 = [self createDocument: @"doc2"];
    [doc2 setValue: @"Tiger" forKey: @"name"];
    [self saveDocument: doc2 collection: self.defaultCollection];

    // +database:
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r) { }];
    AssertEqual(numRows, 2u);

    // +database:as:
    CBLQuery* aliased = [CBLQueryBuilder select: @[kDOCID]
                                           from: [CBLQueryDataSource database: self.db as: @"main"]];
    numRows = [self verifyQuery: aliased randomAccess: YES
                           test: ^(uint64_t n, CBLQueryResult* r) { }];
    AssertEqual(numRows, 2u);
}

// MARK: - CBLQueryExpression -isNullOrMissing / -notNullOrMissing

- (void) testIsNullOrMissing {
    CBLMutableDocument* doc1 = [self createDocument: @"doc1"];
    [doc1 setValue: @"Scott" forKey: @"name"];
    [doc1 setValue: nil forKey: @"address"];
    [self saveDocument: doc1 collection: self.defaultCollection];

    CBLMutableDocument* doc2 = [self createDocument: @"doc2"];
    [doc2 setValue: @"Tiger" forKey: @"name"];
    [doc2 setValue: @"123 1st ave." forKey: @"address"];
    [self saveDocument: doc2 collection: self.defaultCollection];

    CBLQueryExpression* name = [CBLQueryExpression property: @"name"];
    CBLQueryExpression* address = [CBLQueryExpression property: @"address"];

    NSArray* tests = @[
        @[[name isNullOrMissing],     @0],
        @[[name notNullOrMissing],    @2],
        @[[address isNullOrMissing],  @1],
        @[[address notNullOrMissing], @1],
    ];

    for (NSArray* test in tests) {
        CBLQueryExpression* exp = test[0];
        NSUInteger expected = [test[1] unsignedIntegerValue];
        CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                         from: kDATA_SRC_DB
                                        where: exp];
        uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                        test: ^(uint64_t n, CBLQueryResult* r) { }];
        AssertEqual((NSUInteger)numRows, expected, @"Failed case: %@", exp);
    }
}

// MARK: - CBLQueryFullTextFunction +rank: / +matchWithIndexName:query:

- (void) testFullTextFunctionDeprecatedRankAndMatch {
    [self loadJSONResource: @"sentences"];

    CBLQuerySelectResult* S_SENTENCE = [CBLQuerySelectResult property: @"sentence"];

    NSError* error;
    CBLFullTextIndex* index = [CBLIndexBuilder fullTextIndexWithItems: @[[CBLFullTextIndexItem property: @"sentence"]]];
    Assert([self.defaultCollection createIndex: index name: @"sentence" error: &error],
           @"Error when creating the index: %@", error);

    CBLQueryExpression* where = [CBLQueryFullTextFunction matchWithIndexName: @"sentence" query: @"'Dummie woman'"];
    CBLQueryOrdering* order = [[CBLQueryOrdering expression: [CBLQueryFullTextFunction rank: @"sentence"]]
                               descending];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID, S_SENTENCE]
                                     from: kDATA_SRC_DB
                                    where: where
                                  orderBy: @[order]];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r) { }];
    AssertEqual(numRows, 2u);
}

// MARK: - CBLQueryFullTextExpression +indexWithName: / -match:

- (void) testFullTextExpression {
    [self loadJSONResource: @"sentences"];

    CBLQueryFullTextExpression* SENTENCE = [CBLQueryFullTextExpression indexWithName: @"sentence"];
    CBLQuerySelectResult* S_SENTENCE = [CBLQuerySelectResult property: @"sentence"];

    NSError* error;
    CBLFullTextIndex* index = [CBLIndexBuilder fullTextIndexWithItems: @[[CBLFullTextIndexItem property: @"sentence"]]];
    Assert([self.defaultCollection createIndex: index name: @"sentence" error: &error],
           @"Error when creating the index: %@", error);

    CBLQueryExpression* where = [SENTENCE match: @"'Dummie woman'"];
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID, S_SENTENCE]
                                     from: kDATA_SRC_DB
                                    where: where];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult* r) { }];
    AssertEqual(numRows, 2u);
}

// MARK: - CBLQuery -removeChangeListenerWithToken:

- (void) testRemoveQueryChangeListenerWithToken {
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID] from: kDATA_SRC_DB];

    XCTestExpectation* x = [self expectationWithDescription: @"query change"];
    x.assertForOverFulfill = NO;
    id<CBLListenerToken> token = [q addChangeListener: ^(CBLQueryChange* change) {
        AssertNil(change.error);
        [x fulfill];
    }];
    [self waitForExpectations: @[x] timeout: 5.0];

    // Remove using the deprecated API; should not crash.
    [q removeChangeListenerWithToken: token];
}

@end

#pragma clang diagnostic pop
