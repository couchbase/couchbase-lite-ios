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
    return [self fleeceValueToObject: [self fleeceValueForIndex: index]];
}


- (BOOL) booleanAtIndex: (NSUInteger)index {
    return FLValue_AsBool([self fleeceValueForIndex: index]);
}


- (NSInteger) integerAtIndex: (NSUInteger)index {
    return (NSInteger)FLValue_AsInt([self fleeceValueForIndex: index]);
}


- (float) floatAtIndex: (NSUInteger)index {
    return FLValue_AsFloat([self fleeceValueForIndex: index]);
}


- (double) doubleAtIndex: (NSUInteger)index {
    return FLValue_AsDouble([self fleeceValueForIndex: index]);
}


- (nullable NSString*) stringAtIndex: (NSUInteger)index {
    return $castIf(NSString, [self objectAtIndex: index]);
}


- (nullable NSNumber*) numberAtIndex: (NSUInteger)index {
    return $castIf(NSNumber, [self objectAtIndex: index]);
}


- (nullable NSDate*) dateAtIndex: (NSUInteger)index {
    return [CBLJSON dateWithJSONObject: [self stringAtIndex: index]];
}


- (nullable CBLBlob*) blobAtIndex: (NSUInteger)index {
    return $castIf(CBLBlob, [self objectAtIndex: index]);
}


- (nullable CBLReadOnlySubdocument*) subdocumentAtIndex: (NSUInteger)index {
    return $castIf(CBLReadOnlySubdocument, [self objectAtIndex: index]);
}


- (nullable CBLReadOnlyArray*) arrayAtIndex: (NSUInteger)index {
    return $castIf(CBLReadOnlyArray, [self objectAtIndex: index]);
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


#pragma mark - SUBSCRIPTION


- (CBLReadOnlyFragment*) objectAtIndexedSubscript: (NSUInteger)index {
    id value = index < self.count ? [self objectAtIndex: index] : nil;
    return [[CBLReadOnlyFragment alloc] initWithValue: value];
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


#pragma mark - FLEECE


- (FLValue) fleeceValueForIndex: (NSUInteger)index {
    return FLArray_Get(_array, (uint)index);
}


- (id) fleeceValueToObject: (FLValue)value {
    if (value != nullptr)
        return [CBLData fleeceValueToObject: value c4doc: _data.c4doc database: _data.database];
    else
        return nil;
}


@end
