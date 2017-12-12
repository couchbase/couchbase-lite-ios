//
//  CBLArray.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLArray.h"
#import "CBLArray+Swift.h"
#import "CBLData.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"
#import "PlatformCompat.hh"
#import "CBLFleece.hh"
#import "MArray.hh"

using namespace cbl;
using namespace fleeceapi;


@implementation CBLArray 


@synthesize swiftObject=_swiftObject;


- (instancetype) initEmpty {
    return [super init];
}


- (instancetype) initWithMValue: (fleeceapi::MValue<id>*)mv
                       inParent: (fleeceapi::MCollection<id>*)parent
{
    self = [super init];
    if (self) {
        _array.initInSlot(mv, parent);
    }
    return self;
}


- (instancetype) initWithCopyOfMArray: (const MArray<id>&)mArray
                            isMutable: (bool)isMutable
{
    self = [super init];
    if (self) {
        _array.initAsCopyOf(mArray, isMutable);
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    return self;
}


- (CBLMutableArray*) mutableCopyWithZone:(NSZone *)zone {
    return [[CBLMutableArray alloc] initWithCopyOfMArray: _array isMutable: true];
}


- (void) fl_encodeToFLEncoder: (FLEncoder)enc {
    Encoder encoder(enc);
    _array.encodeTo(encoder);
    encoder.release();
}


- (MCollection<id>*) fl_collection {
    return &_array;
}


[[noreturn]] static void throwRangeException(NSUInteger index) {
    [NSException raise: NSRangeException format: @"CBLMutableArray index %lu is out of range",
        (unsigned long)index];
    abort();
}


#pragma mark - GETTER


static const MValue<id>& _get(MArray<id> &array, NSUInteger index) {
    auto &val = array.get(index);
    if (_usuallyFalse(val.isEmpty()))
        throwRangeException(index);
    return val;
}


static id _getObject(MArray<id> &array, NSUInteger index, Class asClass =nil) {
    //OPT: Can return nil before calling asNative, if MValue.value exists and is wrong type
    id obj = _get(array, index).asNative(&array);
    if (asClass && ![obj isKindOfClass: asClass])
        obj = nil;
    return obj;
}


- (nullable id) valueAtIndex: (NSUInteger)index {
    return _getObject(_array, index);
}


- (nullable NSString*) stringAtIndex: (NSUInteger)index {
    return _getObject(_array, index, [NSString class]);
}


- (nullable NSNumber*) numberAtIndex: (NSUInteger)index {
    return _getObject(_array, index, [NSNumber class]);
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    return asInteger(_get(_array, index), _array);
}


- (long long) longLongAtIndex: (NSUInteger)index {
    return asLongLong(_get(_array, index), _array);
}


- (float) floatAtIndex: (NSUInteger)index {
    return asFloat(_get(_array, index), _array);
}


- (double) doubleAtIndex: (NSUInteger)index {
    return asDouble(_get(_array, index), _array);
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    return asBool(_get(_array, index), _array);
}


- (nullable NSDate*) dateAtIndex: (NSUInteger)index {
    return asDate(_getObject(_array, index));
}


- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index {
    return _getObject(_array, index, [CBLBlob class]);
}


- (nullable CBLArray*) arrayAtIndex: (NSUInteger)index {
    return _getObject(_array, index, [CBLArray class]);
}


- (nullable CBLDictionary*) dictionaryAtIndex: (NSUInteger)index {
    return _getObject(_array, index, [CBLDictionary class]);
}


- (NSUInteger) count {
    return _array.count();
}


#pragma mark - Data


- (NSArray*) toArray {
    auto count = _array.count();
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: count];
    for (NSUInteger i = 0; i < count; i++)
        [result addObject: [_getObject(_array, i) cbl_toPlainObject]];
    return result;
}


#pragma mark - Mutable


- (CBLMutableArray*) toMutable {
    return [self mutableCopy];
}


- (id) cbl_toPlainObject {
    return [self toArray];
}


- (id) cbl_toCBLObject {
    return [self mutableCopy];
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    if (state->state == 0) {
        state->state = 1;
        state->mutationsPtr = &state->extra[0]; // Placeholder for no mutation
        state->extra[1] = 0;                    // Next start index
    }
    
    NSUInteger start = state->extra[1];
    NSUInteger end = MIN((start + len), self.count);
    NSUInteger i = 0;
    for (NSUInteger index = start; index < end; index++) {
        id v = [self valueAtIndex: index];
        buffer[i] = v;
        i++;
    }
    state->extra[1] = end;
    state->itemsPtr = buffer;
    return i;
}


#pragma mark - Subscript


- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    if (index >= _array.count())
        return nil;
    return [[CBLFragment alloc] initWithParent: self index: index];
}


#pragma mark - Equality


- (BOOL) isEqual: (id)object {
    if (self == object)
        return YES;
    
    CBLArray* other = $castIf(CBLArray, object);
    if (!other)
        return NO;
    
    NSUInteger count = self.count;
    if (count != other.count)
        return NO;
    
    for (NSUInteger i = 0; i < count; i++) {
        id value1 = [self valueAtIndex: i];
        id value2 = [other valueAtIndex: i];
        if (!(value1 == nil ? value2 == nil : [value1 isEqual: value2]))
            return NO;
    }
    
    return YES;
}


- (NSUInteger) hash {
    NSUInteger hash = 0;
    for (NSUInteger i = 0; i < self.count; i++) {
        id value = [self valueAtIndex: i];
        hash ^= (value ? [value hash] : 0);
    }
    return hash;
}


@end
