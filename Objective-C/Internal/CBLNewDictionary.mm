//
//  CBLNewDictionary.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLNewDictionary.h"
#import "CBLMutableDictionary.h"
#import "CBLData.h"
#import "CBLMutableArray.h"
#import "CBLBlob.h"
#import "CBLJSON.h"
#import "CBLMutableFragment.h"
#import "CBLDocument+Internal.h"

using namespace cbl;


@implementation CBLNewDictionary
{
    NSMutableDictionary* _dict;
    BOOL _changed;
}


- (instancetype) init {
    self = [super init];
    if (self) {
        _dict = [NSMutableDictionary new];
    }
    return self;
}


- (instancetype) initWithDictionary: (NSDictionary*)dictionary {
    self = [super init];
    if (self) {
        _dict = [dictionary mutableCopy];
        if (_dict.count > 0)
            _changed = YES;
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    return [[[self class] alloc] initWithDictionary: _dict];
}


- (CBLMutableDictionary*) mutableCopyWithZone:(NSZone *)zone {
    return [[[self class] alloc] initWithDictionary: _dict];
}


- (void) fl_encodeToFLEncoder: (FLEncoder)enc {
    FLEncoder_WriteNSObject(enc, _dict);
}


- (BOOL) changed {
    return _changed;
}


#pragma mark - Counting Entries


- (NSUInteger) count {
    return _dict.count;
}


#pragma mark - Accessing Keys


- (NSArray*) keys {
    return _dict.allKeys;
}


#pragma mark - Type Getters


- (nullable id) objectForKey: (NSString*)key {
    id obj = _dict[key];
    id cblObj = [obj cbl_toCBLObject];
    if (cblObj != obj && [cblObj class] != [obj class])
        _dict[key] = cblObj;
    return cblObj;
}


- (nullable id) valueForKey: (NSString*)key {
    return [self objectForKey: key];
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return asString(_dict[key]);
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return asNumber(_dict[key]);
}


- (NSInteger) integerForKey: (NSString*)key {
    return asInteger(_dict[key]);
}


- (long long) longLongForKey: (NSString*)key {
    return asLongLong(_dict[key]);
}


- (float) floatForKey: (NSString*)key {
    return asFloat(_dict[key]);
}


- (double) doubleForKey: (NSString*)key {
    return asDouble(_dict[key]);
}


- (BOOL) booleanForKey: (NSString*)key {
    return asBool(_dict[key]);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return asDate(_dict[key]);
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return $castIf(CBLBlob, _dict[key]);
}


- (nullable CBLMutableArray*) arrayForKey: (NSString*)key {
    return $castIf(CBLMutableArray, [self objectForKey: key]);
}


- (nullable CBLMutableDictionary*) dictionaryForKey: (NSString*)key {
    return $castIf(CBLMutableDictionary, [self objectForKey: key]);
}


#pragma mark - Check Existence


- (BOOL) containsValueForKey: (NSString*)key {
    return _dict[key] != nil;
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


- (void) setValue: (nullable id)value forKey: (NSString*)key {
    [self setObject: value forKey: key];
}


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    if (value == nil) value = [NSNull null]; // Store NSNull
    value = [value cbl_toCBLObject];
    id oldValue = _dict[key];
    if (value != oldValue && ![value isEqual: oldValue]) {
        _dict[key] = value;
        _changed = true;
    }
}


- (void) setString: (nullable NSString *)value forKey: (NSString *)key {
    [self setValue: value forKey: key];
}


- (void) removeValueForKey: (NSString *)key {
    if (_dict[key]) {
        [_dict removeObjectForKey: key];
        _changed = true;
    }
}


- (void) setDictionary: (nullable NSDictionary<NSString*,id>*)dictionary {
    _dict = [dictionary mutableCopy];
    _changed = true;
}


#pragma mark - Convert to NSDictionary


- (NSDictionary<NSString*,id>*) toDictionary {
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity: _dict.count];
    [_dict enumerateKeysAndObjectsUsingBlock: ^(id key, id obj, BOOL* stop) {
        result[key] = [obj cbl_toPlainObject];
    }];
    return result;
}


#pragma mark - Mutable


- (CBLMutableDictionary*) toMutable {
    return [self mutableCopy];
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    return [_dict countByEnumeratingWithState: state objects: buffer count: len];
}


#pragma mark - SUBSCRIPTING


- (CBLMutableFragment*) objectForKeyedSubscript: (NSString*)key {
    return [[CBLMutableFragment alloc] initWithParent: self key: key];
}


#pragma mark - CBLConversion


- (id) cbl_toPlainObject {
    return [self toDictionary];
}


- (id) cbl_toCBLObject {
    return self;
}


@end
