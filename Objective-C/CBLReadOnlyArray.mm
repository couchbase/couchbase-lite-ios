//
//  CBLReadOnlyArray.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyArray.h"
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


@synthesize data=_data;

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
    
    return FLEncoder_WriteValue(encoder, (FLValue)_array);
}


#pragma mark - FLEECE


- (id) fleeceValueToObjectAtIndex: (NSUInteger)index {
    FLValue value = FLArray_Get(_array, (uint)index);
    if (value != nullptr)
        return [CBLData fleeceValueToObject: value c4doc: _data.c4doc database: _data.database];
    else
        return nil;
}



@end
