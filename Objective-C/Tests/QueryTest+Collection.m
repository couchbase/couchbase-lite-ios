//
//  QueryTest_Collection.m
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

@interface QueryTest_Collection : QueryTest

@end

@implementation QueryTest_Collection

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark -

- (void) testQueryDefaultCollection {
    NSError* error = nil;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    AssertNil(error);
    
    [self loadJSONResource: @"names_100" toCollection: defaultCollection];
    
    [self testQueryCollection: defaultCollection
                      queries: @[@"SELECT name.first FROM _ ORDER BY name.first LIMIT 1",
                                 @"SELECT name.first FROM _default ORDER BY name.first limit 1",
                                 @"SELECT name.first FROM testdb ORDER BY name.first limit 1"]];
    
    
}

- (void) testQueryDefaultScope {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"names" scope: nil error: &error];
    AssertNil(error);
    
    [self testQueryCollection: col
                      queries: @[
        /* @"SELECT name.first FROM _default.names ORDER BY name.first LIMIT 1", NOT WORKING! */
        @"SELECT name.first FROM names ORDER BY name.first LIMIT 1"
    ]];
}

- (void) testQueryCollection {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"names" scope: @"people" error: &error];
    AssertNil(error);
    
    [self testQueryCollection: col
                      queries: @[
        @"SELECT name.first FROM people.names ORDER BY name.first LIMIT 1"
    ]];
}

- (void) testQueryCollection: (CBLCollection*)collection queries: (NSArray*)queries {
    [self loadJSONResource: @"names_100" toCollection: collection];
    
    NSError* error = nil;
    for (NSString* str in queries) {
        CBLQuery* q = [self.db createQuery: str error: &error];
        AssertNil(error);
        CBLQueryResultSet* rs = [q execute: &error];
        NSArray* allObjects = rs.allObjects;
        
        AssertEqual(allObjects.count, 1);
        CBLQueryResult* result = allObjects.firstObject;
        AssertEqualObjects([result stringForKey: @"first"], @"Abe");
    }
}

#pragma mark -

- (void) testQueryInvalidCollection {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"names" scope: @"people" error: &error];
    AssertNil(error);
    
    [self loadJSONResource: @"names_100" toCollection: col];
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidQuery in: ^BOOL(NSError** err) {
        return [self.db createQuery: @"SELECT name.first FROM person.names ORDER BY name.first LIMIT 1"
                              error: err] != nil;
    }];
}

- (void) testJoinWithCollections {
    NSError* error = nil;
    CBLCollection* flowersCol = [self.db createCollectionWithName: @"flowers" scope: @"test" error: &error];
    AssertNil(error);
    CBLCollection* colorsCol = [self.db createCollectionWithName: @"colors" scope: @"test" error: &error];
    AssertNil(error);
    
    // flowers
    CBLMutableDocument* mdoc = [self createDocument: @"c1"];
    [mdoc setString: @"c1" forKey: @"cid"];
    [mdoc setString: @"rose" forKey: @"name"];
    [self saveDocument: mdoc collection: flowersCol];
    
    mdoc = [self createDocument: @"c2"];
    [mdoc setString: @"c2" forKey: @"cid"];
    [mdoc setString: @"hydrangea" forKey: @"name"];
    [self saveDocument: mdoc collection: flowersCol];
    
    // colors
    mdoc = [self createDocument: @"c1"];
    [mdoc setString: @"c1" forKey: @"cid"];
    [mdoc setString: @"red" forKey: @"color"];
    [self saveDocument: mdoc collection: colorsCol];
    
    mdoc = [self createDocument: @"c2"];
    [mdoc setString: @"c2" forKey: @"cid"];
    [mdoc setString: @"blue" forKey: @"color"];
    [self saveDocument: mdoc collection: colorsCol];
    
    mdoc = [self createDocument: @"c3"];
    [mdoc setString: @"c3" forKey: @"cid"];
    [mdoc setString: @"white" forKey: @"color"];
    [self saveDocument: mdoc collection: colorsCol];
    
    NSString* qStr = @"SELECT a.name, b.color FROM test.flowers a JOIN test.colors b ON a.cid = b.cid ORDER BY a.name";
    CBLQuery* q = [self.db createQuery: qStr error: &error];
    AssertNil(error);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    
    AssertEqual(allObjects.count, 2);
    AssertEqualObjects([allObjects[0] stringForKey: @"name"], @"hydrangea");
    AssertEqualObjects([allObjects[0] stringForKey: @"color"], @"blue");
    AssertEqualObjects([allObjects[1] stringForKey: @"name"], @"rose");
    AssertEqualObjects([allObjects[1] stringForKey: @"color"], @"red");
}

- (void) testQueryBuilderWithDefaultCollectionAsDataSource {
     NSError* error = nil;
     CBLCollection* defaultCollection = [self.db defaultCollection: &error];
     AssertNil(error);

     [self loadJSONResource: @"names_100" toCollection: defaultCollection];

     CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult property: @"name.first"]]
                                      from: [CBLQueryDataSource collection: defaultCollection]
                                     where: nil
                                   groupBy: nil
                                    having: nil
                                   orderBy: @[[[CBLQueryOrdering property: @"name.first"] ascending]]
                                     limit: [CBLQueryLimit limit: [CBLQueryExpression integer: 1]]];
     CBLQueryResultSet* rs = [q execute: &error];
     NSArray* allObjects = rs.allObjects;

     AssertEqual(allObjects.count, 1);
     CBLQueryResult* result = allObjects.firstObject;
     AssertEqualObjects([result stringForKey: @"first"], @"Abe");
 }

- (void) testQueryBuilderWithCollectionAsDataSource {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"names" scope: @"people" error: &error];
    AssertNil(error);
    
    [self loadJSONResource: @"names_100" toCollection: col];
    
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult property: @"name.first"]]
                                     from: [CBLQueryDataSource collection: col]
                                    where: nil
                                  groupBy: nil
                                   having: nil
                                  orderBy: @[[[CBLQueryOrdering property: @"name.first"] ascending]]
                                    limit: [CBLQueryLimit limit: [CBLQueryExpression integer: 1]]];
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;

    AssertEqual(allObjects.count, 1);
    CBLQueryResult* result = allObjects.firstObject;
    AssertEqualObjects([result stringForKey: @"first"], @"Abe");
}

@end
