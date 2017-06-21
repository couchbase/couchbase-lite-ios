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
    FLDict _fleeceDict;
    cbl::SharedKeys _sharedKeys;
    NSArray* _keys;                 // all keys cache
    NSObject* _lock;
}

@synthesize swiftObject=_swiftObject;

- /* internal */ (instancetype) initWithFleeceData: (nullable CBLFLDict*)data {
    self = [super init];
    if (self) {
        _lock = [[NSObject alloc] init];
        self.data = data;
    }
    return self;
}


- (NSUInteger) count {
    CBL_LOCK(_lock) {
        return FLDict_Count(_fleeceDict);
    }
}


- (NSArray*) keys {
    return [[self fleeceKeys] copy];
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


- (NSDictionary<NSString*,id>*) toDictionary {
    CBL_LOCK(_lock) {
        if (_fleeceDict != nullptr)
            return FLValue_GetNSObject((FLValue)_fleeceDict, &_sharedKeys);
        else
            return @{};
    }
}


- (id) cbl_toPlainObject {
    return [self toDictionary];
}


- (id) cbl_toCBLObject {
    return [[CBLDictionary alloc] initWithFleeceData: self.data];
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
    CBL_LOCK(_lock) {
        _data = data;
        _fleeceDict = data.dict;
        _sharedKeys = data.database.sharedKeys;
    }
}


- (CBLFLDict*) data {
    CBL_LOCK(_lock) {
        return _data;
    }
}


- (BOOL) isEmpty {
    return self.count == 0;
}


#pragma mark - FLEECE ENCODING


- (BOOL) cbl_fleeceEncode: (FLEncoder)encoder
                 database: (CBLDatabase*)database
                    error: (NSError**)outError
{
    CBL_LOCK(_lock) {
        return FLEncoder_WriteValueWithSharedKeys(encoder, (FLValue)_fleeceDict, _sharedKeys);
    }
}


#pragma mark - FLEECE


- (FLValue) fleeceValueForKey: (NSString*)key {
    CBL_LOCK(_lock) {
        return FLDict_GetSharedKey(_fleeceDict, CBLStringBytes(key), &_sharedKeys);
    }
}


- (id) fleeceValueToObjectForKey: (NSString*)key {
    CBL_LOCK(_lock) {
        FLValue value = [self fleeceValueForKey: key];
        if (value != nullptr)
            return [CBLData fleeceValueToObject: value datasource: _data.datasource
                                       database: _data.database];
        else
            return nil;
    }
}


- (NSArray*) fleeceKeys {
    CBL_LOCK(_lock) {
        if (!_keys) {
            NSMutableArray* keys = [NSMutableArray arrayWithCapacity: FLDict_Count(_fleeceDict)];
            if (_fleeceDict != nullptr) {
                FLDictIterator iter;
                FLDictIterator_Begin(_fleeceDict, &iter);
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
}


@end
