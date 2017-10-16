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


#pragma mark - Initializers


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


#pragma mark - Type Getters


- (nullable CBLArray*) arrayAtIndex: (NSUInteger)index {
    return $castIf(CBLArray, [self objectAtIndex: index]);
}


- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index {
    return $castIf(CBLBlob, [self objectAtIndex: index]);
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    if (!_array)
        return [super booleanAtIndex: index];
    else {
        id value = _array[index];
        return [CBLData booleanValueForObject: value];
    }
}


- (nullable NSDate*) dateAtIndex: (NSUInteger)index {
    return [CBLJSON dateWithJSONObject: [self objectAtIndex: index]];
}


- (nullable CBLDictionary*) dictionaryAtIndex: (NSUInteger)index {
    return $castIf(CBLDictionary, [self objectAtIndex: index]);
}


- (double) doubleAtIndex: (NSUInteger)index {
    if (!_array)
        return [super doubleAtIndex: index];
    else {
        id value = _array[index];
        return [$castIf(NSNumber, value) doubleValue];
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


- (NSInteger) integerAtIndex: (NSUInteger)index {
    if (!_array)
        return [super integerAtIndex: index];
    else {
        id value = _array[index];
        return [$castIf(NSNumber, value) integerValue];
    }
}


- (long long) longLongAtIndex: (NSUInteger)index {
    if (!_array)
        return [super longLongAtIndex: index];
    else {
        id value = _array[index];
        return [$castIf(NSNumber, value) longLongValue];
    }
}


- (nullable NSNumber*) numberAtIndex: (NSUInteger)index {
    return $castIf(NSNumber, [self objectAtIndex: index]);
}


- (nullable NSString*) stringAtIndex: (NSUInteger)index {
    return $castIf(NSString, [self objectAtIndex: index]);
}


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


- (NSUInteger) count {
    if (!_array)
        return super.count;
    else
        return _array.count;
}


- (NSArray*) toArray {
    if (!_array)
        [self copyFleeceData];
    
    NSMutableArray* array = [NSMutableArray arrayWithCapacity: _array.count];
    for (id item in _array) {
        [array addObject: [item cbl_toPlainObject]];
    }
    return array;
}


#pragma mark - Type Setters


- (void) setArray: (nullable CBLArray*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


- (void) setBlob: (nullable CBLBlob*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


- (void) setBoolean: (BOOL)value atIndex: (NSUInteger)index {
    [self setObject: @(value) atIndex: index];
}


- (void) setDate: (nullable NSDate*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


- (void) setDictionary: (nullable CBLDictionary*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


- (void) setDouble: (double)value atIndex: (NSUInteger)index {
    [self setObject: @(value) atIndex: index];
}


- (void) setFloat: (float)value atIndex: (NSUInteger)index {
    [self setObject: @(value) atIndex: index];
}


- (void) setInteger: (NSInteger)value atIndex: (NSUInteger)index {
    [self setObject: @(value) atIndex: index];
}


- (void) setLongLong: (long long)value atIndex: (NSUInteger)index {
    [self setObject: @(value) atIndex: index];
}


- (void) setNumber: (nullable NSNumber*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


- (void) setObject: (id)value atIndex: (NSUInteger)index {
    if (!value) value = [NSNull null]; // nil conversion only for apple platform
    
    id oldValue = [self objectAtIndex: index];
    if (!$equal(value, oldValue)) {
        [self setValue: [value cbl_toCBLObject] atIndex: index isChange: YES];
    }
}


/** Sets an String object at the given index. A nil value will be converted to an NSNull.
 @param value    The String object.
 @param index    The index. This value must not exceed the bounds of the array. */
- (void) setString: (nullable NSString*)value atIndex: (NSUInteger)index {
    [self setObject: value atIndex: index];
}


#pragma mark - Type Appenders


- (void) addArray: (nullable CBLArray*)value {
    [self addObject: value];
}


- (void) addBlob: (nullable CBLBlob*)value {
    [self addObject: value];
}


- (void) addBoolean: (BOOL)value {
    [self addObject: @(value)];
}


- (void) addDate: (nullable NSDate*)value {
    [self addObject: value];
}


- (void) addDictionary: (nullable CBLDictionary*)value {
    [self addObject: value];
}


- (void) addDouble: (double)value {
    [self addObject: @(value)];
}


- (void) addFloat: (float)value {
    [self addObject: @(value)];
}


- (void) addInteger: (NSInteger)value {
    [self addObject: @(value)];
}


- (void) addLongLong: (long long)value {
    [self addObject: @(value)];
}


- (void) addNumber: (nullable NSNumber*)value {
    [self addObject: value];
}


- (void) addObject: (id)value  {
    if (!_array)
        [self copyFleeceData];
    
    if (!value) value = [NSNull null]; // nil conversion only for apple platform
    [_array addObject: [value cbl_toCBLObject]];
    [self setChanged];
}


- (void) addString: (nullable NSString*)value {
    [self addObject: value];
}


#pragma mark - Type Inserters


- (void) insertArray: (nullable CBLArray*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


- (void) insertBlob: (nullable CBLBlob*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


- (void) insertBoolean: (BOOL)value atIndex: (NSUInteger)index {
    [self insertObject: @(value) atIndex: index];
}


- (void) insertDate: (nullable NSDate*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


- (void) insertDictionary: (nullable CBLDictionary*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


- (void) insertDouble: (double)value atIndex: (NSUInteger)index {
    [self insertObject: @(value) atIndex: index];
}


- (void) insertFloat: (float)value atIndex: (NSUInteger)index {
    [self insertObject: @(value) atIndex: index];
}


- (void) insertInteger: (NSInteger)value atIndex: (NSUInteger)index {
    [self insertObject: @(value) atIndex: index];
}


- (void) insertLongLong: (long long)value atIndex: (NSUInteger)index {
    [self insertObject: @(value) atIndex: index];
}


- (void) insertNumber: (nullable NSNumber*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


- (void) insertObject: (id)value atIndex: (NSUInteger)index {
    if (!_array)
        [self copyFleeceData];
    
    if (!value) value = [NSNull null]; // nil conversion only for apple platform
    [_array insertObject: [value cbl_toCBLObject] atIndex: index];
    [self setChanged];
}


- (void) insertString: (nullable NSString*)value atIndex: (NSUInteger)index {
    [self insertObject: value atIndex: index];
}


#pragma mark - Set Content with an Array


- (void) setArray:(nullable NSArray *)array {
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: [array count]];
    for (id value in array) {
        [result addObject: [value cbl_toCBLObject]];
    }
    
    _array = result;
    [self setChanged];
}


#pragma mark - Remove value


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


#pragma mark - Subscript


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    if (index >= self.count)
        return nil;
    return [[CBLFragment alloc] initWithParent: self index: index];
}


#pragma mark - Change Listener


- (void) objectDidChange: (id)object {
    [self setChanged];
}


#pragma mark - CBLConversion


- (id) cbl_toCBLObject {
    return self;
}


#pragma mark - Fleece Encodable


- (BOOL) cbl_fleeceEncode: (FLEncoder)encoder
                 database: (CBLDatabase*)database
                    error: (NSError**)outError
{
    NSUInteger count = self.count;
    FLEncoder_BeginArray(encoder, count);
    for (NSUInteger i = 0; i < count; i++) {
        id value = [self objectAtIndex: i];
        if (![value cbl_fleeceEncode: encoder database: database error: outError])
            return NO;
    }
    FLEncoder_EndArray(encoder);
    return YES;
}


#pragma mark - Private


- (void) copyFleeceData {
    Assert(_array == nil);
    NSUInteger count = [super count];
    _array = [NSMutableArray arrayWithCapacity: count];
    for (NSUInteger i = 0; i < count; i++) {
        id value = [super objectAtIndex: i];
        [_array addObject: [value cbl_toCBLObject]];
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
