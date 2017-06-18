//
//  CBLDictionary.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDictionary.h"
#import "CBLDictionary+Swift.h"
#import "CBLArray.h"
#import "CBLBlob.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLFragment.h"
#import "CBLJSON.h"
#import "CBLLock.h"
#import "CBLStringBytes.h"


@implementation CBLDictionary {
    NSMutableDictionary<NSString*, id>* _dict;
    NSMapTable* _changeListeners;
    BOOL _changed;
    NSArray* _keys; // key cache
    CBLLock* _lock; // Recursive lock
    CBLLock* _changedLock;
}


@synthesize changed=_changed, swiftObject=_swiftObject;


+ (instancetype) dictionary {
    return [[self alloc] init];
}


- /* internal */ (instancetype) initWithFleeceData: (nullable CBLFLDict*)data {
    self = [super initWithFleeceData: data];
    if (self) {
        _lock = [[CBLLock alloc] initWithName: @"Dictionary" recursive: YES];
        _changedLock = [[CBLLock alloc] initWithName: @"Dictionary-Changed"];self.data = data;
    }
    return self;
}


- (instancetype) init {
    return [self initWithFleeceData: nil];
}


- (instancetype) initWithDictionary: (NSDictionary<NSString*,id>*)dictionary {
    self = [self init];
    if (self) {
        [self setDictionary: dictionary];
    }
    return self;
}


#pragma mark - GETTER


- (NSUInteger) count {
    [_lock lock];
    
    if (!_changed) {
        [_lock unlock];
        return super.count;
    }
    
    __block NSUInteger count = _dict.count;
    for (NSString* key in super.keys) {
        if (!_dict[key])
            count += 1;
    }
    
    [_dict enumerateKeysAndObjectsUsingBlock: ^(NSString *key, id value, BOOL *stop) {
        if (value == kCBLRemovedValue)
            count -= 1;
    }];
    
    [_lock unlock];
    
    return count;
}


- (NSArray*) keys {
    [_lock lock];
    
    NSArray* keys;
    if (!_changed)
        keys = super.keys;
    else
        keys = [[self allKeys] copy];
    
    [_lock unlock];
    
    return keys;
}


- (nullable id) objectForKey: (NSString*)key {
    [_lock lock];
    id value = _dict[key];
    if (!value) {
        value = [super objectForKey: key];
        if ([value isKindOfClass: [CBLReadOnlyDictionary class]]) {
            value = [CBLData convertValue: value listener: self];
            [self setValue: value forKey: key isChange: NO];
        } else if ([value isKindOfClass: [CBLReadOnlyArray class]]) {
            value = [CBLData convertValue: value listener: self];
            [self setValue: value forKey: key isChange: NO];
        }
    } else if (value == kCBLRemovedValue)
        value = nil;
    [_lock unlock];
    return value;
}


- (BOOL) booleanForKey: (NSString*)key {
    [_lock lock];
    id value = _dict[key];
    [_lock unlock];
    
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
    [_lock lock];
    id value = _dict[key];
    [_lock unlock];
    
    if (!value)
        return [super integerForKey: key];
    else
        return [$castIf(NSNumber, value) integerValue];
}


- (float) floatForKey: (NSString*)key {
    [_lock lock];
    id value = _dict[key];
    [_lock unlock];
    
    if (!value)
        return [super floatForKey: key];
    else
        return [$castIf(NSNumber, value) floatValue];
}


- (double) doubleForKey: (NSString*)key {
    [_lock lock];
    id value = _dict[key];
    [_lock unlock];
    
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


- (nullable CBLDictionary*) dictionaryForKey: (NSString*)key {
    return $castIf(CBLDictionary, [self objectForKey: key]);
}


- (nullable CBLArray*) arrayForKey: (NSString*)key {
    return $castIf(CBLArray, [self objectForKey: key]);
}


- (BOOL) containsObjectForKey: (NSString*)key {
    [_lock lock];
    id value = _dict[key];
    [_lock unlock];
    
    if (!value)
        return [super containsObjectForKey: key];
    else
        return value != kCBLRemovedValue;
}


- (NSDictionary<NSString*,id>*) toDictionary {
    [_lock lock];
    NSMutableDictionary* result = _dict ? [_dict mutableCopy] : [NSMutableDictionary dictionary];
    [_lock unlock];
    
    // Backing data:
    NSDictionary* backingData = [super toDictionary];
    [backingData enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        if (!result[key])
            result[key] = value;
    }];
    
    for (NSString* key in result.allKeys) {
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


- (void) setDictionary: (nullable NSDictionary<NSString*,id>*)dictionary {
    [_lock lock];
    
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
    
    [_lock unlock];
}


- (void) setObject: (nullable id)value forKey: (NSString*)key {
    if (!value) value = [NSNull null]; // nil conversion only for apple platform
    
    [_lock lock];
    id oldValue = [self objectForKey: key];
    if (!$equal(value, oldValue)) {
        value = [CBLData convertValue: value listener: self];
        [self detachChangeListenerForObject: oldValue];
        [self setValue: value forKey: key isChange: YES];
        _keys = nil; // Reset key cahche
    }
    [_lock unlock];
}


- (void) removeObjectForKey: (NSString *)key {
    if ([self containsObjectForKey: key]) {
        [self setObject: kCBLRemovedValue forKey: key];
    }
}


#pragma mark - NSFastEnumeration


- (NSUInteger) countByEnumeratingWithState: (NSFastEnumerationState *)state
                                   objects: (id __unsafe_unretained [])buffer
                                     count: (NSUInteger)len
{
    NSUInteger count;
    [_lock lock];
    if (!_changed)
        count = [super countByEnumeratingWithState: state objects: buffer count: len];
    else
        count = [[self allKeys] countByEnumeratingWithState: state objects: buffer count: len];
    [_lock unlock];
    return count;
}


#pragma mark - SUBSCRIPTING


- (CBLFragment*) objectForKeyedSubscript: (NSString*)key {
    id value = [self objectForKey: key];
    return [[CBLFragment alloc] initWithValue: value parent: self parentKey: key];
}


#pragma mark - INTERNAL


- (BOOL) changed {
    [_changedLock lock];
    BOOL isChanged = _changed;
    [_changedLock unlock];
    return isChanged;
}


- (BOOL) isEmpty {
    [_lock lock];
    if (!_changed)
        return super.isEmpty;
    
    for (NSString* key in super.keys) {
        if (!_dict[key]) {
            [_lock unlock];
            return NO;
        }
    }
    
    __block BOOL isEmpty = YES;
    [_dict enumerateKeysAndObjectsUsingBlock: ^(NSString *key, id value, BOOL *stop) {
        if (value != kCBLRemovedValue) {
            isEmpty = NO;
            *stop = YES;
        }
    }];
    [_lock unlock];
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


- (NSArray*) allKeys {
    if (!_keys) {
        NSMutableSet* result = [NSMutableSet setWithArray: _dict.allKeys];
        for (NSString* key in super.keys) {
            if (![result containsObject: key])
                [result addObject: key];
        }
        
        [_dict enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (value == kCBLRemovedValue)
                [result removeObject: key];
        }];
        _keys = [result allObjects];
    }
    return _keys;
}


#pragma mark - CHANGE


- (void) setChanged {
    // Has it own _changedLock instead of using the _lock to avoid deadlock when encoding
    // the object into fleece and at the same time there are some changes in a child
    // dictionary or array by another thread. There is one side effect of doing this is that
    // the changed status could be NO when one thread is trying to get the changed status
    // but the other thread is modifying the object at the same time.
    [_changedLock lock];
    if (!_changed) {
        _changed = YES;
        [self notifyChangeListeners];
    }
    [_changedLock unlock];
}


- (void) addChangeListener: (id<CBLObjectChangeListener>)listener {
    [_changedLock lock];
    if (!_changeListeners)
        _changeListeners = [NSMapTable weakToStrongObjectsMapTable];
    NSInteger count = [[_changeListeners objectForKey: listener] integerValue] + 1;
    [_changeListeners setObject: @(count) forKey: listener];
    [_changedLock unlock];
}


- (void) removeChangeListener: (id<CBLObjectChangeListener>)listener {
    [_changedLock lock];
    NSInteger count = [[_changeListeners objectForKey: listener] integerValue] - 1;
    if (count > 0)
        [_changeListeners setObject: listener forKey: @(count)];
    else
        [_changeListeners removeObjectForKey: listener];
    [_changedLock unlock];
}


- (void) notifyChangeListeners {
    for (id<CBLObjectChangeListener> listener in _changeListeners) {
        [listener objectDidChange: self];
    }
}


- (void) detachChildChangeListeners {
    for (NSString* key in _dict) {
        [self detachChangeListenerForObject: _dict[key]];
    }
}


- (void) detachChangeListenerForObject: (id)object {
    if ([object isKindOfClass: [CBLDictionary class]]) {
        CBLDictionary* dict = (CBLDictionary*)object;
        [dict removeChangeListener: self];
    } else if ([object isKindOfClass: [CBLArray class]]) {
        CBLArray* array = (CBLArray*)object;
        [array removeChangeListener: self];
    }
}


#pragma mark - CBLObjectChangeListener


- (void) objectDidChange: (id)object {
    [self setChanged];
}


#pragma mark - FLEECE ENCODABLE


- (BOOL) fleeceEncode: (FLEncoder)encoder
             database: (CBLDatabase*)database
                error: (NSError* __autoreleasing *)outError
{
    __block BOOL success = YES;
    [_lock withLock: ^{
        NSArray* keys = self.allKeys;
        FLEncoder_BeginDict(encoder, keys.count);
        for (NSString* key in keys) {
            id value = [self objectForKey: key];
            if (value != kCBLRemovedValue) {
                CBLStringBytes bKey(key);
                FLEncoder_WriteKey(encoder, bKey);
                if ([value conformsToProtocol: @protocol(CBLFleeceEncodable)]){
                    if (![value fleeceEncode: encoder database: database error: outError]) {
                        success = NO;
                        return;
                    }
                } else
                    FLEncoder_WriteNSObject(encoder, value);
            }
        }
        FLEncoder_EndDict(encoder);
    }];
    return success;
}


@end
