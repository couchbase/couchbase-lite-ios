//
//  CBLMutableDictionary.mm
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLMutableDictionary.h"
#import "CBLMutableArray.h"
#import "CBLBlob.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLMutableFragment.h"
#import "CBLJSON.h"
#import "CBLStringBytes.h"
#import "CBLFleece.hh"
#import "CBLStatus.h"

using namespace fleece;

@implementation CBLMutableDictionary

#pragma mark - Initializers

+ (instancetype) dictionary {
    return [[self alloc] init];
}

- (instancetype) init {
    return [super initEmpty];
}

- (instancetype) initWithData: (NSDictionary<NSString*,id>*)data {
    self = [self init];
    if (self) {
        [self setData: data];
    }
    return self;
}

- (instancetype) initWithJSON: (NSString*)json error: (NSError**)error {
    self = [self init];
    if (self) {
        if (![self setJSON: json error: error])
            return nil;
    }
    return self;
}

- (id) copyWithZone: (NSZone*)zone {
    CBL_LOCK(self.sharedLock) {
        return [[CBLDictionary alloc] initWithCopyOfMDict: _dict isMutable: false];
    }
}

- (BOOL) changed {
    CBL_LOCK(self.sharedLock) {
        return _dict.isMutated();
    }
}

#pragma mark - Type Setters

- (void) setValue: (nullable id)value forKey: (NSString*)key {
    CBLAssertNotNil(key);
    
    CBL_LOCK(self.sharedLock) {
        CBLStringBytes keySlice(key);
        const MValue<id> &oldValue = _dict.get(keySlice);
        
        if (!value) value = [NSNull null]; // Store NSNull
        value = [value cbl_toCBLObject];
        if (cbl::valueWouldChange(value, oldValue, _dict)) {
            _dict.set(keySlice, value);
            [self keysChanged];
        }
    }
}

- (void) setString: (nullable NSString *)value forKey: (NSString*)key {
    [self setValue: value forKey: key];
}

- (void) setNumber: (nullable NSNumber*)value forKey: (NSString*)key {
    [self setValue: value forKey: key];
}

- (void) setInteger: (NSInteger)value forKey: (NSString*)key {
    [self setValue: @(value) forKey: key];
}

- (void) setLongLong: (long long)value forKey: (NSString*)key {
    [self setValue: @(value) forKey: key];
}

- (void) setFloat: (float)value forKey: (NSString*)key {
    [self setValue: @(value) forKey: key];
}

- (void) setDouble: (double)value forKey: (NSString*)key {
    [self setValue: @(value) forKey: key];
}

- (void) setBoolean: (BOOL)value forKey: (NSString*)key {
    [self setValue: @(value) forKey: key];
}

- (void) setDate: (nullable NSDate*)value forKey: (NSString*)key {
    [self setValue: value forKey: key];
}

- (void) setBlob: (nullable CBLBlob*)value forKey: (NSString*)key {
    [self setValue: value forKey: key];
}

- (void) setArray: (nullable CBLArray*)value forKey: (NSString*)key {
    [self setValue: value forKey: key];
}

- (void) setDictionary: (nullable CBLDictionary*)value forKey: (NSString*)key {
    [self setValue: value forKey: key];
}

- (void) removeValueForKey: (NSString*)key {
    CBLAssertNotNil(key);
    CBL_LOCK(self.sharedLock) {
        CBLStringBytes keySlice(key);
        _dict.remove(keySlice);
        [self keysChanged];
    }
}

- (void) setData: (NSDictionary<NSString*,id>*)data {
    CBL_LOCK(self.sharedLock) {
        _dict.clear();
        [data enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL* stop) {
            CBLStringBytes keySlice(key);
            _dict.set(keySlice, [value cbl_toCBLObject]);
        }];
        [self keysChanged];
    }
}

- (BOOL) setJSON: (NSString*)json error: (NSError**)error {
    CBLStringBytes jsonSlice(json);
    NSError* err = nil;
    id result = cbl::parseJSON(jsonSlice, &err);
    if (err || !result) {
        if (error)
            *error = err;
        return NO;
    }
    if (![result isKindOfClass: [NSDictionary class]]) {
        CBLWarnError(Database, @"%@: Failed to convert FLValue to NSDictionary", self);
        return createError(CBLErrorInvalidJSON, @"Parsed result is not a Dictionary", error);
    }
    
    NSDictionary* dict = (NSDictionary*)result;
    _dict.clear();
    
    NSEnumerator *iter = [dict keyEnumerator];
    id key;
    while((key = [iter nextObject])) {
        CBLStringBytes keySlice(key);
        _dict.set(keySlice, [[dict objectForKey:key] cbl_toCBLObject]);
    }
    
    return YES;
}

#pragma mark - Subscript

- (CBLMutableFragment*) objectForKeyedSubscript: (NSString*)key {
    CBLAssertNotNil(key);
    return [[CBLMutableFragment alloc] initWithParent: self key: key];
}

#pragma mark - CBLConversion

- (id) cbl_toCBLObject {
    // Overrides CBLDictionary
    return self;
}

- (NSString*) toJSON {
    // Overrides CBLDictionary
    [NSException raise: NSInternalInconsistencyException
                format: @"toJSON on Mutable objects are unsupported"];
    return nil;
}

@end
