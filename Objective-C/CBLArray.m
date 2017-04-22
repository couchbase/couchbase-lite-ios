//
//  CBLArraym
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLArray.h"
#import "CBLBlob.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLFleeceArray.h"
#import "CBLJSON.h"
#import "CBLSubdocument.h"

@implementation CBLArray {
    NSMutableArray* _array;
    NSMapTable* _changeListeners;
    BOOL _changed;
}


+ (instancetype) array {
    return [[self alloc] init];
}


- (instancetype) init {
    return [self initWithData: [CBLFleeceArray empty]];
}


- (instancetype) initWithArray: (NSArray*)array {
    self = [self init];
    if (self) {
        [self setArray: array];
    }
    return self;
}


- /*internal */ (instancetype) initWithData: (id<CBLReadOnlyArray>)data {
    self = [super initWithData: data];
    if (self ) {
        _array = [NSMutableArray array];
        [self loadBackingData];
    }
    return self;
}


#pragma mark - GETTER


- (nullable id) objectAtIndex: (NSUInteger)index {
    id value = _array[index];
    return value != [NSNull null] ? value : nil; // Cross-platform behavior
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    id value = _array[index];
    if (value == [NSNull null])
        return NO;
    else {
        id n = $castIf(NSNumber, value);
        return n ? [n boolValue] : YES;
    }
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


- (nullable CBLSubdocument*) subdocumentAtIndex: (NSUInteger)index {
    id value = _array[index];
    return $castIf(CBLSubdocument, value);
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

- (void) setArray:(NSArray *)array {
    // Detach all objects that we are listening to for changes:
    [self detachChildChangeListeners];
    
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: [array count]];
    for (id item in array) {
        [result addObject: [self prepareValue: item]];
    }
    
    _array = result;
    [self setChanged];
}


- (void) setObject: (id)value atIndex: (NSUInteger)index {
    id oldValue = [self objectAtIndex: index];
    if (!$equal(value, oldValue)) {
        value = [self prepareValue: value];
        [self detachChangeListenerForObject: oldValue];
        [self setValue: value atIndex: index isChange: YES];
    }
}


- (void) addObject: (id)value  {
    [_array addObject: [self prepareValue: value]];
    [self setChanged];
}


- (void) insertObject: (id)value atIndex: (NSUInteger)index {
    [_array insertObject: [self prepareValue: value] atIndex: index];
    [self setChanged];
}


- (void) removeObjectAtIndex:(NSUInteger)index {
    id value = _array[index];
    [self detachChangeListenerForObject: value];
    [_array removeObjectAtIndex: index];
    [self setChanged];
}


#pragma mark - SUBSCRIPTION


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    id value = index < self.count ? [self objectAtIndex: index] : nil;
    return [[CBLFragment alloc] initWithValue: value parent: self parentKey: @(index)];
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


- (void) loadBackingData {
    NSUInteger count = [super count];
    for (NSUInteger i = 0; i < count; i++) {
        id value = [super objectAtIndex: i];
        [_array addObject: [self prepareValue: value]];
    }
}


- (nullable id) prepareValue: (nullable id)value {
    value = [self convertValue: value];
    Assert([CBLData validateValue: value], @"Unsupported value type.");
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
