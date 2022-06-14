//
//  CBLScope.m
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

#import "CBLScope+Internal.h"
#import "CBLCollection+Internal.h"

NSString* const kCBLDefaultScopeName = @"_default";

@implementation CBLScope

@synthesize name=_name;

- (instancetype) initWithName: (NSString *)name error: (NSError**)error {
    CBLAssertNotNil(name);
    self = [super init];
    if (self) {
        _name = name;
    }
    return self;
}

- (CBLCollection *) collectionWithName: (NSString *)collectionName error: (NSError**)error {
    // TODO: add implementation
    return nil;
}

- (nullable NSArray<CBLCollection*>*) collections: (NSError**)error {
    // TODO: add implementation
    return [NSArray array];
}

@end
