//
//  CBLDictionary.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDictionaryObject.h"
#import "CBLBlob.h"
#import "CBLDictionaryData.h"
#import "CBLDocumentInternal.h"
#import "CBLJSON.h"
#import "CBLReadOnlyDocumentInternal.h"

@implementation CBLDictionaryObject {
    NSMutableDictionary<NSString*, id>* _dict;
    NSMapTable* _changeListeners;
    BOOL _changed;
}


- (instancetype) initWithData: (CBLDictionaryData*)data {
    self = [super initWithData: data];
    if (self) {
        _dict = [NSMutableDictionary dictionary];
    }
    return self;
}


#pragma mark - GETTER


- (NSDictionary<NSString*, id>*) properties {
    if (self.data.data) {
        // Bring the backing data up:
        NSDictionary* backingData = [super properties];
        [backingData enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
            if (!_dict[key])
                _dict[key] = [self prepareValue: value];
        }];
        // Detach backing data as all backing data has been brought up:
        self.data = [[CBLDictionaryData alloc] init]; // EMPTY
    }
    
    // Filter out keys that have NSNull value to make the result
    // the same across platforms (Java and .NET do not have NSNull
    // equivalent value):
    NSMutableDictionary* result = [_dict mutableCopy];
    for (NSString* key in _dict) {
        if (result[key] == [NSNull null])
            result[key] = nil;
    }
    return result;
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
    } else if (value == [NSNull null])
        value = nil; // Cross-platform behavior
    return value;
}


- (BOOL) booleanForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super booleanForKey: key];
    else {
        if (value == [NSNull null])
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
        return value != [NSNull null] ? YES : NO;
}


#pragma mark - SETTER


- (void) setProperties: (NSDictionary<NSString*, id>*)properties {
    if (_dict == properties)
        return;
    
    // Detach backing data:
    self.data = [[CBLDictionaryData alloc] init]; // EMPTY
    
    // Detach all objects that we are listening to for changes:
    [self detachChildChangeListeners];
    
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    [properties enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        result[key] = [self prepareValue: value];
    }];
    
    _dict = result;
    
    [self setChanged];
}


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    id oldValue = [self objectForKey: key];
    if (!$equal(value, oldValue)) {
        [self detachChangeListenerForObject: oldValue];
        value = [self prepareValue: value];
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


#pragma mark - CHANGE LISTENER


- (void) addChangeListener: (id<CBLObjectChangeListener>)listener {
    if (!_changeListeners)
        _changeListeners = [NSMapTable weakToStrongObjectsMapTable];
    NSInteger count = [[_changeListeners objectForKey: listener] integerValue] + 1;
    [_changeListeners setObject: listener forKey: @(count)];
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
    for (id <CBLObjectChangeListener> listener in _changeListeners) {
        [listener objectDidChange: self];
    }
}


#pragma mark - CHANGE LISTENING


- (void) objectDidChange: (id)object {
    [self setChanged];
}


#pragma mark - PRIVATE


- (nullable id) prepareValue: (nullable id)value {
    value = [self convertValue: value];
    if (![self validateValue: value]) {
        // TODO: Throw Error
    }
    return value;
}


- (id) convertValue: (id)value {
    if (!value)
        return [NSNull null];
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
    // subdocument.properties = dictionary; // TODO
    [subdocument.dictionary addChangeListener: self];
    return subdocument;
}


- (id) convertArray: (NSArray*)array {
    CBLArray* arrayObject = [[CBLArray alloc] init];
    // arrayObject.items = array; // TODO
    [arrayObject addChangeListener: self];
    return arrayObject;
}


- (void) setValue: (id)value forKey: (NSString*)key isChange: (BOOL)isChange {
    _dict[key] = value;
    if (isChange)
        [self setChanged];
}


- (void) setChanged {
    _changed = YES;
    [self notifyChangeListeners];
}


- (BOOL) validateValue: (id)value {
    return value == nil ||
           [value isKindOfClass: [NSString class]] ||
           [value isKindOfClass: [NSNumber class]] ||
           [value isKindOfClass: [CBLBlob class]] ||
           [value isKindOfClass: [CBLSubdocument class]] ||
           [value isKindOfClass: [CBLArray class]] ||
           [value isKindOfClass: [CBLReadOnlySubdocument class]] ||
           [value isKindOfClass: [CBLReadOnlyArray class]] ||
           [value isKindOfClass: [NSDate class]] ||
           [value isKindOfClass: [NSDictionary class]] ||
           [value isKindOfClass: [NSArray class]];
}


@end
