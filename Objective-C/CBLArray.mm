//
//  CBLArray.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLArray.h"
#import "CBLArray+Swift.h"
#import "CBLData.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"
#import "CBLFleece.hh"
#import "MArray.hh"

using namespace cbl;
using namespace fleece;


@implementation CBLArray {
    __weak NSObject* _sharedLock;
}


@synthesize swiftObject=_swiftObject;


- (instancetype) initEmpty {
    self = [super init];
    if (self) {
        [self setupSharedLock];
    }
    return self;
}


- (instancetype) initWithMValue: (fleece::MValue<id>*)mv
                       inParent: (fleece::MCollection<id>*)parent
{
    self = [super init];
    if (self) {
        _array.initInSlot(mv, parent);
        [self setupSharedLock];
    }
    return self;
}


- (instancetype) initWithCopyOfMArray: (const MArray<id>&)mArray
                            isMutable: (bool)isMutable
{
    self = [super init];
    if (self) {
        _array.initAsCopyOf(mArray, isMutable);
        [self setupSharedLock];
    }
    return self;
}


- (void) setupSharedLock {
    id db;
    auto docContext = dynamic_cast<DocContext*>(_array.context());
    if (docContext)
        db = (docContext)->database();
    _sharedLock = db != nil ? db : self;
}


- (id) copyWithZone:(NSZone *)zone {
    return self;
}


- (CBLMutableArray*) mutableCopyWithZone:(NSZone *)zone {
    CBL_LOCK(_sharedLock) {
        return [[CBLMutableArray alloc] initWithCopyOfMArray: _array isMutable: true];
    }
}


// Called under the database's lock:
- (void) fl_encodeToFLEncoder: (FLEncoder)enc {
    SharedEncoder encoder(enc);
    _array.encodeTo(encoder);
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
    CBL_LOCK(_sharedLock) {
        return _getObject(_array, index);
    }
}


- (nullable NSString*) stringAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return _getObject(_array, index, [NSString class]);
    }
}


- (nullable NSNumber*) numberAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return _getObject(_array, index, [NSNumber class]);
    }
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return asInteger(_get(_array, index), _array);
    }
}


- (long long) longLongAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return asLongLong(_get(_array, index), _array);
    }
}


- (float) floatAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return asFloat(_get(_array, index), _array);
    }
}


- (double) doubleAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return asDouble(_get(_array, index), _array);
    }
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return asBool(_get(_array, index), _array);
    }
}


- (nullable NSDate*) dateAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return asDate(_getObject(_array, index));
    }
}


- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return _getObject(_array, index, [CBLBlob class]);
    }
}


- (nullable CBLArray*) arrayAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return _getObject(_array, index, [CBLArray class]);
    }
}


- (nullable CBLDictionary*) dictionaryAtIndex: (NSUInteger)index {
    CBL_LOCK(_sharedLock) {
        return _getObject(_array, index, [CBLDictionary class]);
    }
}


- (NSUInteger) count {
    CBL_LOCK(_sharedLock) {
        return _array.count();
    }
}


#pragma mark - Data


- (NSArray*) toArray {
    CBL_LOCK(_sharedLock) {
        auto count = _array.count();
        NSMutableArray* result = [NSMutableArray arrayWithCapacity: count];
        for (NSUInteger i = 0; i < count; i++)
            [result addObject: [_getObject(_array, i) cbl_toPlainObject]];
        return result;
    }
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
    CBL_LOCK(_sharedLock) {
        if (index >= _array.count())
            return nil;
    }
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


#pragma mark - Lock


- (NSObject*) sharedLock {
    return _sharedLock;
}


@end
