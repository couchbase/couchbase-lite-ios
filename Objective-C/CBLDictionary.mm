//
//  CBLDictionary.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDictionary.h"
#import "CBLDictionary+Swift.h"
#import "CBLDatabase+Internal.h"
#import "CBLArray.h"
#import "CBLBlob.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLFragment.h"
#import "CBLJSON.h"
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"


@implementation CBLDictionary {
    NSMutableDictionary<NSString*, id>* _dict;
    NSMapTable* _changeListeners;
    BOOL _changed;
    NSArray* _keys; // key cache
}

@synthesize changed=_changed, swiftObject=_swiftObject;


#pragma mark - Initializers


+ (instancetype) dictionary {
    return [[self alloc] init];
}


- (instancetype) init {
    return [self initWithFleeceData: nil];
}


- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary {
    self = [self initWithFleeceData: nil];
    if (self) {
        [self setDictionary: dictionary];
    }
    return self;
}


#pragma mark - CBLReadOnlyDictionary


- (NSUInteger) count {
    if (!_changed)
        return super.count;
    
    __block NSUInteger count = _dict.count;
    for (NSString* key in super.keys) {
        if (!_dict[key])
            count += 1;
    }
    
    [_dict enumerateKeysAndObjectsUsingBlock: ^(NSString *key, id value, BOOL *stop) {
        if (value == kCBLRemovedValue)
            count -= 1;
    }];
    return count;
}


- (NSArray*) keys {
    if (_keys)
        return _keys;

    NSArray* superKeys = super.keys;
    if (!_changed)
        return superKeys;

    if (superKeys.count == 0) {
        _keys = _dict.allKeys;
    } else {
        NSMutableSet* result = [NSMutableSet setWithArray: superKeys];
        [_dict enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (value != kCBLRemovedValue)
                [result addObject: key];
            else
                [result removeObject: key];
        }];
        _keys = result.allObjects;
    }
    return _keys;
}


- (nullable CBLArray*) arrayForKey: (NSString*)key {
    return $castIf(CBLArray, [self objectForKey: key]);
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return $castIf(CBLBlob, [self objectForKey:key]);
}


- (BOOL) booleanForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super booleanForKey: key];
    else {
        if (value == kCBLRemovedValue)
            return NO;
        else
            return [CBLData booleanValueForObject: value];
    }
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [CBLJSON dateWithJSONObject: [self objectForKey: key]];
}


- (nullable CBLDictionary*) dictionaryForKey: (NSString*)key {
    return $castIf(CBLDictionary, [self objectForKey: key]);
}


- (double) doubleForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super doubleForKey: key];
    else
        return [$castIf(NSNumber, value) doubleValue];
}


- (float) floatForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super floatForKey: key];
    else
        return [$castIf(NSNumber, value) floatValue];
}


- (NSInteger) integerForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super integerForKey: key];
    else
        return [$castIf(NSNumber, value) integerValue];
}


- (long long) longLongForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super longLongForKey: key];
    else
        return [$castIf(NSNumber, value) longLongValue];
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return $castIf(NSNumber, [self objectForKey: key]);
}


- (nullable id) objectForKey: (NSString*)key {
    id value = _dict[key];
    if (!value) {
        value = [super objectForKey: key];
        if ([value isKindOfClass: [CBLReadOnlyDictionary class]]) {
            value = [value cbl_toCBLObject];
            [self setValue: value forKey: key isChange: NO];
        } else if ([value isKindOfClass: [CBLReadOnlyArray class]]) {
            value = [value cbl_toCBLObject];
            [self setValue: value forKey: key isChange: NO];
        }
    } else if (value == kCBLRemovedValue)
        value = nil;
    return value;
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return $castIf(NSString, [self objectForKey: key]);
}


- (BOOL) containsObjectForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super containsObjectForKey: key];
    else
        return value != kCBLRemovedValue;
}


- (NSDictionary<NSString*,id>*) toDictionary {
    NSDictionary* backingData = [super toDictionary];
    if (_dict.count == 0)
        return backingData; // No changes

    NSMutableDictionary* result = [backingData mutableCopy];
    [_dict enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        if (value == kCBLRemovedValue)
            result[key] = nil; // Remove key
        else
            result[key] = [value cbl_toPlainObject];
    }];
    return result;
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
    if (!value) value = [NSNull null]; // nil conversion only for apple platform
    id oldValue = [self objectForKey: key];
    value = [value cbl_toCBLObject];
    if (!$equal(value, oldValue)) {
        [self setValue: value forKey: key isChange: YES];
        _keys = nil; // Reset key cache
    }
}


- (void) setString: (nullable NSString *)value forKey: (NSString *)key {
    [self setObject: value forKey: key];
}


- (void) removeObjectForKey: (NSString *)key {
    id value = [super containsObjectForKey: key] ? kCBLRemovedValue : nil;
    if (value != _dict[key]) {
        [self setValue: value forKey: key isChange: YES];
        _keys = nil; // Reset key cache
    }
}


- (void) setDictionary: (nullable NSDictionary<NSString*,id>*)dictionary {
    NSArray* inheritedKeys = [super keys];
    NSUInteger capacity = MAX(dictionary.count, inheritedKeys.count);
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity: capacity];
    
    [dictionary enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        result[key] = [value cbl_toCBLObject];
    }];
    
    // Mark pre-existing keys as removed by setting the value to kRemovedValue:
    for (NSString* key in inheritedKeys) {
        if (!result[key])
            result[key] = kCBLRemovedValue;
    };
    
    _dict = result;
    
    [self setChanged];
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    if (!_changed)
        return [super countByEnumeratingWithState: state objects: buffer count: len];
    else
        return [[self keys] countByEnumeratingWithState: state objects: buffer count: len];
}


#pragma mark - Subscript


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    id value = [self objectForKey: key];
    return [[CBLFragment alloc] initWithValue: value parent: self parentKey: key];
}


#pragma mark - Internal


- (BOOL) isEmpty {
    if (!_changed)
        return super.isEmpty;
    
    for (NSString* key in super.keys) {
        if (!_dict[key])
            return NO;
    }
    
    __block BOOL isEmpty = YES;
    [_dict enumerateKeysAndObjectsUsingBlock: ^(NSString *key, id value, BOOL *stop) {
        if (value != kCBLRemovedValue) {
            isEmpty = NO;
            *stop = YES;
        }
    }];
    return isEmpty;
}


#pragma mark - CBLConversion


- (id) cbl_toCBLObject {
    return self;
}


#pragma mark - Private


- (void) setValue: (id)value forKey: (NSString*)key isChange: (BOOL)isChange {
    if (!_dict)
        _dict = [NSMutableDictionary dictionary];
    
    _dict[key] = value;
    if (isChange)
        [self setChanged];
}


#pragma mark - Change


- (void) setChanged {
    if (!_changed) {
        _changed = YES;
    }
}


#pragma mark - Fleece Encodable


- (BOOL) cbl_fleeceEncode: (FLEncoder)encoder
                 database: (CBLDatabase*)database
                    error: (NSError**)outError
{
    NSArray* keys = self.keys;
    FLEncoder_BeginDict(encoder, keys.count);
    for (NSString* key in keys) {
        id value = [self objectForKey: key];
        if (value != kCBLRemovedValue) {
            CBLStringBytes bKey(key);
            FL_WriteKey(encoder, bKey, database.sharedKeys);
            if (![value cbl_fleeceEncode: encoder database: database error: outError])
                return NO;
        }
    }
    FLEncoder_EndDict(encoder);
    return YES;
}



@end
