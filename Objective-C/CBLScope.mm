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

#import "CBLCollection+Internal.h"
#import "CBLDatabase+Internal.h"
#import "CBLScope+Internal.h"
#import "CBLStringBytes.h"

NSString* const kCBLDefaultScopeName = @"_default";

@implementation CBLScope

@synthesize name=_scopeName, db=_db;

- (instancetype) initWithDB: (CBLDatabase*)db name: (NSString *)name {
    CBLAssertNotNil(name);
    self = [super init];
    if (self) {
        _scopeName = name;
        _db = db;
        CBLLogVerbose(Database, @"%@ Creating scope", self.fullDescription);
    }
    return self;
}

- (nullable CBLCollection *) collectionWithName: (NSString *)name error: (NSError**)error {
    return [_db collectionWithName: name scope: _scopeName error: error];
}

- (nullable NSArray<CBLCollection*>*) collections: (NSError**)error {
    return [_db collections: _scopeName error: error];
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, _scopeName];
}

- (NSString*) fullDescription {
    return [NSString stringWithFormat: @"%p %@[%@] db[%@]", self, self.class, _scopeName, _db];
}

@end
