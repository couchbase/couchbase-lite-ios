//
//  CBLDictionary.m
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
#import "CBLJSON.h"
#import "CBLSubdocument.h"


@implementation CBLDictionary {
    NSMutableDictionary<NSString*, id>* _dict;
    NSMapTable* _changeListeners;
    BOOL _changed;
}


@synthesize changed=_changed;


static id kRemovedValue;
+ (void) initialize {
    if (self == [CBLDictionary class]) {
        kRemovedValue = [[NSObject alloc] init];
    }
}

- /* internal */ (instancetype) initWithData: (id<CBLReadOnlyDictionary>)data {
    self = [super initWithData: data];
    if (self) {
        _dict = [NSMutableDictionary dictionary];
    }
    return self;
}


#pragma mark - GETTER


- (NSUInteger) count {
    __block NSUInteger count = _dict.count;
    for (NSString* key in [super allKeys]) {
        if (!_dict[key])
            count += 1;
    }
    
    [_dict enumerateKeysAndObjectsUsingBlock: ^(NSString *key, id value, BOOL *stop) {
        if (value == kRemovedValue)
            count -= 1;
    }];
    return count;
}


- (nullable id) objectForKey: (NSString*)key {
    id value = _dict[key];
    if (!value) {
        value = [super objectForKey: key];
        if ([value isKindOfClass: [CBLReadOnlySubdocument class]]) {
            value = [self convertReadOnlySubdocument: value];
            [self setValue: value forKey: key isChange: NO];
        } else if ([value isKindOfClass: [CBLReadOnlyArray class]]) {
            value = [self convertReadOnlyArray: value];
            [self setValue: value forKey: key isChange: NO];
        }
    } else if (value == kRemovedValue)
        value = nil;
    if (value == [NSNull null])
        value = nil; // Cross-platform behavior
    return value;
}


- (BOOL) booleanForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super booleanForKey: key];
    else {
        if (value == kRemovedValue)
            return NO;
        else if (value == [NSNull null])
            return NO;
        else {
            id n = $castIf(NSNumber, value);
            return n ? [n boolValue] : YES;
        }
    }
}


- (NSInteger) integerForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super integerForKey: key];
    else
        return [$castIf(NSNumber, value) integerValue];
}


- (float) floatForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super floatForKey: key];
    else
        return [$castIf(NSNumber, value) floatValue];
}


- (double) doubleForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super doubleForKey: key];
    else
        return [$castIf(NSNumber, value) doubleValue];
}


- (nullable NSString*) stringForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super stringForKey: key];
    else
        return $castIf(NSString, value);
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super numberForKey: key];
    else
        return $castIf(NSNumber, value);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [CBLJSON dateWithJSONObject: [self stringForKey: key]];
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super blobForKey: key];
    else
        return $castIf(CBLBlob, value);
}


- (nullable CBLSubdocument*) subdocumentForKey: (NSString*)key {
    id value = _dict[key];
    if (!value) {
        value = [super subdocumentForKey: key];
        if ([value isKindOfClass: [CBLReadOnlySubdocument class]]) {
            value = [self convertReadOnlySubdocument: value];
            [self setValue: value forKey: key isChange: NO];
        }
        return value;
    } else
        return $castIf(CBLSubdocument, value);
}


- (nullable CBLArray*) arrayForKey: (NSString*)key {
    id value = _dict[key];
    if (!value) {
        value = [super arrayForKey: key];
        if ([value isKindOfClass: [CBLReadOnlyArray class]]) {
            value = [self convertReadOnlyArray: value];
            [self setValue: value forKey: key isChange: NO];
        }
        return value;
    } else
        return $castIf(CBLArray, value);
}


- (BOOL) containsObjectForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super containsObjectForKey: key];
    else
        return value != kRemovedValue ? YES : NO;
}


- (NSArray*) allKeys {
    NSMutableSet* result = [NSMutableSet setWithArray: [_dict allKeys]];
    for (NSString* key in [super allKeys]) {
        if (![result containsObject: key])
            [result addObject: key];
    }
    
    [_dict enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (value == kRemovedValue)
            [result removeObject: key];
    }];
    
    return [result allObjects];
}


- (NSDictionary<NSString*,id>*) toDictionary {
    NSMutableDictionary* result = [_dict mutableCopy];
    
    // Backing data:
    NSDictionary* backingData = [super toDictionary];
    [backingData enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        if (!result[key])
            result[key] = value;
    }];
    
    for (NSString* key in [result allKeys]) {
        id value = result[key];
        if (value == kRemovedValue)
            result[key] = nil; // Remove key
        else if ([value conformsToProtocol: @protocol(CBLReadOnlyDictionary)])
            result[key] = [value toDictionary];
        else if ([value conformsToProtocol: @protocol(CBLReadOnlyArray)])
            result[key] = [value toArray];
    }
    
    return result;
}


#pragma mark - SETTER


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    id oldValue = [self objectForKey: key];
    if (!$equal(value, oldValue)) {
        value = [self prepareValue: value];
        [self detachChangeListenerForObject: oldValue];
        [self setValue: value forKey: key isChange: YES];
    }
}


- (void) setBoolean: (BOOL)value forKey: (NSString*)key {
    [self setObject: @(value) forKey: key];
}


- (void) setInteger: (NSInteger)value forKey: (NSString*)key {
    [self setObject: @(value) forKey: key];
}


- (void) setFloat: (float)value forKey: (NSString*)key {
    [self setObject: @(value) forKey: key];
}


- (void) setDouble: (double)value forKey: (NSString*)key {
    [self setObject: @(value) forKey: key];
}


- (void) removeObjectForKey: (NSString*)key {
    [self setObject: nil forKey: key];
}


- (void) setDictionary: (NSDictionary<NSString*,id>*)dictionary {
    // Detach all objects that we are listening to for changes:
    [self detachChildChangeListeners];
    
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    [dictionary enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        result[key] = [self prepareValue: value];
    }];
    
    // Marked the key as removed by setting the value to NSNull:
    NSDictionary* backingData = [super toDictionary];
    [backingData enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        if (!result[key])
            result[key] = kRemovedValue;
    }];
    
    _dict = result;
    
    [self setChanged];
}


#pragma mark - INTERNAL


- (BOOL) isEmpty {
    __block BOOL isEmpty = YES;
    [_dict enumerateKeysAndObjectsUsingBlock: ^(NSString *key, id value, BOOL *stop) {
        if (value != kRemovedValue) {
            isEmpty = NO;
            *stop = YES;
        }
    }];
    
    if (isEmpty)
        isEmpty = super.isEmpty;
    return isEmpty;
}


#pragma mark - FLEECE ENCODING


- (BOOL) isFleeceEncodableValue: (id)value {
    return value != kRemovedValue;
}


#pragma mark - PRIVATE


- (nullable id) prepareValue: (nullable id)value {
    Assert([CBLData validateValue: value], @"Unsupported value type.");
    return [self convertValue: value];
}


- (id) convertValue: (id)value {
    if (!value)
        return kRemovedValue; // Represent removed key
    else if ([value isKindOfClass: [CBLSubdocument class]])
        return [self convertSubdocument: value];
    else if ([value isKindOfClass: [CBLArray class]])
        return [self convertArrayObject: value];
    else if ([value isKindOfClass: [CBLReadOnlySubdocument class]])
        return [self convertReadOnlySubdocument: value];
    else if ([value isKindOfClass: [CBLReadOnlyArray class]])
        return [self convertReadOnlyArray: value];
    else if ([value isKindOfClass: [NSDictionary class]])
        return [self convertDictionary: value];
    else if ([value isKindOfClass: [NSArray class]])
        return [self convertArray: value];
    else if ([value isKindOfClass: [NSDate class]])
        return [CBLJSON JSONObjectWithDate: value];
    return value;
}


- (id) convertSubdocument: (CBLSubdocument*)subdocument {
    [subdocument.dictionary addChangeListener: self];
    return subdocument;
}


- (id) convertArrayObject: (CBLArray*)array {
    [array addChangeListener: self];
    return array;
}


- (id) convertReadOnlySubdocument: (CBLReadOnlySubdocument*)readOnlySubdoc {
    CBLSubdocument* subdocument = [[CBLSubdocument alloc] initWithData: readOnlySubdoc.data];
    [subdocument.dictionary addChangeListener: self];
    return subdocument;
}


- (id) convertReadOnlyArray: (CBLReadOnlyArray*)readOnlyArray {
    CBLArray* array = [[CBLArray alloc] initWithData: readOnlyArray.data];
    [array addChangeListener: self];
    return array;
}


- (id) convertDictionary: (NSDictionary*)dictionary {
    CBLSubdocument* subdocument = [[CBLSubdocument alloc] init];
    [subdocument setDictionary: dictionary];
    [subdocument.dictionary addChangeListener: self];
    return subdocument;
}


- (id) convertArray: (NSArray*)array {
    CBLArray* arrayObject = [[CBLArray alloc] init];
    [arrayObject setArray: array];
    [arrayObject addChangeListener: self];
    return arrayObject;
}


- (void) setValue: (id)value forKey: (NSString*)key isChange: (BOOL)isChange {
    _dict[key] = value;
    if (isChange)
        [self setChanged];
}


#pragma mark - CHANGE


- (void) setChanged {
    if (!_changed) {
        _changed = YES;
        [self notifyChangeListeners];
    }
}


- (void) addChangeListener: (id<CBLObjectChangeListener>)listener {
    if (!_changeListeners)
        _changeListeners = [NSMapTable weakToStrongObjectsMapTable];
    NSInteger count = [[_changeListeners objectForKey: listener] integerValue] + 1;
    [_changeListeners setObject: @(count) forKey: listener];
}


- (void) removeChangeListener: (id<CBLObjectChangeListener>)listener {
    NSInteger count = [[_changeListeners objectForKey: listener] integerValue] - 1;
    if (count > 0)
        [_changeListeners setObject: listener forKey: @(count)];
    else
        [_changeListeners removeObjectForKey: listener];
}


- (void) detachChildChangeListeners {
    for (NSString* key in _dict) {
        [self detachChangeListenerForObject: _dict[key]];
    }
}


- (void) detachChangeListenerForObject: (id)object {
    if ([object isKindOfClass: [CBLSubdocument class]]) {
        CBLSubdocument* subdocument = (CBLSubdocument*)object;
        [subdocument.dictionary removeChangeListener: self];
    } else if ([object isKindOfClass: [CBLArray class]]) {
        CBLArray* array = (CBLArray*)object;
        [array removeChangeListener: self];
    }
}


- (void) notifyChangeListeners {
    for (id<CBLObjectChangeListener> listener in _changeListeners) {
        [listener objectDidChange: self];
    }
}


#pragma mark - CBLObjectChangeListener


- (void) objectDidChange: (id)object {
    [self setChanged];
}


@end
