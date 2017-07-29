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
    NSObject* _lock;
}

@synthesize swiftObject=_swiftObject;


+ (instancetype) array {
    return [[self alloc] init];
}


- /* internal */ (instancetype) initWithFleeceData: (nullable CBLFLArray*)data {
    self = [super initWithFleeceData: data];
    if (self) {
        _lock = [[NSObject alloc] init];
    }
    return self;
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
    CBL_LOCK(_lock) {
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
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    CBL_LOCK(_lock) {
        if (!_array)
            return [super booleanAtIndex: index];
        else {
            id value = _array[index];
            return [CBLData booleanValueForObject: value];
        }
    }
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    CBL_LOCK(_lock) {
        if (!_array)
            return [super integerAtIndex: index];
        else {
            id value = _array[index];
            return [$castIf(NSNumber, value) integerValue];
        }
    }
}


- (float) floatAtIndex: (NSUInteger)index {
    CBL_LOCK(_lock) {
        if (!_array)
            return [super floatAtIndex: index];
        else {
            id value = _array[index];
            return [$castIf(NSNumber, value) floatValue];
        }
    }
}


- (double) doubleAtIndex: (NSUInteger)index {
    CBL_LOCK(_lock) {
        if (!_array)
            return [super doubleAtIndex: index];
        else {
            id value = _array[index];
            return [$castIf(NSNumber, value) doubleValue];
        }
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
    CBL_LOCK(_lock) {
        if (!_array)
            return super.count;
        else
            return _array.count;
    }
}


- (NSArray*) toArray {
    CBL_LOCK(_lock) {
        if (!_array)
            [self copyFleeceData];
        
        NSMutableArray* array = [NSMutableArray arrayWithCapacity: _array.count];
        for (id item in _array) {
            [array addObject: [item cbl_toPlainObject]];
        }
        return array;
    }
}


- (id) cbl_toCBLObject {
    return self;
}


#pragma mark - SETTER


- (void) setArray:(nullable NSArray *)array {
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: [array count]];
    for (id value in array) {
        [result addObject: [value cbl_toCBLObject]];
    }
    
    CBL_LOCK(_lock) {
        _array = result;
        [self setChanged];
    }
}


- (void) setObject: (id)value atIndex: (NSUInteger)index {
    CBL_LOCK(_lock) {
        if (!value) value = [NSNull null]; // nil conversion only for apple platform
        
        id oldValue = [self objectAtIndex: index];
        if (!$equal(value, oldValue)) {
            [self setValue: [value cbl_toCBLObject] atIndex: index isChange: YES];
        }
    }
}


- (void) addObject: (id)value  {
    CBL_LOCK(_lock) {
        if (!_array)
            [self copyFleeceData];
        
        if (!value) value = [NSNull null]; // nil conversion only for apple platform
        [_array addObject: [value cbl_toCBLObject]];
        [self setChanged];
    }
}


- (void) insertObject: (id)value atIndex: (NSUInteger)index {
    CBL_LOCK(_lock) {
        if (!_array)
            [self copyFleeceData];
        
        if (!value) value = [NSNull null]; // nil conversion only for apple platform
        [_array insertObject: [value cbl_toCBLObject] atIndex: index];
        [self setChanged];
    }
}


- (void) removeObjectAtIndex:(NSUInteger)index {
    CBL_LOCK(_lock) {
        if (!_array)
            [self copyFleeceData];
        
        [_array removeObjectAtIndex: index];
        [self setChanged];
    }
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    CBL_LOCK(_lock) {
        if (!_array)
            return [super countByEnumeratingWithState: state objects: buffer count: len];
        else
            return [_array countByEnumeratingWithState: state objects: buffer count: len];
    }
}


#pragma mark - SUBSCRIPTING


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    CBL_LOCK(_lock) {
        id value = index < self.count ? [self objectAtIndex: index] : nil;
        return [[CBLFragment alloc] initWithValue: value parent: self parentKey: @(index)];
    }
}


#pragma mark - FLEECE ENCODABLE


- (BOOL) cbl_fleeceEncode: (FLEncoder)encoder
                 database: (CBLDatabase*)database
                    error: (NSError**)outError
{
    CBL_LOCK(_lock) {
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
}


#pragma mark - PRIVATE


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
