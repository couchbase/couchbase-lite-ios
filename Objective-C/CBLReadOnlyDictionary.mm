//
//  CBLReadOnlyDictionary.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyDictionary.h"
#import "CBLReadOnlyDictionary+Swift.h"
#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLInternal.h"
#import "CBLJSON.h"
#import "CBLStringBytes.h"
#import "CBLSharedKeys.hh"


@implementation CBLReadOnlyDictionary {
    CBLFLDict* _data;
    FLDict _dict;
    cbl::SharedKeys _sharedKeys;
}

@synthesize data=_data, swiftObject=_swiftObject;

- /* internal */ (instancetype) initWithFleeceData: (nullable CBLFLDict*)data {
    self = [super init];
    if (self) {
        self.data = data;
    }
    return self;
}


- (NSUInteger) count {
    return FLDict_Count(_dict);
}


- (nullable id) objectForKey: (NSString*)key {
    return [self fleeceValueToObjectForKey: key];
}


- (BOOL) booleanForKey: (NSString*)key {
    return FLValue_AsBool([self fleeceValueForKey: key]);
}


- (NSInteger) integerForKey: (NSString*)key {
    return (NSInteger)FLValue_AsInt([self fleeceValueForKey: key]);
}


- (float) floatForKey: (NSString*)key {
    return FLValue_AsFloat([self fleeceValueForKey: key]);
}


- (double) doubleForKey: (NSString*)key {
    return FLValue_AsDouble([self fleeceValueForKey: key]);
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return $castIf(NSString, [self fleeceValueToObjectForKey: key]);
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return $castIf(NSNumber, [self fleeceValueToObjectForKey: key]);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [CBLJSON dateWithJSONObject: [self fleeceValueToObjectForKey: key]];
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return $castIf(CBLBlob, [self fleeceValueToObjectForKey: key]);
}


- (nullable CBLReadOnlyDictionary*) dictionaryForKey: (NSString*)key {
    return $castIf(CBLReadOnlyDictionary, [self fleeceValueToObjectForKey: key]);
}


- (nullable CBLReadOnlyArray*) arrayForKey: (NSString*)key {
    return $castIf(CBLReadOnlyArray, [self fleeceValueToObjectForKey: key]);
}


- (BOOL) containsObjectForKey: (NSString*)key {
    FLValueType type = FLValue_GetType([self fleeceValueForKey: key]);
    return type != kFLUndefined;
}


- (NSArray*) allKeys {
    NSMutableArray* keys = [NSMutableArray array];
    if (_dict != nullptr) {
        FLDictIterator iter;
        FLDictIterator_Begin(_dict, &iter);
        NSString *key;
        while (nullptr != (key = FLDictIterator_GetKey(&iter, &_sharedKeys))) {
            [keys addObject: key];
            FLDictIterator_Next(&iter);
        }
    }
    return keys;
}


- (NSDictionary<NSString*,id>*) toDictionary {
    if (_dict != nullptr)
        return FLValue_GetNSObject((FLValue)_dict, &_sharedKeys);
    else
        return @{};
}


#pragma mark - SUBSCRIPTING


- (CBLReadOnlyFragment*) objectForKeyedSubscript: (NSString*)key {
    return [[CBLReadOnlyFragment alloc] initWithValue: [self fleeceValueToObjectForKey: key]];
}


#pragma mark - INTERNAL


- (void) setData: (CBLFLDict*)data {
    _data = data;
    _dict = data.dict;
    _sharedKeys = data.database.sharedKeys;
}


- (BOOL) isEmpty {
    return self.count == 0;
}


#pragma mark - FLEECE ENCODING


- (BOOL) fleeceEncode: (FLEncoder)encoder
             database: (CBLDatabase*)database
                error: (NSError**)outError
{
    return FLEncoder_WriteValue(encoder, (FLValue)_dict);
}


#pragma mark - FLEECE


- (FLValue) fleeceValueForKey: (NSString*)key {
    return FLDict_GetSharedKey(_dict, CBLStringBytes(key), &_sharedKeys);
}


- (id) fleeceValueToObjectForKey: (NSString*)key {
    FLValue value = [self fleeceValueForKey: key];
    if (value != nullptr)
        return [CBLData fleeceValueToObject: value c4doc: _data.c4doc database: _data.database];
    else
        return nil;
}


@end
