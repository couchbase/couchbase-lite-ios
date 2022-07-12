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
    AssertNil(error);
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in:^BOOL(NSError** e) {
        return [self.db createCollectionWithName: kCBLDefaultCollectionName
                                           scope: nil error: e] != nil;
    }];
    
    dCol = [self.db defaultCollection: &error];
    AssertNil(dCol);
    AssertNil(error);
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
    AssertNil(error);
    
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
    AssertNil(error);
}

- (void) testDeleteCollection1 {
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
    AssertNil(error);
    AssertNil([self.db collectionWithName: @"colA" scope: @"scopeA" error: &error]);
    AssertNil(error);
    AssertNil([self.db collectionWithName: @"colB" scope: @"scopeA" error: &error]);
    AssertNil(error);
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
    NSMutableString* name = [NSMutableString string];
    for (NSUInteger i = 0; i < 251; i++) {
        [name appendString: @"a"];
        
        NSError* error = nil;
        CBLCollection* col = [self.db createCollectionWithName: name scope: name error: &error];
        AssertNotNil(col);
        AssertEqualObjects(col.name, name);
        AssertEqualObjects(col.scope.name, name);
    }
    
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

@end
