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

@end
