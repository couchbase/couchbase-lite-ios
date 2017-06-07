//
//  CBLArray.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLArray.h"
#import "CBLArray+Swift.h"
#import "CBLBlob.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"
#import "CBLLock.h"


@implementation CBLArray {
    NSMutableArray* _array;
    NSMapTable* _changeListeners;
    BOOL _changed;
    CBLLock* _lock; // Recursive lock
    CBLLock* _changedLock;
}

@synthesize swiftObject=_swiftObject;


+ (instancetype) array {
    return [[self alloc] init];
}


- /* internal */ (instancetype) initWithFleeceData: (nullable CBLFLArray*)data {
    self = [super initWithFleeceData: data];
    if (self) {
        _lock = [[CBLLock alloc] initWithName: @"Array" recursive: YES];
        _changedLock = [[CBLLock alloc] initWithName: @"Array-Changed"];
    }
    return self;
}


- (instancetype) init {
    return [self initWithFleeceData: nil];
}


- (instancetype) initWithArray: (NSArray*)array {
    self = [self init];
    if (self) {
        [self setArray: array];
    }
    return self;
}


#pragma mark - GETTER


- (nullable id) objectAtIndex: (NSUInteger)index {
    __block id value = nil;
    [_lock withLock: ^{
        if (!_array) {
            value = [super objectAtIndex: index];
            if ([value isKindOfClass: [CBLReadOnlyDictionary class]] ||
                [value isKindOfClass: [CBLReadOnlyArray class]]) {
                [self copyFleeceData];
            } else
                return;
        }
        value = _array[index];
    }];
    return value;
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    __block BOOL value;
    [_lock withLock: ^{
        if (!_array)
            value = [super booleanAtIndex: index];
        else
            value = [CBLData booleanValueForObject: _array[index]];
    }];
    return value;
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    __block NSInteger value;
    [_lock withLock: ^{
        if (!_array)
            value = [super integerAtIndex: index];
        else
            value = [$castIf(NSNumber, _array[index]) integerValue];
    }];
    return value;
}


- (float) floatAtIndex: (NSUInteger)index {
    __block float value;
    [_lock withLock: ^{
        if (!_array)
            value = [super floatAtIndex: index];
        else
            value = [$castIf(NSNumber, _array[index]) floatValue];
    }];
    return value;
}


- (double) doubleAtIndex: (NSUInteger)index {
    __block double value;
    [_lock withLock: ^{
        if (!_array)
            value = [super doubleAtIndex: index];
        else
            value = [$castIf(NSNumber, _array[index]) doubleValue];
    }];
    return value;
}


- (nullable NSString*) stringAtIndex: (NSUInteger)index {
    return $castIf(NSString, [self objectAtIndex: index]);
}


- (nullable NSNumber*) numberAtIndex: (NSUInteger)index {
    return $castIf(NSNumber, [self objectAtIndex: index]);
}


- (nullable NSDate*) dateAtIndex: (NSUInteger)index {
    return [CBLJSON dateWithJSONObject: [self objectAtIndex: index]];
}


- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index {
    return $castIf(CBLBlob, [self objectAtIndex: index]);
}


- (nullable CBLArray*) arrayAtIndex: (NSUInteger)index {
    return $castIf(CBLArray, [self objectAtIndex: index]);
}


- (nullable CBLDictionary*) dictionaryAtIndex: (NSUInteger)index {
    return $castIf(CBLDictionary, [self objectAtIndex: index]);
}


- (NSUInteger) count {
    __block NSUInteger count;
    [_lock withLock: ^{
        if (!_array) {
            count = super.count;
        } else
            count = _array.count;
    }];
    return count;
}


- (NSArray*) toArray {
    __block NSMutableArray* array = [NSMutableArray array];
    [_lock withLock: ^{
        if (!_array)
            [self copyFleeceData];
        for (id item in _array) {
            id value = item;
            if ([value conformsToProtocol: @protocol(CBLReadOnlyDictionary)])
                value = [value toDictionary];
            else if ([value conformsToProtocol: @protocol(CBLReadOnlyArray)])
                value = [value toArray];
            [array addObject: value];
        }
    }];
    return array;
}


#pragma mark - SETTER


- (void) setArray:(nullable NSArray *)array {
    [_lock withLock: ^{
        // Detach all objects that we are listening to for changes:
        [self detachChildChangeListeners];
        
        NSMutableArray* result = [NSMutableArray arrayWithCapacity: [array count]];
        for (id value in array) {
            [result addObject: [CBLData convertValue: value listener: self]];
        }
        
        _array = result;
        [self setChanged];
    }];
}


- (void) setObject: (id)value atIndex: (NSUInteger)index {
    __block id v = value ? value : [NSNull null]; // nil conversion only for apple platform
    [_lock withLock: ^{
        id oldValue = [self objectAtIndex: index];
        if (!$equal(value, oldValue)) {
            v = [CBLData convertValue: v listener: self];
            [self detachChangeListenerForObject: oldValue];
            [self setValue: v atIndex: index isChange: YES];
        }
    }];
}


- (void) addObject: (id)value  {
    if (!value) value = [NSNull null]; // nil conversion only for apple platform
    [_lock withLock: ^{
        if (!_array)
            [self copyFleeceData];
        [_array addObject: [CBLData convertValue: value listener: self]];
        [self setChanged];
    }];
}


- (void) insertObject: (id)value atIndex: (NSUInteger)index {
    if (!value) value = [NSNull null]; // nil conversion only for apple platform
    [_lock withLock: ^{
        if (!_array)
            [self copyFleeceData];
        [_array insertObject: [CBLData convertValue: value listener: self] atIndex: index];
        [self setChanged];
    }];
}


- (void) removeObjectAtIndex: (NSUInteger)index {
    [_lock withLock: ^{
        if (!_array)
            [self copyFleeceData];
        id value = _array[index];
        [self detachChangeListenerForObject: value];
        [_array removeObjectAtIndex: index];
        [self setChanged];
    }];
}


#pragma mark - NSFastEnumeration


- (NSUInteger) countByEnumeratingWithState: (NSFastEnumerationState *)state
                                   objects: (id __unsafe_unretained [])buffer
                                     count: (NSUInteger)len
{
    NSUInteger count;
    [_lock lock];
    if (!_array)
        count = [super countByEnumeratingWithState: state objects: buffer count: len];
    else
        count = [_array countByEnumeratingWithState: state objects: buffer count: len];
    [_lock unlock];
    return count;
}


#pragma mark - SUBSCRIPTING


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    id value = index < self.count ? [self objectAtIndex: index] : nil;
    return [[CBLFragment alloc] initWithValue: value parent: self parentKey: @(index)];
}


#pragma mark - CHANGE LISTENER


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
        [_changeListeners setObject: @(count) forKey: listener];
    else
        [_changeListeners removeObjectForKey: listener];
    [_changedLock unlock];
}


- (void) detachChildChangeListeners {
    for (id object in _array) {
        [self detachChangeListenerForObject: object];
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


#pragma mark - CHANGED


- (BOOL) changed {
    // Has it own _changedLock instead of using the _lock to avoid deadlock when encoding
    // the object into fleece and at the same time there are some changes in a child
    // dictionary or array by another thread. There is one side effect of doing this is that
    // the changed status could be NO when one thread is trying to get the changed status
    // but the other thread is modifying the object at the same time.
    [_changedLock lock];
    BOOL isChanged = _changed;
    [_changedLock unlock];
    return isChanged;
}


- (void) setChanged {
    [_changedLock lock];
    if (!_changed) {
        _changed = YES;
        [self notifyChangeListeners];
    }
    [_changedLock unlock];
}


- (void) objectDidChange: (id)object {
    [self setChanged];
}


- (void) notifyChangeListeners {
    for (id <CBLObjectChangeListener> listener in _changeListeners) {
        [listener objectDidChange: self];
    }
}

#pragma mark - FLEECE ENCODABLE


- (BOOL) fleeceEncode: (FLEncoder)encoder
             database: (CBLDatabase*)database
                error: (NSError* __autoreleasing *)outError
{
    __block BOOL success = YES;
    [_lock withLock: ^{
        NSUInteger count = self.count;
        FLEncoder_BeginArray(encoder, count);
        for (NSUInteger i = 0; i < count; i++) {
            id value = [self objectAtIndex: i];
            if ([value conformsToProtocol: @protocol(CBLFleeceEncodable)]) {
                if (![value fleeceEncode: encoder database: database error: outError]) {
                    success = NO;
                    return;
                }
            } else
                FLEncoder_WriteNSObject(encoder, value);
        }
        FLEncoder_EndArray(encoder);
    }];
    return success;
}


#pragma mark - PRIVATE


- (void) copyFleeceData {
    Assert(_array == nil);
    NSUInteger count = [super count];
    _array = [NSMutableArray arrayWithCapacity: count];
    for (NSUInteger i = 0; i < count; i++) {
        id value = [super objectAtIndex: i];
        [_array addObject: [CBLData convertValue: value listener: self]];
    }
}


- (void) setValue: (id)value atIndex: (NSUInteger)index isChange: (BOOL)isChange {
    if (!_array)
        [self copyFleeceData];
    
    _array[index] = value;
    if (isChange)
        [self setChanged];
}

@end
