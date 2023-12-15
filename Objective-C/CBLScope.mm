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

@synthesize name=_scopeName, strongdb=_strongdb, weakdb=_weakdb;

- (instancetype) initWithDB: (CBLDatabase*)db name: (NSString *)name cached:(BOOL)cached {
    CBLAssertNotNil(name);
    self = [super init];
    if (self) {
        _scopeName = name;
        if (cached) {
            _weakdb = db;
        } else {
            _strongdb = db;
        }
    }
    return self;
}

- (CBLDatabase*) database {
    if (_strongdb) {
        return _strongdb;
    } else {
        CBLDatabase* db = _weakdb;
        assert(db);
        return db;
    }
}

- (nullable CBLCollection *) collectionWithName: (NSString *)name error: (NSError**)error {
    return [self.database collectionWithName: name scope: _scopeName error: error];
}

- (nullable NSArray<CBLCollection*>*) collections: (NSError**)error {
    return [self.database collections: _scopeName error: error];
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, _scopeName];
}

- (NSString*) fullDescription {
    return [NSString stringWithFormat: @"%p %@[%@] db[%@]", self, self.class, _scopeName, self.database];
}

- (NSUInteger) hash {
    return [self.name hash] ^ [self.database.path hash];
}

- (BOOL) isEqual: (id)object {
    if (self == object)
        return YES;
    
    CBLScope* other = $castIf(CBLScope, object);
    if (!other)
        return NO;
    
    if (!(other && [self.name isEqual: other.name] &&
          [self.database.path isEqual: other.database.path])) {
        return NO;
    }
    
    return YES;
}

@end
