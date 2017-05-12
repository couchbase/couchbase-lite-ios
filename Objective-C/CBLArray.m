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


@implementation CBLArray {
    NSMutableArray* _array;
    NSMapTable* _changeListeners;
    BOOL _changed;
}

@synthesize swiftObject=_swiftObject;


+ (instancetype) array {
    return [[self alloc] init];
}


- (instancetype) init {
    return [self initWithFleeceData: nil];
}


- (instancetype) initWithArray: (NSArray*)array {
    self = [self initWithFleeceData: nil];
    if (self) {
        [self setArray: array];
    }
    return self;
}


- /*internal */ (instancetype) initWithFleeceData: (CBLFLArray*)data {
    self = [super initWithFleeceData: data];
    if (self ) {
        _array = [NSMutableArray array];
        [self loadBackingFleeceData];
    }
    return self;
}


#pragma mark - GETTER


- (nullable id) objectAtIndex: (NSUInteger)index {
    return _array[index];
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    id value = _array[index];
    return [CBLData booleanValueForObject: value];
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    id value = _array[index];
    return [$castIf(NSNumber, value) integerValue];
}


- (float) floatAtIndex: (NSUInteger)index {
    id value = _array[index];
    return [$castIf(NSNumber, value) floatValue];
}


- (double) doubleAtIndex: (NSUInteger)index {
    id value = _array[index];
    return [$castIf(NSNumber, value) doubleValue];
}


- (nullable NSString*) stringAtIndex: (NSUInteger)index {
    id value = _array[index];
    return $castIf(NSString, value);
}


- (nullable NSNumber*) numberAtIndex: (NSUInteger)index {
    id value = _array[index];
    return $castIf(NSNumber, value);
}


- (nullable NSDate*) dateAtIndex: (NSUInteger)index {
    return [CBLJSON dateWithJSONObject: [self stringAtIndex: index]];
}


- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index {
    id value = _array[index];
    return $castIf(CBLBlob, value);
}


- (nullable CBLDictionary*) dictionaryAtIndex: (NSUInteger)index {
    id value = _array[index];
    return $castIf(CBLDictionary, value);
}


- (nullable CBLArray*) arrayAtIndex: (NSUInteger)index {
    id value = _array[index];
    return $castIf(CBLArray, value);
}


- (NSUInteger) count {
    return _array.count;
}


- (NSArray*) toArray {
    NSMutableArray* array = [NSMutableArray array];
    for (id item in _array) {
        id value = item;
        if ([value conformsToProtocol: @protocol(CBLReadOnlyDictionary)])
            value = [value toDictionary];
        else if ([value conformsToProtocol: @protocol(CBLReadOnlyArray)])
            value = [value toArray];
        [array addObject: value];
    }
    return array;
}


#pragma mark - SETTER

- (void) setArray:(nullable NSArray *)array {
    // Detach all objects that we are listening to for changes:
    [self detachChildChangeListeners];
    
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: [array count]];
    for (id value in array) {
        [result addObject: [CBLData convertValue: value listener: self]];
    }
    
    _array = result;
    [self setChanged];
}


- (void) setObject: (id)value atIndex: (NSUInteger)index {
    id oldValue = [self objectAtIndex: index];
    if (!$equal(value, oldValue)) {
        value = [CBLData convertValue: value listener: self];
        [self detachChangeListenerForObject: oldValue];
        [self setValue: value atIndex: index isChange: YES];
    }
}


- (void) addObject: (id)value  {
    [_array addObject: [CBLData convertValue: value listener: self]];
    [self setChanged];
}


- (void) insertObject: (id)value atIndex: (NSUInteger)index {
    [_array insertObject: [CBLData convertValue: value listener: self] atIndex: index];
    [self setChanged];
}


- (void) removeObjectAtIndex:(NSUInteger)index {
    id value = _array[index];
    [self detachChangeListenerForObject: value];
    [_array removeObjectAtIndex: index];
    [self setChanged];
}


#pragma mark - SUBSCRIPTING


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    id value = index < self.count ? [self objectAtIndex: index] : nil;
    return [[CBLFragment alloc] initWithValue: value parent: self parentKey: @(index)];
}


#pragma mark - CHANGE LISTENER


- (void) addChangeListener: (id<CBLObjectChangeListener>)listener {
    if (!_changeListeners)
        _changeListeners = [NSMapTable weakToStrongObjectsMapTable];
    NSInteger count = [[_changeListeners objectForKey: listener] integerValue] + 1;
    [_changeListeners setObject: @(count) forKey: listener];
}


- (void) removeChangeListener: (id<CBLObjectChangeListener>)listener {
    NSInteger count = [[_changeListeners objectForKey: listener] integerValue] - 1;
    if (count > 0)
        [_changeListeners setObject: @(count) forKey: listener];
    else
        [_changeListeners removeObjectForKey: listener];
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

- (void) notifyChangeListeners {
    for (id <CBLObjectChangeListener> listener in _changeListeners) {
        [listener objectDidChange: self];
    }
}


#pragma mark - CHANGE LISTENING


- (void) objectDidChange: (id)object {
    [self setChanged];
}


#pragma mark - FLEECE ENCODABLE


- (BOOL) fleeceEncode: (FLEncoder)encoder
             database: (CBLDatabase*)database
                error: (NSError**)outError
{
    NSUInteger count = self.count;
    FLEncoder_BeginArray(encoder, count);
    for (NSUInteger i = 0; i < count; i++) {
        id value = [self objectAtIndex: i];
        if ([value conformsToProtocol: @protocol(CBLFleeceEncodable)]) {
            if (![value fleeceEncode: encoder database: database error: outError])
                return NO;
        } else
            FLEncoder_WriteNSObject(encoder, value);
    }
    FLEncoder_EndArray(encoder);
    return YES;
}


#pragma mark - PRIVATE


- (void) loadBackingFleeceData {
    NSUInteger count = [super count];
    for (NSUInteger i = 0; i < count; i++) {
        id value = [super objectAtIndex: i];
        [_array addObject: [CBLData convertValue: value listener: self]];
    }
}


- (void) setValue: (id)value atIndex: (NSUInteger)index isChange: (BOOL)isChange {
    _array[index] = value;
    if (isChange)
        [self setChanged];
}


- (void) setChanged {
    if (!_changed) {
        _changed = YES;
        [self notifyChangeListeners];
    }
}


@end
