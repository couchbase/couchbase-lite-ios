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
    AssertNil(error);
    
    [self loadJSONResource: @"names_100" toCollection: self.defaultCollection];
    
    [self testQueryCollection: self.defaultCollection
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
     AssertNil(error);

     [self loadJSONResource: @"names_100" toCollection: self.defaultCollection];

     CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult property: @"name.first"]]
                                      from: [CBLQueryDataSource collection: self.defaultCollection]
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

- (void) testSelectAllResultKey {
    NSError* error = nil;
    CBLCollection* flowersCol = [self.db createCollectionWithName: @"flowers" scope: @"test" error: &error];
    AssertNotNil(flowersCol);
    
    CBLMutableDocument* mdoc1 = [self createDocument: @"c1"];
    [mdoc1 setString: @"c1" forKey: @"cid"];
    [mdoc1 setString: @"rose" forKey: @"name"];
    [self saveDocument: mdoc1 collection: flowersCol];
    
    CBLMutableDocument* mdoc2 = [self createDocument: @"c1"];
    [mdoc2 setString: @"c1" forKey: @"cid"];
    [mdoc2 setString: @"rose" forKey: @"name"];
    [self saveDocument: mdoc2 collection: self.defaultCollection];
    
    NSArray<NSString*>* froms = @[
        self.db.name,
        @"_",
        @"_default._default",
        @"test.flowers",
        @"test.flowers as f"
    ];
    
    NSArray<NSString*>* expectedKeyNames = @[
        self.db.name,
        @"_",
        @"_default",
        @"flowers",
        @"f"
    ];
    
    NSUInteger i = 0;
    for (NSString* from in froms) {
        NSString* queryString = [NSString stringWithFormat: @"SELECT * FROM %@", from];
        CBLQuery* query = [self.db createQuery: queryString error: &error];
        AssertNotNil(query);
        CBLQueryResultSet* rs = [query execute: &error];
        AssertNotNil(rs);
        AssertNotNil([rs.allResults.firstObject dictionaryForKey: expectedKeyNames[i++]]);
    }
}

- (void) testFtsWithFtsIndexDefaultCollection {
    NSError* error = nil;
    [self loadJSONResource: @"names_100" toCollection: self.defaultCollection];
    
    CBLMutableDictionary* dict1 = [[CBLMutableDictionary alloc] init];
    [dict1 setValue: @"Jasper" forKey: @"first"];
    [dict1 setValue: @"Grebel" forKey: @"last"];
    
    CBLMutableDictionary* dict2 = [[CBLMutableDictionary alloc] init];
    [dict2 setValue: @"Jasper" forKey: @"first"];
    [dict2 setValue: @"Okorududu" forKey: @"last"];
    
    CBLFullTextIndexConfiguration* config = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"name.first"]
                                                                                        ignoreAccents: NO language: nil];
    Assert([self.defaultCollection createIndexWithName:@"index" config:config error: &error]);

    NSArray<NSString*>* indexs = @[
        @"index",
        @"_.index",
        @"_default.index",
        [NSString stringWithFormat:@"%@.index", self.db.name],
        @"d.index"
    ];
    
    NSArray<NSString*>* froms = @[
        @"_",
        @"_",
        @"_default",
        self.db.name,
    ];

    for (NSUInteger i = 0; i < indexs.count; i++) {
        NSString* queryString= @"";
        if (i != indexs.count - 1){
            queryString = [NSString stringWithFormat: @"SELECT name FROM %1$@ WHERE match(%2$@, 'Jasper') ORDER BY rank(%2$@) ", froms[i], indexs[i]];
        } else {
            queryString = [NSString stringWithFormat: @"SELECT name FROM _ as d WHERE match(%1$@, 'Jasper') ORDER BY rank(%1$@) ", indexs[i]];
        }
        
        CBLQuery* query = [self.db createQuery: queryString error: &error];
        AssertNotNil(query);
        CBLQueryResultSet* rs = [query execute: &error];
        AssertNotNil(rs);
        NSArray* allObjects = rs.allObjects;
        AssertEqual(allObjects.count, 2);
        AssertEqualObjects([allObjects[0] dictionaryForKey: @"name"], dict1);
        AssertEqualObjects([allObjects[1] dictionaryForKey: @"name"], dict2);
    }
}

- (void) testFtsWithFtsIndexNamedCollection {
    NSError* error = nil;
    CBLCollection* peopleCol = [self.db createCollectionWithName: @"people" scope: @"test" error: &error];
    AssertNil(error);

    CBLMutableDocument* mdoc = [self createDocument: @"person1"];
    CBLMutableDictionary* dict1 = [[CBLMutableDictionary alloc] init];
    [dict1 setValue: @"Jasper" forKey: @"first"];
    [dict1 setValue: @"Grebel" forKey: @"last"];
    [mdoc setDictionary: dict1 forKey: @"name"];
    [mdoc setString: @"4" forKey: @"random"];
    [self saveDocument: mdoc collection: peopleCol];

    mdoc = [self createDocument: @"person2"];
    CBLMutableDictionary* dict2 = [[CBLMutableDictionary alloc] init];
    [dict2 setValue: @"Jasper" forKey: @"first"];
    [dict2 setValue: @"Okorududu" forKey: @"last"];
    [mdoc setDictionary: dict2 forKey: @"name"];
    [mdoc setString: @"1" forKey: @"random"];
    [self saveDocument: mdoc collection: peopleCol];

    mdoc = [self createDocument: @"person3"];
    CBLMutableDictionary* dict3 = [[CBLMutableDictionary alloc] init];
    [dict3 setValue: @"Monica" forKey: @"first"];
    [dict3 setValue: @"Polina" forKey: @"last"];
    [mdoc setDictionary: dict3 forKey: @"name"];
    [mdoc setString: @"1" forKey: @"random"];
    [self saveDocument: mdoc collection: peopleCol];


    CBLFullTextIndexConfiguration* config = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"name.first"]
                                                                                        ignoreAccents: NO language: nil];
    Assert([peopleCol createIndexWithName:@"index" config:config error: &error]);

    NSArray<NSString*>* indexs = @[
        @"index",
        @"people.index",
        @"p.index"
    ];

    for (NSString* index in indexs) {
        NSString* queryString= @"";
        if (index != [indexs lastObject]) {
            queryString = [NSString stringWithFormat: @"SELECT name FROM test.people WHERE match(%1$@, 'Jasper') ORDER BY rank(%1$@)", index];
        } else {
            queryString = [NSString stringWithFormat: @"SELECT name FROM test.people as p WHERE match(%1$@, 'Jasper') ORDER BY rank(%1$@)", index];
        }
        CBLQuery* query = [self.db createQuery: queryString error: &error];
        AssertNotNil(query);
        CBLQueryResultSet* rs = [query execute: &error];
        AssertNotNil(rs);
        NSArray* allObjects = rs.allObjects;
        AssertEqual(allObjects.count, 2);
        AssertEqualObjects([allObjects[0] dictionaryForKey: @"name"], dict1);
        AssertEqualObjects([allObjects[1] dictionaryForKey: @"name"], dict2);
    }
}

- (void) testFtsJoinWithCollection {
    NSError* error = nil;
    CBLCollection* flowersCol = [self.db createCollectionWithName: @"flowers" scope: @"test" error: &error];
    AssertNil(error);
    CBLCollection* colorsCol = [self.db createCollectionWithName: @"colors" scope: @"test" error: &error];
    AssertNil(error);
    
    // flowers
    CBLMutableDocument* mdoc = [self createDocument: @"c1"];
    [mdoc setString: @"c1" forKey: @"cid"];
    [mdoc setString: @"rose" forKey: @"name"];
    [mdoc setString: @"Red flowers" forKey: @"description"];
    [self saveDocument: mdoc collection: flowersCol];
    
    mdoc = [self createDocument: @"c2"];
    [mdoc setString: @"c2" forKey: @"cid"];
    [mdoc setString: @"hydrangea" forKey: @"name"];
    [mdoc setString: @"Blue flowers" forKey: @"description"];
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

    CBLFullTextIndexItem* desc = [CBLFullTextIndexItem property: @"description"];
    CBLFullTextIndex* descIndex = [CBLIndexBuilder fullTextIndexWithItems: @[desc]];
    descIndex.ignoreAccents = NO;
    Assert([flowersCol createIndex: descIndex name: @"descIndex" error: &error],
           @"Error when creating fts index: %@", error);
    
    NSString* qStr = @"SELECT f.name, f.description, c.color FROM test.flowers as f JOIN test.colors as c ON f.cid = c.cid WHERE match(f.descIndex, 'red') ORDER BY f.name";
    CBLQuery* q = [self.db createQuery: qStr error: &error];
    AssertNil(error);
    
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 1);
    CBLQueryResult* result = allObjects.firstObject;
    AssertEqualObjects([result stringForKey: @"color"], @"red");
    AssertEqualObjects([result stringForKey: @"description"], @"Red flowers");
    AssertEqualObjects([result stringForKey: @"name"], @"rose");
}

- (void) testQueryBuilderSelectAllResultKey {
    NSError* error = nil;
    
    CBLCollection* flowersCol = [self.db createCollectionWithName: @"flowers" scope: @"test" error: &error];
    AssertNotNil(flowersCol);
    
    CBLMutableDocument* mdoc1 = [self createDocument: @"c1"];
    [mdoc1 setString: @"c1" forKey: @"cid"];
    [mdoc1 setString: @"rose" forKey: @"name"];
    [self saveDocument: mdoc1 collection: flowersCol];
    
    CBLMutableDocument* mdoc2 = [self createDocument: @"c1"];
    [mdoc2 setString: @"c1" forKey: @"cid"];
    [mdoc2 setString: @"rose" forKey: @"name"];
    [self saveDocument: mdoc2 collection: self.defaultCollection];
    
    NSArray<CBLQueryDataSource*>* froms = @[
        [CBLQueryDataSource collection: self.defaultCollection],
        [CBLQueryDataSource collection: flowersCol],
        [CBLQueryDataSource collection: flowersCol as: @"f"]
    ];
    
    NSArray<NSString*>* expectedKeyNames = @[
        @"_default",
        @"flowers",
        @"f"
    ];
    
    NSUInteger i = 0;
    for (CBLQueryDataSource* from in froms) {
        CBLQuery* query = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: from];
        AssertNotNil(query);
        CBLQueryResultSet* rs = [query execute: &error];
        AssertNotNil(rs);
        AssertNotNil([rs.allResults.firstObject dictionaryForKey: expectedKeyNames[i++]]);
    }
}

@end
