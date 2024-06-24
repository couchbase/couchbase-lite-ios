//
//  CollectionTest.m
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

#import "CBLTestCase.h"

@interface CollectionTest : CBLTestCase

@end

@implementation CollectionTest

- (void) setUp {
    [super setUp];
}

- (void) tearDown {
    [super tearDown];
}

- (void) testGetNonExistingDoc {
    NSError* error = nil;
    CBLCollection* col = [self.db defaultCollection: &error];
    AssertNil(error);
    
    CBLDocument* doc = [col documentWithID: @"nonExisting" error: &error];
    AssertNil(error);
    AssertNil(doc);
}

#pragma mark - Default Scope/Collection

- (void) testDefaultCollectionExists {
    NSError* error = nil;
    CBLCollection* col = [self.db defaultCollection: &error];
    AssertNotNil(col, @"default collection shouldn't be empty");
    AssertEqualObjects(col.name, kCBLDefaultCollectionName);
    AssertNil(error);
    
    NSArray* cols = [self.db collections: nil error: &error];
    Assert([cols containsObject: col]);
    AssertNil(error);
    
    CBLScope* scope = col.scope;
    AssertNotNil(scope, @"default scope shouldn't be empty");
    AssertEqualObjects(scope.name, kCBLDefaultScopeName);
    
    CBLCollection* col1 = [self.db collectionWithName: kCBLDefaultCollectionName
                                                scope: nil error: &error];
    AssertEqualObjects(col, col1);
    AssertNil(error);
    
    scope = col1.scope;
    AssertNotNil(scope, @"default scope shouldn't be empty");
    AssertEqualObjects(scope.name, kCBLDefaultScopeName);
}

- (void) testDefaultScopeExists {
    NSError* error = nil;
    CBLScope* scope = [self.db defaultScope: &error];
    AssertNotNil(scope, @"Default scope shouldn't be empty");
    AssertEqualObjects(scope.name, kCBLDefaultScopeName);
    AssertNil(error);
    
    NSArray<CBLScope*>* scopes = [self.db scopes: &error];
    AssertEqual(scopes.count, 1);
    AssertEqualObjects(scopes[0].name, kCBLDefaultScopeName);
    AssertNil(error);
    
    CBLScope* scope1 = [self.db scopeWithName: kCBLDefaultScopeName error: &error];
    AssertNotNil(scope1, @"Scope shouldn't be empty");
    AssertEqualObjects(scope1.name, kCBLDefaultScopeName);
    AssertNil(error);
}

- (void) testDeleteDefaultCollection {
    // exception 
    [self ignoreException: ^{
        NSError* err = nil;
        AssertFalse([self.db deleteCollectionWithName: kCBLDefaultCollectionName scope: nil error: &err]);
        AssertEqual(err.code, CBLErrorInvalidParameter);
        AssertEqual(err.domain, CBLErrorDomain);
    }];
    
    NSError* error = nil;
    CBLCollection* col = [self.db defaultCollection: &error];
    AssertNotNil(col);
    AssertEqualObjects(col.name, kCBLDefaultCollectionName);
    AssertEqualObjects(col.scope.name, kCBLDefaultScopeName);
    
    // try to create the default collection
    col = [self.db createCollectionWithName: kCBLDefaultCollectionName scope: nil error: &error];
    AssertNotNil(col);
    AssertEqualObjects(col.name, kCBLDefaultCollectionName);
    AssertEqualObjects(col.scope.name, kCBLDefaultScopeName);
}

- (void) testGetDefaultScopeAfterDeleteDefaultCollection {
    // delete the default collection
    
    [self ignoreException: ^{
        NSError* err = nil;
        AssertFalse([self.db deleteCollectionWithName: kCBLDefaultCollectionName scope: nil error: &err]);
        AssertEqual(err.code, CBLErrorInvalidParameter);
        AssertEqual(err.domain, CBLErrorDomain);
    }];
    
    // make sure scope exists
    NSError* error = nil;
    CBLScope* scope = [self.db defaultScope: &error];
    AssertNotNil(scope, @"Default scope shouldn't be empty");
    AssertEqualObjects(scope.name, kCBLDefaultScopeName);
    AssertNil(error);
    
    NSArray* cols = [scope collections: &error];
    AssertEqual(cols.count, 1);
    AssertNil(error);
    
    NSArray<CBLScope*>* scopes = [self.db scopes: &error];
    AssertEqual(scopes.count, 1);
    AssertEqualObjects(scopes[0].name, kCBLDefaultScopeName);
    AssertNil(error);
    
    cols = [self.db collections: kCBLDefaultScopeName error: &error];
    AssertEqual(cols.count, 1);
    AssertNil(error);
}

#pragma mark - 8.2 Collections

- (void) testCreateAndGetCollectionsInDefaultScope {
    NSError* error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA"
                                                      scope: nil error: &error];
    AssertNil(error);
    
    CBLCollection* colB = [self.db createCollectionWithName: @"colB"
                                                      scope: kCBLDefaultScopeName error: &error];
    AssertNil(error);
    
    // created collection objects have the correct name and scope
    AssertEqualObjects(colA.name, @"colA");
    AssertEqualObjects(colA.scope.name, kCBLDefaultScopeName);
    AssertEqualObjects(colB.name, @"colB");
    AssertEqualObjects(colB.scope.name, kCBLDefaultScopeName);
    
    // created collections exist when calling database.collectionWithName:
    CBLCollection* colAa = [self.db collectionWithName: @"colA" scope: nil error: &error];
    AssertEqualObjects(colA.name, colAa.name);
    AssertEqualObjects(colA.scope.name, colAa.scope.name);
    AssertNil(error);
    
    CBLCollection* colBa = [self.db collectionWithName: @"colB"
                                                 scope: kCBLDefaultScopeName
                                                 error: &error];
    AssertEqualObjects(colB.name, colBa.name);
    AssertEqualObjects(colB.scope.name, colBa.scope.name);
    AssertNil(error);
    
    NSArray<CBLCollection*>* collections = [self.db collections: nil error: &error];
    AssertEqual(collections.count, 3);
    Assert([(@[@"colA", @"colB", @"_default"]) containsObject: collections[0].name]);
    Assert([(@[@"colA", @"colB", @"_default"]) containsObject: collections[1].name]);
    Assert([(@[@"colA", @"colB", @"_default"]) containsObject: collections[2].name]);
    AssertNil(error);
}

- (void) testCreateAndGetCollectionsInNamedScope {
    NSError* error = nil;
    AssertNil([self.db scopeWithName: @"scopeA" error: &error]);
    AssertNil(error);
    
    error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertEqualObjects(colA.name, @"colA");
    AssertEqualObjects(colA.scope.name, @"scopeA");
    AssertNil(error);
    
    CBLScope* scopeA = [self.db scopeWithName: @"scopeA" error: &error];
    AssertNotNil(scopeA);
    AssertEqualObjects(colA.scope, scopeA);
    AssertEqualObjects(scopeA.name, @"scopeA");
    AssertNil(error);
    
    colA = [self.db collectionWithName: @"colA"
                                 scope: @"scopeA" error: &error];
    AssertEqualObjects(colA.name, @"colA");
    AssertEqualObjects(colA.scope, scopeA);
    AssertEqualObjects(colA.scope.name, @"scopeA");
    AssertNil(error);
    
    NSArray<CBLScope*>* scopes = [self.db scopes: &error];
    AssertEqual(scopes.count, 2);
    Assert([(@[@"scopeA", kCBLDefaultScopeName]) containsObject: scopes[0].name]);
    Assert([(@[@"scopeA", kCBLDefaultScopeName]) containsObject: scopes[1].name]);
    AssertNil(error);
}

- (void) testCreateAnExistingCollection {
    NSError* error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertNotNil(colA);
    AssertNil(error);
    
    CBLMutableDocument* d = [CBLMutableDocument documentWithID: @"doc1"];
    [d setString: @"string" forKey: @"someKey"];
    [colA saveDocument: d error: &error];
    AssertNil(error);
    
    CBLCollection* colA2 = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertNotNil(colA2);
    AssertEqualObjects(colA, colA2);
    AssertNil(error);
    
    CBLDocument* doc1 = [colA2 documentWithID: @"doc1" error: &error];
    AssertNotNil(doc1);
    AssertNil(error);
}

- (void) testGetNonExistingCollection {
    NSError* error = nil;
    AssertNil([self.db collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil(error);
}

- (void) testDeleteCollection {
    NSError* error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertNotNil(colA);
    AssertNil(error);
    
    // create some docs
    [self createDocNumbered: colA start: 0 num: 10];
    AssertEqual(colA.count, 10);
    
    // delete & verify its deleted
    Assert([self.db deleteCollectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil([self.db collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    NSArray* cols = [self.db collections: @"scopeA" error: &error];
    AssertEqual(cols.count, 0);
    
    // recreate
    CBLCollection* colA2 = [self.db createCollectionWithName: @"colA"
                                       scope: @"scopeA" error: &error];
    AssertNotNil(colA2);
    AssertEqualObjects(colA2.name, @"colA");
    AssertEqualObjects(colA2.scope.name, @"scopeA");
    
    // make sure, new collection is empty and not equal
    AssertEqual(colA2.count, 0);
    AssertNotEqualObjects(colA2, colA);
}

- (void) testGetCollectionsFromScope {
    NSError* error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertNotNil(colA);
    AssertNil(error);
    CBLCollection* colB = [self.db createCollectionWithName: @"colB"
                                                      scope: @"scopeA" error: &error];
    AssertNotNil(colB);
    AssertNil(error);
    
    CBLScope* scope = [self.db scopeWithName: @"scopeA" error: &error];
    AssertNil(error);
    CBLCollection* col = [scope collectionWithName: @"colA" error: &error];
    AssertEqualObjects(col, colA);
    AssertNil(error);
    col = [scope collectionWithName: @"colB" error: &error];
    AssertEqualObjects(col, colB);
    AssertNil(error);
    
    AssertNil([scope collectionWithName: @"colC" error: &error]);
    AssertNil(error);
    
    error = nil;
    NSArray<CBLCollection*>* cols = [self.db collections: @"scopeA" error: &error];
    AssertEqual(cols.count, 2);
    Assert([(@[@"colA", @"colB"]) containsObject: cols[0].name]);
    Assert([(@[@"colA", @"colB"]) containsObject: cols[1].name]);
    AssertNil(error);
}

- (void) testDeleteAllCollectionsInScope {
    NSError* error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertNotNil(colA);
    AssertNil(error);
    CBLCollection* colB = [self.db createCollectionWithName: @"colB"
                                                      scope: @"scopeA" error: &error];
    AssertNotNil(colB);
    AssertNil(error);
    
    CBLScope* scopeA = [self.db scopeWithName: @"scopeA" error: &error];
    AssertNil(error);
    NSArray<CBLCollection*>* collectionsInScopeA = [scopeA collections: &error];
    AssertEqual(collectionsInScopeA.count, 2);
    Assert([(@[@"colA", @"colB"]) containsObject: collectionsInScopeA[0].name]);
    Assert([(@[@"colA", @"colB"]) containsObject: collectionsInScopeA[1].name]);
    AssertNil(error);
    
    // delete collections in the scope
    [self.db deleteCollectionWithName: @"colA" scope: @"scopeA" error: &error];
    collectionsInScopeA = [scopeA collections: &error];
    AssertEqual(collectionsInScopeA.count, 1);
    AssertNil(error);
    [self.db deleteCollectionWithName: @"colB" scope: @"scopeA" error: &error];
    AssertNil(error);
    
    // make sure scope doesn't exist
    AssertNil([self.db scopeWithName: @"scopeA" error: &error]);
    AssertNil(error);
    
    // make sure, collections return NotFound error
    AssertNil([self.db collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil(error);
    
    AssertNil([self.db collectionWithName: @"colB" scope: @"scopeA" error: &error]);
    AssertNil(error);
}

- (void) testScopeCollectionNameWithValidChars {
    NSArray* names = @[@"a",
                       @"A",
                       @"0", @"-",
                       @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_%"];
    
    for (NSString* name in names) {
        NSError* error = nil;
        CBLCollection* col1 = [self.db createCollectionWithName: name
                                                          scope: name error: &error];
        AssertNotNil(col1);
        AssertNil(error);
        
        CBLCollection* col2 = [self.db collectionWithName: name scope: name error: &error];
        AssertNotNil(col2);
        AssertNil(error);
        
        AssertEqualObjects(col1, col2);
    }
}

- (void) testScopeCollectionNameWithIllegalChars {
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
        return  [self.db createCollectionWithName: @"_a" scope: nil error: e] != nil;
    }];
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
        return  [self.db createCollectionWithName: @"a" scope: @"_a" error: e] != nil;
    }];
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
        return  [self.db createCollectionWithName: @"%a" scope: nil error: e] != nil;
    }];
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
        return  [self.db createCollectionWithName: @"b" scope: @"%b" error: e] != nil;
    }];
    
    NSString* invalidChars = @"!@#$^&*()+={}[]<>,.?/:;\"'\\|`~";
    for (NSUInteger i = 0; i < invalidChars.length; i++) {
        unichar c = [invalidChars characterAtIndex: i];
        NSString* name = [NSString stringWithFormat: @"a%cz", c];
        [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
            return  [self.db createCollectionWithName: name scope: nil error: e] != nil;
        }];
        
        [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
            return  [self.db createCollectionWithName: @"colA" scope: name error: e] != nil;
        }];
    }
}

- (void) testScopeCollectionNameLength {
    NSMutableArray* names = [NSMutableArray array];
    NSMutableString* name = [NSMutableString string];
    for (NSUInteger i = 0; i < 251; i++) {
        [name appendString: @"a"];
        if (i%4==0) // without this, test might take ~20secs to finish
            [names addObject: name];
    }
    
    NSError* error = nil;
    for (NSString* n in names) {
        CBLCollection* col = [self.db createCollectionWithName: n scope: n error: &error];
        AssertNotNil(col);
        AssertEqualObjects(col.name, n);
        AssertEqualObjects(col.scope.name, n);
        AssertNil(error);
    }
    
    CBLCollection* col = [self.db createCollectionWithName: name scope: name error: &error];
    AssertNotNil(col);
    AssertEqualObjects(col.name, name);
    AssertEqualObjects(col.scope.name, name);
    
    [name appendString: @"a"];
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in: ^BOOL(NSError** er) {
        return [self.db createCollectionWithName: name scope: @"scopeA" error: er] != nil;
    }];
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in: ^BOOL(NSError** er) {
        return [self.db createCollectionWithName: @"colA" scope: name error: er] != nil;
    }];
    
}

- (void) testCollectionNameCaseSensitive {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"COLLECTION1"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"collection1"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    AssertNotEqualObjects(col1a, col1b);
    AssertEqualObjects(col1a.name, @"COLLECTION1");
    AssertEqualObjects(col1b.name, @"collection1");
    
    NSArray<CBLCollection*>* cols = [self.db collections: @"scopeA" error: &error];
    AssertEqual(cols.count, 2);
    Assert([(@[@"COLLECTION1", @"collection1"]) containsObject: cols[0].name]);
    Assert([(@[@"COLLECTION1", @"collection1"]) containsObject: cols[1].name]);
}

- (void) testScopeNameCaseSensitive {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1aa = [self.db createCollectionWithName: @"colA"
                                                       scope: @"SCOPEa" error: &error];
    AssertNotNil(col1aa);
    AssertNil(error);
    
    AssertEqualObjects(col1a.scope.name, @"scopeA");
    AssertEqualObjects(col1aa.scope.name, @"SCOPEa");
    AssertNotEqualObjects(col1a, col1aa);
    
    NSArray<CBLScope*>* scopes = [self.db scopes: &error];
    AssertEqual(scopes.count, 3);
    Assert([(@[@"scopeA", @"SCOPEa", kCBLDefaultScopeName]) containsObject: scopes[0].name]);
    Assert([(@[@"scopeA", @"SCOPEa", kCBLDefaultScopeName]) containsObject: scopes[1].name]);
}

#pragma mark - Collection Full Name

// Spec: https://docs.google.com/document/d/1nUgaCgXIB3lLViudf6Pw6H9nPa_OeYU6uM_9xAd08M0

- (void) testCollectionFullName {
    NSError* error;
    
    // 3.1 TestGetFullNameFromDefaultCollection
    CBLCollection* col1 = [self.db defaultCollection: &error];
    AssertNotNil(col1);
    AssertEqualObjects(col1.fullName, @"_default._default");
    
    // 3.2 TestGetFullNameFromNewCollectionInDefaultScope
    CBLCollection* col2 = [self.db createCollectionWithName: @"colA" scope: nil error: &error];
    AssertNotNil(col2);
    AssertEqualObjects(col2.fullName, @"_default.colA");
    
    // 3.3 TestGetFullNameFromNewCollectionInCustomScope
    CBLCollection* col3 = [self.db createCollectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertNotNil(col3);
    AssertEqualObjects(col3.fullName, @"scopeA.colA");
    
    // 3.4 TestGetFullNameFromExistingCollectionInDefaultScope
    CBLCollection* col4 = [self.db collectionWithName: @"colA" scope: nil error: &error];
    AssertNotNil(col4);
    AssertEqualObjects(col4.fullName, @"_default.colA");
    
    // 3.5 TestGetFullNameFromNewCollectionInCustomScope
    CBLCollection* col5 = [self.db collectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertNotNil(col5);
    AssertEqualObjects(col5.fullName, @"scopeA.colA");
}

#pragma mark - Collection and Scope Database

// Spec: https://docs.google.com/document/d/1kA78r1aRbbaJVepseSjdzqxgCQjjC5NWU449O3l33U8

- (void) testCollectionDatabase {
    NSError* error;
        
    // 3.1 TestGetDatabaseFromNewCollection
    CBLCollection* col1 = [self.db createCollectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertNotNil(col1);
    AssertEqual(col1.database, self.db);
    
    // 3.2 TestGetDatabaseFromExistingCollection
    CBLCollection* col2 = [self.db collectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertNotNil(col2);
    AssertEqual(col2.database, self.db);
}

- (void) testScopeDatabase {
    NSError* error;
        
    // 3.3 TestGetDatabaseFromScopeObtainedFromCollection
    CBLCollection* col1 = [self.db createCollectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertNotNil(col1);
    AssertEqual(col1.scope.database, self.db);
    
    // 3.4 TestGetDatabaseFromScopeObtainedFromDatabase
    CBLScope* scope = [self.db scopeWithName: @"scopeA" error: &error];
    AssertNotNil(scope);
    AssertEqual(scope.database, self.db);
}

#pragma mark - 8.3 Collections and Cross Database Instance

- (void) testCreateThenGetCollectionFromDifferentDatabaseInstance {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"colA"
                                                     scope: @"scopeA" error: &error];
    
    [self createDocNumbered: col start: 0 num: 10];
    AssertEqual(col.count, 10);
    AssertNil(error);
    
    CBLDatabase* db2 = [self openDBNamed: kDatabaseName error: &error];
    CBLCollection* col2 = [db2 createCollectionWithName: @"colA"
                                                  scope: @"scopeA" error: &error];
    AssertEqualObjects(col, col2);
    AssertEqual(col2.count, 10);
    AssertNil(error);
    
    AssertEqual([self.db collections: @"scopeA" error: &error].count, 1);
    AssertNil(error);
    AssertEqual([db2 collections: @"scopeA" error: &error].count, 1);
    AssertNil(error);
    
    [self createDocNumbered: col start: 10 num: 10];
    AssertEqual(col.count, 20);
    AssertEqual(col2.count, 20);
}

- (void) testDeleteThenGetCollectionFromDifferentDatabaseInstance {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"colA"
                                                     scope: @"scopeA" error: &error];
    
    [self createDocNumbered: col start: 0 num: 10];
    AssertEqual(col.count, 10);
    AssertNil(error);
    
    CBLDatabase* db2 = [self openDBNamed: kDatabaseName error: &error];
    AssertNil(error);
    CBLCollection* col2 = [db2 collectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertNil(error);
    AssertEqualObjects(col, col2);
    
    Assert([self.db deleteCollectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertEqual(col.count, 0);
    AssertEqual(col2.count, 0);
    AssertNil(error);
    
    AssertNil([self.db collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil(error);
    AssertNil([db2 collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil(error);
}

- (void) testDeleteAndRecreateThenGetCollectionFromDifferentDatabaseInstance {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"colA"
                                                     scope: @"scopeA" error: &error];
    
    [self createDocNumbered: col start: 0 num: 10];
    AssertEqual(col.count, 10);
    AssertNil(error);
    
    CBLDatabase* db2 = [self openDBNamed: kDatabaseName error: &error];
    AssertNil(error);
    CBLCollection* col2 = [db2 collectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertEqual(col2.count, 10);
    AssertNil(error);
    
    // make sure both instances are same
    AssertEqualObjects(col, col2);
    
    // Delete the collection from db:
    Assert([self.db deleteCollectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil(error);
    
    AssertNil([self.db collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil(error);
    
    error = nil;
    AssertNil([db2 collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil(error);
    
    // Recreate:
    error = nil;
    CBLCollection* col3 = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertEqual(col3.count, 0);
    AssertNil(error);
    
    [self createDocNumbered: col3 start: 0 num: 3];
    CBLCollection* col4 = [db2 collectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertEqualObjects(col3, col4);
    AssertNil(error);
}

#pragma mark - 8.4 Listeners

- (void) testCollectionChangeListener {
    NSError* error = nil;
    CBLCollection* col1 = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertNil(error);
    
    CBLCollection* col2 = [self.db createCollectionWithName: @"colB"
                                                      scope: @"scopeA" error: &error];
    AssertNil(error);
    
    XCTestExpectation* exp1 = [self expectationWithDescription: @"change listener 1"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"change listener 2"];
    XCTestExpectation* exp3 = [self expectationWithDescription: @"change listener 3"];
    XCTestExpectation* exp4 = [self expectationWithDescription: @"change listener 4"];
    __block int changeListenerFired = 0;
    __block int count1 = 0;
    id token1 = [col1 addChangeListener: ^(CBLCollectionChange* change) {
        changeListenerFired++;
        if ([change.collection.name isEqualToString: @"colA"]) {
            count1 += change.documentIDs.count;
            if (count1 == 10)
                [exp1 fulfill];
        } else {
            Assert(NO, @"CollectionB shouldn't receive any listener");
        }
    }];
    
    __block int count2 = 0;
    id token2 = [col1 addChangeListener: ^(CBLCollectionChange* change) {
        changeListenerFired++;
        if ([change.collection.name isEqualToString: @"colA"]) {
            count2 += change.documentIDs.count;
            if (count2 == 10)
                [exp2 fulfill];
        } else {
            Assert(NO, @"CollectionB shouldn't receive any listener");
        }
    }];
    
    __block int count3 = 0;
    dispatch_queue_t q1 = dispatch_queue_create(@"dispatch-queue-1".UTF8String, DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t q2 = dispatch_queue_create(@"dispatch-queue-2".UTF8String, DISPATCH_QUEUE_SERIAL);
    id token3 = [col1 addChangeListenerWithQueue: q1 listener: ^(CBLCollectionChange* change) {
        changeListenerFired++;
        if ([change.collection.name isEqualToString: @"colA"]) {
            count3 += change.documentIDs.count;
            if (count3 == 10)
                [exp3 fulfill];
        } else {
            Assert(NO, @"CollectionB shouldn't receive any listener");
        }
    }];
    
    __block int count4 = 0;
    id token4 = [col1 addChangeListenerWithQueue: q2 listener: ^(CBLCollectionChange* change) {
        changeListenerFired++;
        if ([change.collection.name isEqualToString: @"colA"]) {
            count4 += change.documentIDs.count;
            if (count4 == 10)
                [exp4 fulfill];
        } else {
            Assert(NO, @"CollectionB shouldn't receive any listener");
        }
    }];
    
    [self createDocNumbered: col1 start: 0 num: 10];
    [self createDocNumbered: col2 start: 0 num: 10];
    
    [self waitForExpectations: @[exp1, exp2, exp3, exp4] timeout: 10.0];
    changeListenerFired = 0;
    [token1 remove];
    [token2 remove];
    [token3 remove];
    [token4 remove];
    
    [self createDocNumbered: col1 start: 10 num: 10];
    [self createDocNumbered: col2 start: 10 num: 10];
    AssertEqual(changeListenerFired, 0);
}

/** Test that there is no collection or c4 object leak when the listener token is not removed.
    The actual check for the object leak is in the test's tear down. */
- (void) testCollectionChangeListenerWithoutRemoveToken {
    @autoreleasepool {
        NSError* error = nil;
        CBLCollection* colA = [self.db createCollectionWithName: @"colA"
                                                          scope: @"scopeA" error: &error];
        
        XCTestExpectation* exp1 = [self expectationWithDescription: @"change listener 1"];
        [colA addChangeListener: ^(CBLCollectionChange* change) {
            [exp1 fulfill];
        }];
        
        [self createDocNumbered: colA start: 0 num: 1];
        
        [self waitForExpectations: @[exp1] timeout: 10.0];
    }
}

- (void) testCollectionDocumentChangeListener {
    NSError* error = nil;
    CBLCollection* col1 = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertNil(error);
    
    CBLCollection* col2 = [self.db createCollectionWithName: @"colB"
                                                      scope: @"scopeA" error: &error];
    AssertNil(error);
    XCTestExpectation* exp1 = [self expectationWithDescription: @"doc change listener 1"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"doc change listener 2"];
    XCTestExpectation* exp3 = [self expectationWithDescription: @"doc change listener 3"];
    XCTestExpectation* exp4 = [self expectationWithDescription: @"doc change listener 4"];
    
    __block int changeListenerFired = 0;
    __block int count1 = 0;
    id token1 = [col1 addDocumentChangeListenerWithID: @"doc-1" listener: ^(CBLDocumentChange* change) {
        changeListenerFired++;
        if ([change.collection.name isEqualToString: @"colA"]) {
            if (++count1 == 2)
                [exp1 fulfill];
        } else {
            Assert(NO, @"CollectionB shouldn't receive any listener");
        }
    }];
    
    __block int count2 = 0;
    id token2 = [col1 addDocumentChangeListenerWithID: @"doc-1" listener: ^(CBLDocumentChange* change) {
        changeListenerFired++;
        if ([change.collection.name isEqualToString: @"colA"]) {
            if (++count2 == 2)
                [exp2 fulfill];
        } else {
            Assert(NO, @"CollectionB shouldn't receive any listener");
        }
    }];
    
    __block int count3 = 0;
    dispatch_queue_t q1 = dispatch_queue_create(@"dispatch-queue-1".UTF8String, DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t q2 = dispatch_queue_create(@"dispatch-queue-2".UTF8String, DISPATCH_QUEUE_SERIAL);
    id token3 = [col1 addDocumentChangeListenerWithID: @"doc-1" queue: q1 listener: ^(CBLDocumentChange* change) {
        changeListenerFired++;
        if ([change.collection.name isEqualToString: @"colA"]) {
            if (++count3 == 2)
                [exp3 fulfill];
        } else {
            Assert(NO, @"CollectionB shouldn't receive any listener");
        }
    }];
    
    __block int count4 = 0;
    id token4 = [col1 addDocumentChangeListenerWithID: @"doc-1" queue: q2 listener: ^(CBLDocumentChange* change) {
        changeListenerFired++;
        if ([change.collection.name isEqualToString: @"colA"]) {
            if (++count4 == 2)
                [exp4 fulfill];
        } else {
            Assert(NO, @"CollectionB shouldn't receive any listener");
        }
    }];
    
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc-1"];
    [doc setString: @"str" forKey: @"key"];
    [col1 saveDocument: doc error: &error];
    
    doc = [[col1 documentWithID: @"doc-1" error: &error] toMutable];
    [doc setString: @"str2" forKey: @"key2"];
    [col1 saveDocument: doc error: &error];
    
    [self createDocNumbered: col2 start: 0 num: 10];
    [self waitForExpectations: @[exp1, exp2, exp3, exp4] timeout: 10.0];
    changeListenerFired = 0;
    [token1 remove];
    [token2 remove];
    [token3 remove];
    [token4 remove];
    
    doc = [[col1 documentWithID: @"doc-1" error: &error] toMutable];
    [doc setString: @"str3" forKey: @"key3"];
    [col1 saveDocument: doc error: &error];
    
    [self createDocNumbered: col2 start: 10 num: 10];
    AssertEqual(changeListenerFired, 0);
}

/** Test that there is no collection or c4 object leak when the listener token is not removed.
    The actual check for the object leak is in the test's tear down. */
- (void) testCollectionDocumentChangeListenerWithoutRemoveToken {
    @autoreleasepool {
        NSError* error = nil;
        CBLCollection* colA = [self.db createCollectionWithName: @"colA" scope: @"scopeA" error: &error];
        AssertNotNil(colA);
        
        XCTestExpectation* exp1 = [self expectationWithDescription: @"doc change listener 1"];
        [colA addDocumentChangeListenerWithID: @"doc-1" listener: ^(CBLDocumentChange* change) {
            [exp1 fulfill];
        }];
        
        CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc-1"];
        [doc setString: @"str" forKey: @"key"];
        [colA saveDocument: doc error: &error];
        
        [self waitForExpectations: @[exp1] timeout: 10.0];
    }
}

#pragma mark - 8.5-6 Use collection APIs on deleted/closed scenarios

- (void) testUseCollectionAPIOnDeletedCollection {
    [self testUseInvalidCollection: @"colA" onAction: ^{
        NSError* er = nil;
        Assert([self.db deleteCollectionWithName: @"colA" scope: nil error: &er]);
        AssertNil(er);
    }];
}

- (void) testUseCollectionAPIOnDeletedCollectionDeletedFromDifferentDBInstance {
    NSError* error = nil;
    CBLDatabase* db2 = [self openDBNamed: kDatabaseName error: &error];
    [self testUseInvalidCollection: @"colA" onAction: ^{
        NSError* er = nil;
        Assert([db2 deleteCollectionWithName: @"colA" scope: nil error: &er]);
        AssertNil(er);
    }];
}

- (void) testUseCollectionAPIWhenDatabaseIsClosed {
    [self testUseInvalidCollection: @"colA" onAction: ^{
        NSError* error = nil;
        Assert([self.db close: &error]);
        AssertNil(error);
    }];
}

- (void) testUseCollectionAPIWhenDatabaseIsDeleted {
    [self testUseInvalidCollection: @"colA" onAction: ^{
        NSError* error = nil;
        Assert([self.db delete: &error]);
        AssertNil(error);
    }];
}

- (void) testUseInvalidCollection: (NSString*)collectionName onAction: (void (^) (void))onAction {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: collectionName
                                                     scope: nil error: &error];
    AssertNotNil(col);
    AssertNil(error);
    [self createDocNumbered: col start: 0 num: 10];
    CBLDocument* doc = [col documentWithID: @"doc4" error: nil];
    
    onAction();
    
    // properties
    AssertEqualObjects(col.name, collectionName);
    AssertEqualObjects(col.scope.name, kCBLDefaultScopeName);
    AssertEqual(col.count, 0);
    
    // document
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col documentWithID: @"doc-1" error: err] != nil;
    }];
    
    // save functions
    CBLMutableDocument* mdoc = [CBLMutableDocument document];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col saveDocument: mdoc error: err];
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col saveDocument: mdoc
                 conflictHandler: ^BOOL(CBLMutableDocument*d1, CBLDocument*d2) { return YES; }
                           error: err];
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col saveDocument: mdoc
              concurrencyControl: kCBLConcurrencyControlLastWriteWins
                           error: err];
    }];
    
    // delete functions
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col deleteDocument: doc error: err];
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col deleteDocument: doc
                concurrencyControl: kCBLConcurrencyControlLastWriteWins
                             error: err];
    }];
    
    // purge functions
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col purgeDocument: doc error: err];
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col purgeDocumentWithID: @"doc2" error: err];
    }];
    
    // doc expiry
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col setDocumentExpirationWithID: @"doc-1" expiration: [NSDate date] error: err];
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col getDocumentExpirationWithID: @"doc-1" error: err] != nil;
    }];

    // create valueIndexConfig
    CBLValueIndexConfiguration* config = [[CBLValueIndexConfiguration alloc] initWithExpression: @[@"firstName"]];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col createIndexWithName: @"index1" config: config error: err];
    }];
    
    // create fullTextIndexConfig
    CBLFullTextIndexConfiguration* config2 = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"firstName"]
                                                                                         ignoreAccents: NO language: nil];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col createIndexWithName: @"index2" config: config2 error: err];
    }];
    
    // get index, get indexes, delete index
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col indexWithName: @"index1" error: err];
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col indexes: err] != nil;
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col deleteIndexWithName: @"index1" error: err];
    }];
    
    // add change listeners:
    // to avoid stopping c4exception break point, we use ignoreException
    __block id<CBLListenerToken> token;
    [self ignoreException: ^{
        token = [col addChangeListener: ^(CBLCollectionChange *change) { }];
        [token remove];
    }];
    
    // doc change listener:
    // to avoid stopping c4exception break point, we use ignoreException
    [self ignoreException: ^{
        token = [col addDocumentChangeListenerWithID: @"doc1"
                                            listener: ^(CBLDocumentChange *change) { }];
        [token remove];
    }];
}

#pragma mark - 8.7 Use Scope APIs on deleted/closed scenarios

- (void) testUseScopeWhenDatabaseIsClosed {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"colA"
                                                     scope: @"scopeA" error: &error];
    AssertNotNil(col);
    AssertNil(error);
    CBLScope* scope = col.scope;
    
    // close
    [self.db close: &error];
    AssertNil(error);
    
    [self testInvalidScope: scope];
}

- (void) testUseScopeWhenDatabaseIsDeleted {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"colA"
                                                     scope: @"scopeA" error: &error];
    AssertNotNil(col);
    AssertNil(error);
    CBLScope* scope = col.scope;
    
    // delete
    [self.db delete: &error];
    AssertNil(error);
    
    [self testInvalidScope: scope];
}

- (void) testInvalidScope: (CBLScope*)scope {
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [scope collectionWithName: @"colA" error: err] != nil;
    }];
    
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [scope collections: err] != nil;
    }];
}

#pragma mark - 8.8 Get Scopes/Collections

- (void) testGetScopesOrCollectionsWhenDatabaseIsClosed {
    NSError* error = nil;
    [self.db close: &error];
    
    [self checkInvalidDatabase];
}

- (void) testGetScopesOrCollectionsWhenDatabaseIsDeleted {
    NSError* error = nil;
    [self.db delete: &error];
    
    [self checkInvalidDatabase];
}

- (void) checkInvalidDatabase {
    // default collection/scope
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** error) {
        return [self.db defaultCollection: error] != nil;
    }];
    
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** error) {
        return [self.db defaultScope: error] != nil;
    }];
    
    // collection(s)
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** error) {
        return [self.db collectionWithName: @"colA" scope: @"scopeA" error: error] != nil;
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** error) {
        return [self.db collections: nil error: error] != nil;
    }];
    
    // scope(s)
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** error) {
        return [self.db scopeWithName: @"scopeA" error: error] != nil;
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** error) {
        return [self.db scopes: error] != nil;
    }];
    
    // create/delete collections
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** error) {
        return [self.db createCollectionWithName: @"colA" scope: @"scopeA" error: error] != nil;
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** error) {
        return [self.db deleteCollectionWithName:@"colA" scope: @"scopeA" error: error];
    }];
}

#pragma mark - 8.9 all collections deleted under scope

- (void) testUseScopeAPIAfterDeletingAllCollections {
    [self testUseScopeAPIAfterDeletingAllCollectionsFrom: self.db];
}

- (void) testUseScopeAPIAfterDeletingAllCollectionsFromDifferentDBInstance {
    NSError* error = nil;
    CBLDatabase* db = [self openDBNamed: kDatabaseName error: &error];
    [self testUseScopeAPIAfterDeletingAllCollectionsFrom: db];
}

- (void) testUseScopeAPIAfterDeletingAllCollectionsFrom: (CBLDatabase*)db {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"colA"
                                                scope: @"scopeA" error: &error];
    AssertNotNil(col);
    AssertNil(error);
    CBLScope* scope = col.scope;
    
    Assert([db deleteCollectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil([scope collectionWithName: @"colA" error: &error]);
    AssertNil(error);

    // Empty result & no error
    NSArray* list = [scope collections: &error];
    AssertEqual(list.count, 0);
    AssertEqual(error.code, 0);
}

- (void) testUseScopeAfterScopeDeletedAndDBClosed {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"colA"
                                                     scope: @"scopeA" error: &error];
    AssertNotNil(col);
    AssertNil(error);
    CBLScope* scope = col.scope;
    
    [self.db deleteCollectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertNil(error);
    AssertNil([self.db scopeWithName: @"scopeA" error: &error]);
    AssertNil(error);
    
    [self.db close: &error];
    AssertNil(error);
    
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [scope collectionWithName: @"colA" error: err] != nil;
    }];

    NSArray* list = [scope collections: &error];
    AssertEqual(list.count, 0);
    AssertEqual(error.code, CBLErrorNotOpen);
}

@end
