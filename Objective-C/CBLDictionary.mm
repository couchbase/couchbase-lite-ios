//
//  CBLDictionary.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDictionary.h"
#import "CBLArray.h"
#import "CBLBlob.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLFragment.h"
#import "CBLJSON.h"
#import "CBLStringBytes.h"
#import "CBLFleece.hh"

using namespace fleeceapi;


@implementation CBLDictionary


#pragma mark - Initializers


+ (instancetype) dictionary {
    return [[self alloc] init];
}


- (instancetype) init {
    return [super initEmpty];
}


- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary {
    self = [self init];
    if (self) {
        [self setDictionary: dictionary];
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    return [[CBLReadOnlyDictionary alloc] initWithCopyOfMDict: _dict isMutable: false];
}


- (BOOL) changed {
    return _dict.isMutated();
}


#pragma mark - Type Setters


- (void) setArray: (nullable CBLArray *)value forKey: (NSString *)key {
    [self setObject: value forKey: key];
}


- (void) setBoolean: (BOOL)value forKey: (NSString *)key {
    [self setObject: @(value) forKey: key];
}


- (void) setBlob: (nullable CBLBlob*)value forKey: (NSString *)key {
    [self setObject: value forKey: key];
}


- (void) setDate: (nullable NSDate *)value forKey: (NSString *)key {
    [self setObject: value forKey: key];
}


- (void) setDictionary: (nullable CBLDictionary *)value forKey: (NSString *)key {
    [self setObject: value forKey: key];
}


- (void) setDouble: (double)value forKey: (NSString *)key {
    [self setObject: @(value) forKey: key];
}


- (void) setFloat: (float)value forKey: (NSString *)key {
    [self setObject: @(value) forKey: key];
}


- (void) setInteger: (NSInteger)value forKey: (NSString *)key {
    [self setObject: @(value) forKey: key];
}


- (void) setLongLong: (long long)value forKey: (NSString *)key {
    [self setObject: @(value) forKey: key];
}


- (void) setNumber: (nullable NSNumber*)value forKey: (NSString *)key {
    [self setObject: value forKey: key];
}


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    fleece::nsstring_slice keySlice(key);
    const MValue<id> &oldValue = _dict.get(keySlice);

    if (value) {
        value = [value cbl_toCBLObject];
        if (valueWouldChange(value, oldValue, _dict))
            _dict.set(keySlice, value);
    } else {
        // On Apple platforms, storing a nil value for a key means to delete the key.
        // (On other platforms, the null would be stored into the collection as a JSON null.)
        if (!oldValue.isEmpty())
            _dict.remove(keySlice);
    }
}


- (void) setString: (nullable NSString *)value forKey: (NSString *)key {
    [self setObject: value forKey: key];
}


- (void) removeObjectForKey: (NSString *)key {
    fleece::nsstring_slice keySlice(key);
    _dict.remove(keySlice);
}


- (void) setDictionary: (nullable NSDictionary<NSString*,id>*)dictionary {
    _dict.clear();
    
    [dictionary enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        fleece::nsstring_slice keySlice(key);
        _dict.set(keySlice, [value cbl_toCBLObject]);
    }];
}


#pragma mark - Subscript


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    return [[CBLFragment alloc] initWithParent: self key: key];
}


#pragma mark - CBLConversion


- (id) cbl_toCBLObject {
    // Overrides CBLReadOnlyDictionary
    return self;
}


@end
