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
#import "CBLSubdocument.h"


@implementation CBLDictionary {
    NSMutableDictionary<NSString*, id>* _dict;
    NSMapTable* _changeListeners;
    BOOL _changed;
}


@synthesize changed=_changed;


#pragma mark - GETTER


- (NSUInteger) count {
    __block NSUInteger count = _dict.count;
    if (count == 0)
        return super.count;
    
    for (NSString* key in [super allKeys]) {
        if (!_dict[key])
            count += 1;
    }
    
    [_dict enumerateKeysAndObjectsUsingBlock: ^(NSString *key, id value, BOOL *stop) {
        if (value == kCBLRemovedValue)
            count -= 1;
    }];
    return count;
}


- (nullable id) objectForKey: (NSString*)key {
    id value = _dict[key];
    if (!value) {
        value = [super objectForKey: key];
        if ([value isKindOfClass: [CBLReadOnlySubdocument class]]) {
            value = [CBLData convertValue: value listener: self];
            [self setValue: value forKey: key isChange: NO];
        } else if ([value isKindOfClass: [CBLReadOnlyArray class]]) {
            value = [CBLData convertValue: value listener: self];
            [self setValue: value forKey: key isChange: NO];
        }
    } else if (value == kCBLRemovedValue)
        value = nil;
    return value;
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
    return $castIf(NSString, [self objectForKey: key]);
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return $castIf(NSNumber, [self objectForKey: key]);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [CBLJSON dateWithJSONObject: [self objectForKey: key]];
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return $castIf(CBLBlob, [self objectForKey:key]);
}


- (nullable CBLSubdocument*) subdocumentForKey: (NSString*)key {
    return $castIf(CBLSubdocument, [self objectForKey:key]);
}


- (nullable CBLArray*) arrayForKey: (NSString*)key {
    return $castIf(CBLArray, [self objectForKey: key]);
}


- (BOOL) containsObjectForKey: (NSString*)key {
    id value = _dict[key];
    if (!value)
        return [super containsObjectForKey: key];
    else
        return value != kCBLRemovedValue;
}


- (NSArray*) allKeys {
    NSMutableSet* result = [NSMutableSet setWithArray: [_dict allKeys]];
    for (NSString* key in [super allKeys]) {
        if (![result containsObject: key])
            [result addObject: key];
    }
    
    [_dict enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (value == kCBLRemovedValue)
            [result removeObject: key];
    }];
    
    return [result allObjects];
}


- (NSDictionary<NSString*,id>*) toDictionary {
    NSMutableDictionary* result = _dict ? [_dict mutableCopy] : [NSMutableDictionary dictionary];
    
    // Backing data:
    NSDictionary* backingData = [super toDictionary];
    [backingData enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        if (!result[key])
            result[key] = value;
    }];
    
    for (NSString* key in [result allKeys]) {
        id value = result[key];
        if (value == kCBLRemovedValue)
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
        value = [CBLData convertValue: value listener: self];
        [self detachChangeListenerForObject: oldValue];
        [self setValue: value forKey: key isChange: YES];
    }
}


- (void) setDictionary: (NSDictionary<NSString*,id>*)dictionary {
    // Detach all objects that we are listening to for changes:
    [self detachChildChangeListeners];
    
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    [dictionary enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        result[key] = [CBLData convertValue: value listener: self];
    }];
    
    // Marked the key as removed by setting the value to kRemovedValue:
    NSDictionary* backingData = [super toDictionary];
    [backingData enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        if (!result[key])
            result[key] = kCBLRemovedValue;
    }];
    
    _dict = result;
    
    [self setChanged];
}


- (void) removeObjectForKey: (NSString*)key {
    [self setObject: nil forKey: key];
}


#pragma mark - SUBSCRIPTING


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    id value = [self objectForKey: key];
    return [[CBLFragment alloc] initWithValue: value parent: self parentKey: key];
}


#pragma mark - INTERNAL


- (BOOL) isEmpty {
    if (_dict.count == 0)
        return super.count == 0;
    
    for (NSString* key in [super allKeys]) {
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


#pragma mark - PRIVATE


- (void) setValue: (id)value forKey: (NSString*)key isChange: (BOOL)isChange {
    if (!_dict)
        _dict = [NSMutableDictionary dictionary];
    
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


#pragma mark - FLEECE ENCODABLE


- (BOOL) fleeceEncode: (FLEncoder)encoder
             database: (CBLDatabase*)database
                error: (NSError**)outError
{
    NSArray* keys = [self allKeys];
    FLEncoder_BeginDict(encoder, keys.count);
    for (NSString* key in keys) {
        id value = [self objectForKey: key];
        if (value != kCBLRemovedValue) {
            CBLStringBytes bKey(key);
            FLEncoder_WriteKey(encoder, bKey);
            if ([value conformsToProtocol: @protocol(CBLFleeceEncodable)]){
                if (![value fleeceEncode: encoder database: database error: outError])
                    return NO;
            } else
                FLEncoder_WriteNSObject(encoder, value);
        }
    }
    FLEncoder_EndDict(encoder);
    return YES;
}



@end
