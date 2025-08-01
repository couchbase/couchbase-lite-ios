//
//  PartialIndexTest.m
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLTestCase.h"

/**
 Test Spec v1.0.3:
 https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0007-Partial-Index.md
 */

@interface PartialIndexTest : CBLTestCase

@end

@implementation PartialIndexTest

/**
 * 1. TestCreatePartialValueIndex
 *
 * Description
 * Test that a partial value index is successfully created.
 *
 * Steps
 * 1. Create a partial value index named "numIndex" in the default collection.
 *     - expression: "num"
 *     - where: "type = 'number'"
 * 2. Check that the index is successfully created.
 * 3. Create a query object with an SQL++ string:
 *     - SELECT *
 *       FROM _
 *       WHERE type = 'number' AND num > 1000
 * 4. Get the query plan from the query object and check that the plan contains "USING INDEX numIndex" string.
 * 5. Create a query object with an SQL++ string:
 *     - SELECT *
 *       FROM _
 *       WHERE type = 'foo' AND num > 1000
 * 6. Get the query plan from the query object and check that the plan doesn't contain "USING INDEX numIndex" string.
 */
- (void) testCreatePartialValueIndex {
    NSError* error;
    CBLCollection* collection = [self.db defaultCollection: &error];

    CBLValueIndexConfiguration* config = [[CBLValueIndexConfiguration alloc] initWithExpression: @[@"num"] where: @"type='number'"];
    Assert([collection createIndexWithName: @"numIndex" config: config error: nil]);
    
    NSString* sql = @"SELECT * FROM _ WHERE type = 'number' AND num > 1000";
    CBLQuery* q = [_db createQuery: sql error: &error];
    AssertNotNil(q);
    Assert([self isUsingIndexNamed: @"numIndex" forQuery: q]);
    
    sql = @"SELECT * FROM _ WHERE type = 'foo' AND num > 1000";
    q = [_db createQuery: sql error: &error];
    AssertFalse([self isUsingIndexNamed: @"numIndex" forQuery: q]);
}

/**
 * 2. TestCreatePartialFullTextIndex
 *
 * Description
 * Test that a partial full text index is successfully created.
 *
 * Steps
 * 1. Create following two documents with the following bodies in the default collection.
 *     - { "content" : "Couchbase Lite is a database." }
 *     - { "content" : "Couchbase Lite is a NoSQL syncable database." }
 * 2. Create a partial full text index named "contentIndex" in the default collection.
 *     - expression: "content"
 *     - where: "length(content) > 30"
 * 3. Check that the index is successfully created.
 * 4. Create a query object with an SQL++ string:
 *     - SELECT content
 *       FROM _
 *       WHERE match(contentIndex, "database")
 * 4. Execute the query and check that:
 *     - The query returns the second document.
 * 5. Create a query object with an SQL++ string:
 *     - There is one result returned
 *     - The returned content is "Couchbase Lite is a NoSQL syncable database.".
 */
- (void) testCreatePartialFullTextIndex {
    NSError* error;
    CBLCollection* collection = [self.db defaultCollection: &error];
    NSString* json1 = @"{\"content\":\"Couchbase Lite is a database.\"}";
    NSString* json2 = @"{\"content\":\"Couchbase Lite is a NoSQL syncable database.\"}";
    
    [collection saveDocument:[[CBLMutableDocument alloc] initWithJSON:json1 error:&error]
                       error:&error];
    
    [collection saveDocument:[[CBLMutableDocument alloc] initWithJSON:json2 error:&error]
                       error:&error];

    CBLFullTextIndexConfiguration* config = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"content"]
                                                                                                where: @"length(content)>30"
                                                                                        ignoreAccents: false
                                                                                             language: nil];
    Assert([collection createIndexWithName: @"contentIndex" config: config error: nil]);
    
    NSString* sql = @"SELECT content FROM _ WHERE match(contentIndex, 'database')";
    CBLQuery* q = [_db createQuery: sql error: &error];
    AssertNotNil(q);
    NSArray* results = [[q execute: &error] allResults];
    AssertEqual(results.count, 1);
    AssertEqualObjects([results[0] toJSON], json2);
}

@end
