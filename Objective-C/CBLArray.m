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


#pragma mark - GETTER


- (nullable id) objectAtIndex: (NSUInteger)index {
    if (!_array) {
        id value = [super objectAtIndex: index];
        if ([value isKindOfClass: [CBLReadOnlyDictionary class]] ||
            [value isKindOfClass: [CBLReadOnlyArray class]]) {
            [self copyFleeceData];
        } else
            return value;
    }
    return _array[index];
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    if (!_array)
        return [super booleanAtIndex: index];
    else {
        id value = _array[index];
        return [CBLData booleanValueForObject: value];
    }
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    if (!_array)
        return [super integerAtIndex: index];
    else {
        id value = _array[index];
        return [$castIf(NSNumber, value) integerValue];
    }
}


- (float) floatAtIndex: (NSUInteger)index {
    if (!_array)
        return [super floatAtIndex: index];
    else {
        id value = _array[index];
        return [$castIf(NSNumber, value) floatValue];
    }
}


- (double) doubleAtIndex: (NSUInteger)index {
    if (!_array)
        return [super doubleAtIndex: index];
    else {
        id value = _array[index];
        return [$castIf(NSNumber, value) doubleValue];
    }
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
    if (!_array)
        return super.count;
    else
        return _array.count;
}


- (NSArray*) toArray {
    if (!_array)
        [self copyFleeceData];
    
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
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: [array count]];
    for (id value in array) {
        [result addObject: [CBLData convertValue: value]];
    }
    
    _array = result;
    [self setChanged];
}


- (void) setObject: (id)value atIndex: (NSUInteger)index {
    if (!value) value = [NSNull null]; // nil conversion only for apple platform
    
    id oldValue = [self objectAtIndex: index];
    if (!$equal(value, oldValue)) {
        value = [CBLData convertValue: value];
        [self setValue: value atIndex: index isChange: YES];
    }
}


- (void) addObject: (id)value  {
    if (!_array)
        [self copyFleeceData];
    
    if (!value) value = [NSNull null]; // nil conversion only for apple platform
    [_array addObject: [CBLData convertValue: value]];
    [self setChanged];
}


- (void) insertObject: (id)value atIndex: (NSUInteger)index {
    if (!_array)
        [self copyFleeceData];
    
    if (!value) value = [NSNull null]; // nil conversion only for apple platform
    [_array insertObject: [CBLData convertValue: value] atIndex: index];
    [self setChanged];
}


- (void) removeObjectAtIndex:(NSUInteger)index {
    if (!_array)
        [self copyFleeceData];
    
    [_array removeObjectAtIndex: index];
    [self setChanged];
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    if (!_array)
        return [super countByEnumeratingWithState: state objects: buffer count: len];
    else
        return [_array countByEnumeratingWithState: state objects: buffer count: len];
}


#pragma mark - SUBSCRIPTING


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    id value = index < self.count ? [self objectAtIndex: index] : nil;
    return [[CBLFragment alloc] initWithValue: value parent: self parentKey: @(index)];
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


- (void) copyFleeceData {
    Assert(_array == nil);
    NSUInteger count = [super count];
    _array = [NSMutableArray arrayWithCapacity: count];
    for (NSUInteger i = 0; i < count; i++) {
        id value = [super objectAtIndex: i];
        [_array addObject: [CBLData convertValue: value]];
    }
}


- (void) setValue: (id)value atIndex: (NSUInteger)index isChange: (BOOL)isChange {
    if (!_array)
        [self copyFleeceData];
    
    _array[index] = value;
    if (isChange)
        [self setChanged];
}


- (void) setChanged {
    if (!_changed) {
        _changed = YES;
    }
}


@end
