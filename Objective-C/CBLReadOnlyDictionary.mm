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
    NSArray* _keys;                 // all keys cache
}

@synthesize data=_data, swiftObject=_swiftObject;

- /* internal */ (instancetype) initWithFleeceData: (nullable CBLFLDict*)data {
    self = [super init];
    if (self) {
        self.data = data;
    }
    return self;
}


#pragma mark - Counting Entries


- (NSUInteger) count {
    return FLDict_Count(_dict);
}


#pragma mark - Accessing Keys

- (NSArray*) keys {
    return [[self fleeceKeys] copy];
}


#pragma mark - Type Setters


- (nullable CBLReadOnlyArray*) arrayForKey: (NSString*)key {
    return $castIf(CBLReadOnlyArray, [self fleeceValueToObjectForKey: key]);
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return $castIf(CBLBlob, [self fleeceValueToObjectForKey: key]);
}


- (BOOL) booleanForKey: (NSString*)key {
    return FLValue_AsBool([self fleeceValueForKey: key]);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [CBLJSON dateWithJSONObject: [self fleeceValueToObjectForKey: key]];
}


- (nullable CBLReadOnlyDictionary*) dictionaryForKey: (NSString*)key {
    return $castIf(CBLReadOnlyDictionary, [self fleeceValueToObjectForKey: key]);
}


- (nullable id) objectForKey: (NSString*)key {
    return [self fleeceValueToObjectForKey: key];
}


- (double) doubleForKey: (NSString*)key {
    return FLValue_AsDouble([self fleeceValueForKey: key]);
}


- (float) floatForKey: (NSString*)key {
    return FLValue_AsFloat([self fleeceValueForKey: key]);
}


- (NSInteger) integerForKey: (NSString*)key {
    return (NSInteger)FLValue_AsInt([self fleeceValueForKey: key]);
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return $castIf(NSNumber, [self fleeceValueToObjectForKey: key]);
}


- (nullable NSString*) stringForKey: (NSString*)key {
    return $castIf(NSString, [self fleeceValueToObjectForKey: key]);
}


#pragma mark - Check Existence


- (BOOL) containsObjectForKey: (NSString*)key {
    FLValueType type = FLValue_GetType([self fleeceValueForKey: key]);
    return type != kFLUndefined;
}


#pragma mark - Convert to NSDictionary


- (NSDictionary<NSString*,id>*) toDictionary {
    if (_dict != nullptr)
        return FLValue_GetNSObject((FLValue)_dict, &_sharedKeys);
    else
        return @{};
}


#pragma mark - NSFastEnumeration


- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state
                                  objects: (id __unsafe_unretained [])buffer
                                    count: (NSUInteger)len
{
    return [[self fleeceKeys] countByEnumeratingWithState: state objects: buffer count: len];
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


#pragma mark - CBLConversion


- (id) cbl_toPlainObject {
    return [self toDictionary];
}


- (id) cbl_toCBLObject {
    return [[CBLDictionary alloc] initWithFleeceData: self.data];
}


#pragma mark - FLEECE ENCODING


- (BOOL) cbl_fleeceEncode: (FLEncoder)encoder
                 database: (CBLDatabase*)database
                    error: (NSError**)outError
{
    return FLEncoder_WriteValueWithSharedKeys(encoder, (FLValue)_dict, _sharedKeys);
}


#pragma mark - FLEECE


- (FLValue) fleeceValueForKey: (NSString*)key {
    return FLDict_GetSharedKey(_dict, CBLStringBytes(key), &_sharedKeys);
}


- (id) fleeceValueToObjectForKey: (NSString*)key {
    FLValue value = [self fleeceValueForKey: key];
    if (value != nullptr)
        return [CBLData fleeceValueToObject: value datasource: _data.datasource
                                   database: _data.database];
    else
        return nil;
}


- (NSArray*) fleeceKeys {
    if (!_keys) {
        NSMutableArray* keys = [NSMutableArray arrayWithCapacity: FLDict_Count(_dict)];
        if (_dict != nullptr) {
            FLDictIterator iter;
            FLDictIterator_Begin(_dict, &iter);
            NSString *key;
            while (nullptr != (key = FLDictIterator_GetKey(&iter, &_sharedKeys))) {
                [keys addObject: key];
                FLDictIterator_Next(&iter);
            }
        }
        _keys= keys;
    }
    return _keys;
}


@end
