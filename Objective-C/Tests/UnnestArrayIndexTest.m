//
//  UnnestArrayIndexTest.m
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc. All rights reserved.
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
#import "CBLArrayIndexConfiguration.h"
#import "CBLCollection+Internal.h"

@interface UnnestArrayIndexTest : CBLTestCase

@end

@implementation UnnestArrayIndexTest

/**
 Test Spec v1.0.1:
 https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0004-Unnest-Array-Index.md
 */

/**
 1. TestArrayIndexConfigInvalidExpressions
 Description
    Test that creating an ArrayIndexConfiguration with invalid expressions which are an empty expressions or contain null.
 Steps
    1. Create a ArrayIndexConfiguration object.
        - path: "contacts"
        - expressions: []
    2. Check that an invalid arument exception is thrown.
 */

- (void) testArrayIndexConfigInvalidExpressions {
    [self expectException: NSInvalidArgumentException in:^{
        (void) [[CBLArrayIndexConfiguration alloc] initWithPath:@"contacts" expressions: @[]];
    }];
}

/**
 2. TestCreateArrayIndexWithPath
 Description
    Test that creating an array index with only path works as expected.
 Steps
    1. Load profiles.json into the collection named "_default.profiles".
    2. Create a ArrayIndexConfiguration object.
        - path: "contacts"
        - expressions: null
    3. Create an array index named "contacts" in the profiles collection.
    4. Get index names from the profiles collection and check that the index named "contacts" exists.
    5. Get info of the index named "contacts" using an internal API and check that the index has path and expressions as configured.
 */

- (void) testCreateArrayIndexWithPath {
    NSError* err;
    CBLCollection* profiles = [self.db createCollectionWithName: @"profiles" scope: nil error: &err];
    [self loadJSONResource: @"profiles_100" toCollection: profiles];
    
    CBLArrayIndexConfiguration* config = [[CBLArrayIndexConfiguration alloc] initWithPath: @"contacts" expressions: nil];
    [profiles createIndexWithName: @"contacts" config: config error: &err];
    NSArray* indexes = [profiles indexesInfo: nil];
    AssertEqual(indexes.count, 1u);
    AssertEqualObjects(indexes[0][@"expr"], @"");
}

/**
 3. TestCreateArrayIndexWithPathAndExpressions
 Description
    Test that creating an array index with path and expressions works as expected.
 Steps
    1. Load profiles.json into the collection named "_default.profiles".
    2. Create a ArrayIndexConfiguration object.
        - path: "contacts"
        - expressions: ["address.city", "address.state"]
    3. Create an array index named "contacts" in the profiles collection.
    4. Get index names from the profiles collection and check that the index named "contacts" exists.
    5. Get info of the index named "contacts" using an internal API and check that the index has path and expressions as configured.
 */
- (void) testCreateArrayIndexWithPathAndExpressions {
    NSError* err;
    CBLCollection* profiles = [self.db createCollectionWithName: @"profiles" scope: nil error: &err];
    [self loadJSONResource: @"profiles_100" toCollection: profiles];
    
    CBLArrayIndexConfiguration* config = [[CBLArrayIndexConfiguration alloc] initWithPath: @"contacts" expressions: @[@"address.city", @"address.state"]];
    [profiles createIndexWithName: @"contacts" config: config error: &err];
    
    NSArray* indexes = [profiles indexesInfo: nil];
    AssertEqual(indexes.count, 1u);
    AssertEqualObjects(indexes[0][@"expr"], @"address.city,address.state");
}

@end
