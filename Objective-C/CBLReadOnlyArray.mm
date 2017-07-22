//
//  CBLReadOnlyArray.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyArray.h"
#import "CBLReadOnlyArray+Swift.h"
#import "CBLDocument+Internal.h"
#import "CBLInternal.h"
#import "CBLJSON.h"
#import "CBLSharedKeys.hh"
#import "CBLData.h"


@implementation CBLReadOnlyArray {
    CBLFLArray* _data;
    FLArray _array;
    cbl::SharedKeys _sharedKeys;
}


@synthesize data=_data, swiftObject=_swiftObject;

- /* internal */ (instancetype) initWithFleeceData: (nullable CBLFLArray*)data {
    self = [super init];
    if (self) {
        _data = data;
        _array = _data.array;
        _sharedKeys = _data.database.sharedKeys;
    }
    return self;
}


#pragma mark - GETTER


- (nullable id) objectAtIndex: (NSUInteger)index {
    return [self fleeceValueToObjectAtIndex: index];
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    return FLValue_AsBool(FLArray_Get(_array, (uint)index));
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    return (NSInteger)FLValue_AsInt(FLArray_Get(_array, (uint)index));
}


- (float) floatAtIndex: (NSUInteger)index {
    return FLValue_AsFloat(FLArray_Get(_array, (uint)index));
}


- (double) doubleAtIndex: (NSUInteger)index {
    return FLValue_AsDouble(FLArray_Get(_array, (uint)index));
}


- (nullable NSString*) stringAtIndex: (NSUInteger)index {
    return $castIf(NSString, [self fleeceValueToObjectAtIndex: index]);
}


- (nullable NSNumber*) numberAtIndex: (NSUInteger)index {
    return $castIf(NSNumber, [self fleeceValueToObjectAtIndex: index]);
}


- (nullable NSDate*) dateAtIndex: (NSUInteger)index {
    return [CBLJSON dateWithJSONObject: [self fleeceValueToObjectAtIndex: index]];
}


- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index {
    return $castIf(CBLBlob, [self fleeceValueToObjectAtIndex: index]);
}


- (nullable CBLReadOnlyDictionary*) dictionaryAtIndex: (NSUInteger)index {
    return $castIf(CBLReadOnlyDictionary, [self fleeceValueToObjectAtIndex: index]);
}


- (nullable CBLReadOnlyArray*) arrayAtIndex: (NSUInteger)index {
    return $castIf(CBLReadOnlyArray, [self fleeceValueToObjectAtIndex: index]);
}


- (NSUInteger) count {
    return FLArray_Count(_array);
}


- (NSArray*) toArray {
    if (_array != nullptr)
        return FLValue_GetNSObject((FLValue)_array, &_sharedKeys);
    else
        return @[];
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
        id v = [self objectAtIndex: index];
        buffer[i] = v;
        i++;
    }
    state->extra[1] = end;
    state->itemsPtr = buffer;
    return i;
}


#pragma mark - SUBSCRIPTING


- (CBLReadOnlyFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    id value = index < self.count ? [self fleeceValueToObjectAtIndex: index] : nil;
    return [[CBLReadOnlyFragment alloc] initWithValue: value];
}


#pragma mark - FLEECE ENCODABLE


- (BOOL) fleeceEncode: (FLEncoder)encoder
             database: (CBLDatabase*)database
                error: (NSError**)outError
{
    
    return FLEncoder_WriteValueWithSharedKeys(encoder, (FLValue)_array, _sharedKeys);
}


#pragma mark - FLEECE


- (id) fleeceValueToObjectAtIndex: (NSUInteger)index {
    FLValue value = FLArray_Get(_array, (uint)index);
    if (value != nullptr)
        return [CBLData fleeceValueToObject: value
                                 datasource: _data.datasource database: _data.database];
    else
        return nil;
}



@end
