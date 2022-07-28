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

#pragma mark - Default Scope/Collection

- (void) testDefaultCollectionExists {
    NSError* error = nil;
    CBLCollection* dCol = [self.db defaultCollection: &error];
    AssertNotNil(dCol, @"default collection shouldn't be empty");
    AssertEqualObjects(dCol.name, kCBLDefaultCollectionName);
    AssertNil(error);
    
    NSArray* cols = [self.db collections: nil error: &error];
    Assert([cols containsObject: dCol]);
    AssertNil(error);
    
    CBLScope* dScope = dCol.scope;
    AssertNotNil(dScope, @"default scope shouldn't be empty");
    AssertEqualObjects(dScope.name, kCBLDefaultScopeName);
    
    CBLCollection* col1 = [self.db collectionWithName: kCBLDefaultCollectionName
                                                scope: nil error: &error];
    AssertEqualObjects(dCol, col1);
    AssertNil(error);
}

- (void) testDefaultScopeExists {
    NSError* error = nil;
    CBLScope* dScope = [self.db defaultScope: &error];
    AssertNotNil(dScope, @"Default scope shouldn't be empty");
    AssertEqualObjects(dScope.name, kCBLDefaultScopeName);
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
    NSError* error = nil;
    Assert([self.db deleteCollectionWithName: kCBLDefaultCollectionName scope: nil error: &error]);
    AssertNil(error);
    
    CBLCollection* dCol = [self.db defaultCollection: &error];
    AssertNil(dCol);
    AssertEqual(error.code, CBLErrorNotFound);
    AssertEqual(error.domain, CBLErrorDomain);
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
        return [self.db createCollectionWithName: kCBLDefaultCollectionName
                                           scope: nil error: e] != nil;
    }];
    
    dCol = [self.db defaultCollection: &error];
    AssertNil(dCol);
    AssertEqual(error.code, CBLErrorNotFound);
    AssertEqual(error.domain, CBLErrorDomain);
}

- (void) testGetDefaultScopeAfterDeleteDefaultCollection {
    NSError* error = nil;
    Assert([self.db deleteCollectionWithName: kCBLDefaultCollectionName scope: nil error: &error]);
    AssertNil(error);
    
    CBLScope* dScope = [self.db defaultScope: &error];
    AssertNotNil(dScope, @"Default scope shouldn't be empty");
    AssertEqualObjects(dScope.name, kCBLDefaultScopeName);
    AssertNil(error);
    
    NSArray<CBLScope*>* scopes = [self.db scopes: &error];
    AssertEqual(scopes.count, 1);
    AssertEqualObjects(scopes[0].name, kCBLDefaultScopeName);
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
    
    CBLCollection* colBa = [self.db collectionWithName: @"colB" scope: nil error: &error];
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
    AssertEqual(error.code, CBLErrorNotFound);
    
    error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertEqualObjects(colA.name, @"colA");
    AssertEqualObjects(colA.scope.name, @"scopeA");
    AssertNil(error);
    
    CBLScope* scopeA = [self.db scopeWithName: @"scopeA" error: &error];
    AssertNotNil(scopeA);
    AssertEqualObjects(scopeA.name, @"scopeA");
    AssertNil(error);
    
    colA = [self.db collectionWithName: @"colA"
                                 scope: @"scopeA" error: &error];
    AssertEqualObjects(colA.name, @"colA");
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
    AssertNil(error);
    CBLMutableDocument* d = [CBLMutableDocument documentWithID: @"doc1"];
    [d setString: @"string" forKey: @"someKey"];
    [colA saveDocument: d error: &error];
    AssertNil(error);
    
    CBLCollection* colB = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertNil(error);
    
    CBLDocument* doc1 = [colB documentWithID: @"doc1" error: &error];
    AssertNotNil(doc1);
    AssertNil(error);
}

- (void) testGetNonExistingCollection {
    NSError* error = nil;
    AssertNil([self.db collectionWithName: @"colA"
                                    scope: @"scopeA" error: &error]);
    AssertEqual(error.code, CBLErrorNotFound);
}

- (void) testDeleteCollection {
    NSError* error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertNotNil(colA);
    AssertNil(error);
    
    CBLMutableDocument* doc1 = [CBLMutableDocument documentWithID: @"doc1"];
    [doc1 setString: @"str" forKey: @"str"];
    [colA saveDocument: doc1 error: &error];
    AssertNil(error);
    
    CBLMutableDocument* doc2 = [CBLMutableDocument documentWithID: @"doc2"];
    [doc2 setString: @"str2" forKey: @"str2"];
    [colA saveDocument: doc2 error: &error];
    AssertNil(error);
    
    CBLMutableDocument* doc3 = [CBLMutableDocument documentWithID: @"doc3"];
    [doc3 setString: @"str3" forKey: @"str3"];
    [colA saveDocument: doc3 error: &error];
    AssertNil(error);
    AssertEqual(colA.count, 3);
    
    Assert([self.db deleteCollectionWithName: @"colA" scope: @"scopeA" error: &error]);
    
    AssertNil([self.db collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    
    NSArray* cols = [self.db collections: @"scopeA" error: &error];
    AssertEqual(cols.count, 0);
    
    colA = [self.db createCollectionWithName: @"colA"
                                       scope: @"scopeA" error: &error];
    AssertNotNil(colA);
    AssertEqual(colA.count, 0);
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
    AssertNotNil([scope collectionWithName: @"colA" error: &error]);
    AssertNil(error);
    AssertNotNil([scope collectionWithName: @"colB" error: &error]);
    AssertNil(error);
    
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
    
    [self.db deleteCollectionWithName: @"colA" scope: @"scopeA" error: &error];
    collectionsInScopeA = [scopeA collections: &error];
    AssertEqual(collectionsInScopeA.count, 1);
    AssertNil(error);
    [self.db deleteCollectionWithName: @"colB" scope: @"scopeA" error: &error];
    AssertNil(error);
    
    AssertNil([self.db scopeWithName: @"scopeA" error: &error]);
    AssertEqual(error.code, CBLErrorNotFound);
    
    error = nil;
    AssertNil([self.db collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertEqual(error.code, CBLErrorNotFound);
    
    error = nil;
    AssertNil([self.db collectionWithName: @"colB" scope: @"scopeA" error: &error]);
    AssertEqual(error.code, CBLErrorNotFound);
}

- (void) testScopeCollectionNameWithValidChars {
    NSArray* names = @[@"a",
    /* TODO: https://issues.couchbase.com/browse/CBL-3195 @"A", */
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
        
        AssertEqualObjects(col1.name, col2.name);
        AssertEqualObjects(col1.scope.name, col2.scope.name);
    }
}

- (void) testScopeCollectionNameWithIllegalChars {
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
        return  [self.db createCollectionWithName: @"_" scope: nil error: e] != nil;
    }];
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
        return  [self.db createCollectionWithName: @"a" scope: @"_" error: e] != nil;
    }];
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
        return  [self.db createCollectionWithName: @"%" scope: nil error: e] != nil;
    }];
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
        return  [self.db createCollectionWithName: @"b" scope: @"%" error: e] != nil;
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

// TODO: CBL-3195
- (void) _testCollectionNameCaseSensitive {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"COLLECTION1"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"collection1"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    AssertEqualObjects(col1a.name, @"COLLECTION1");
    AssertEqualObjects(col1b.name, @"collection1");
    
    NSArray<CBLCollection*>* cols = [self.db collections: @"scopeA" error: &error];
    AssertEqual(cols.count, 2);
    Assert([(@[@"COLLECTION1", @"collection1"]) containsObject: cols[0].name]);
    Assert([(@[@"COLLECTION1", @"collection1"]) containsObject: cols[1].name]);
}

// TODO: CBL-3195
- (void) _testScopeNameCaseSensitive {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colA"
                                                       scope: @"SCOPEa" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    AssertEqualObjects(col1a.scope.name, @"scopeA");
    AssertEqualObjects(col1b.scope.name, @"SCOPEa");
    
    NSArray<CBLScope*>* scopes = [self.db scopes: &error];
    AssertEqual(scopes.count, 2);
    Assert([(@[@"scopeA", @"SCOPEa"]) containsObject: scopes[0].name]);
    Assert([(@[@"scopeA", @"SCOPEa"]) containsObject: scopes[1].name]);
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
    AssertEqualObjects(col.name, col2.name);
    AssertEqualObjects(col.scope.name, col2.scope.name);
    AssertEqual(col2.count, 10);
    AssertNil(error);
    
    AssertEqual([self.db collections: @"scopeA" error: &error].count, 1);
    AssertNil(error);
    AssertEqual([db2 collections: @"scopeA" error: &error].count, 1);
    AssertNil(error);
    
    [self createDocNumbered: col start: 10 num: 10];
    AssertEqual(col.count, 20);
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
    
    Assert([self.db deleteCollectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertEqual(col.count, 0);
    AssertEqual(col2.count, 0);
    AssertNil(error);
    
    AssertNil([self.db collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertEqual(error.code, CBLErrorNotFound);
    AssertNil([db2 collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertEqual(error.code, CBLErrorNotFound);
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
    
    // Delete the collection from db:
    Assert([self.db deleteCollectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil(error);
    
    AssertNil([self.db collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertEqual(error.code, CBLErrorNotFound);
    
    error = nil;
    AssertNil([db2 collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertEqual(error.code, CBLErrorNotFound);
    
    // Recreate:
    error = nil;
    CBLCollection* col3 = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertEqual(col3.count, 0);
    AssertNil(error);
    
    [self createDocNumbered: col3 start: 0 num: 3];
    CBLCollection* col4 = [db2 collectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertEqual(col4.count, 3);
    AssertEqual(col3.count, 3);
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

    // indexes
    CBLValueIndexConfiguration* config = [[CBLValueIndexConfiguration alloc] initWithExpression: @[@"firstName"]];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col createIndexWithName: @"index1" config: config error: err];
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col indexes: err] != nil;
    }];
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [col deleteIndexWithName: @"index1" error: err];
    }];
}

#pragma mark - 8.7 Use Scope APIs on deleted/closed scenarios

- (void) testUseScopeWhenDatabaseIsClosed {
    [self testUseInvalidScope: ^{
        NSError* error = nil;
        [self.db close: &error];
        AssertNil(error);
    }];
}

- (void) testUseScopeWhenDatabaseIsDeleted {
    [self testUseInvalidScope: ^{
        NSError* error = nil;
        [self.db delete: &error];
        AssertNil(error);
    }];
}

- (void) testUseInvalidScope: (void (^) (void))onAction {
    NSError* error = nil;
    CBLCollection* col = [self.db createCollectionWithName: @"colA"
                                                     scope: nil error: &error];
    AssertNotNil(col);
    AssertNil(error);
    CBLScope* scope = col.scope;
    
    onAction();
    
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
    
    [self getScopesOrCollectionsTest];
}

- (void) testGetScopesOrCollectionsWhenDatabaseIsDeleted {
    NSError* error = nil;
    [self.db delete: &error];
    
    [self getScopesOrCollectionsTest];
}

- (void) getScopesOrCollectionsTest {
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

#pragma mark - 8.9 default collection deleted

// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void) testUseDatabaseAPIWhenDefaultCollectionIsDeleted {
    NSError* error = nil;
    CBLCollection* col = [self.db defaultCollection: &error];
    AssertNotNil(col);
    AssertNil(error);
    [self createDocNumbered: col start: 0 num: 10];
    CBLDocument* doc = [col documentWithID: @"doc4" error: nil];
    id token = [self.db addChangeListener:^(CBLDatabaseChange *change) { }];
    
    [self.db deleteCollectionWithName: kCBLDefaultCollectionName scope: nil error: &error];
    
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db documentWithID: @"doc-1"];
    }];
    // save functions
    CBLMutableDocument* mdoc = [CBLMutableDocument document];
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db saveDocument: mdoc error: nil];
    }];
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db saveDocument: mdoc
              conflictHandler: ^BOOL(CBLMutableDocument*d1, CBLDocument*d2) { return YES; }
                        error: nil];
    }];
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db saveDocument: mdoc
           concurrencyControl: kCBLConcurrencyControlLastWriteWins
                        error: nil];
    }];
    
    // delete functions
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db deleteDocument: doc error: nil];
    }];
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db deleteDocument: doc
             concurrencyControl: kCBLConcurrencyControlLastWriteWins
                          error: nil];
    }];
    
    // purge functions
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db purgeDocument: doc error: nil];
    }];
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db purgeDocumentWithID: @"doc2" error: nil];
    }];
    
    // doc expiry
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db setDocumentExpirationWithID: @"doc-1" expiration: [NSDate date] error: nil];
    }];
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db getDocumentExpirationWithID: @"doc-1"];
    }];
    
    // indexes
    CBLValueIndexConfiguration* config = [[CBLValueIndexConfiguration alloc] initWithExpression: @[@"firstName"]];
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db createIndexWithConfig: config name: @"index1" error: nil];
    }];
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db indexes];
    }];
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db deleteIndexForName: @"index1" error: nil];
    }];
    
    // change listener
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db addChangeListener:^(CBLDatabaseChange *change) { }];
    }];
    [self expectException: NSInternalInconsistencyException in: ^{
        dispatch_queue_t q1 = dispatch_queue_create(@"dispatch-queue-1".UTF8String, DISPATCH_QUEUE_SERIAL);
        [self.db addChangeListenerWithQueue: q1 listener:^(CBLDatabaseChange *change) { }];
    }];
    
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db addDocumentChangeListenerWithID: @"doc1" listener: ^(CBLDocumentChange* change) { }];
    }];
    [self expectException: NSInternalInconsistencyException in: ^{
        dispatch_queue_t q2 = dispatch_queue_create(@"dispatch-queue-2".UTF8String, DISPATCH_QUEUE_SERIAL);
        [self.db addDocumentChangeListenerWithID: @"doc1" queue: q2 listener: ^(CBLDocumentChange* change) { }];
    }];
    
    [self expectException: NSInternalInconsistencyException in: ^{
        [self.db removeChangeListenerWithToken: token];
    }];
}
#pragma clang diagnostic pop

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
    AssertEqual([scope collections: &error].count, 0);
}

@end
