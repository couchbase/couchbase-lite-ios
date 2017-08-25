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
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"


@implementation CBLReadOnlyDictionary {
    CBLFLDict* _data;
    FLDict _dict;
    NSArray* _keys;                 // all keys cache
    NSObject* _lock;
}

@synthesize lock=_lock;
@synthesize swiftObject=_swiftObject;

- /* internal */ (instancetype) initWithFleeceData: (nullable CBLFLDict*)data {
    self = [super init];
    if (self) {
        _lock = [[NSObject alloc] init];
        
        self.data = data;
    }
    return self;
}


#pragma mark - Counting Entries


- (NSUInteger) count {
    CBL_LOCK(_lock) {
        return FLDict_Count(_dict);
    }
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


- (long long) longLongForKey: (NSString*)key {
    return FLValue_AsInt([self fleeceValueForKey: key]);
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
    CBL_LOCK(_lock) {
        if (_dict != nullptr)
            return FLValue_GetNSObject((FLValue)_dict, _data.database.sharedKeys);
        else
            return @{};
    }
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
        _dict = data.dict;
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
    CBL_LOCK(_lock) {
        return FL_WriteValue(encoder, (FLValue)_dict, database.sharedKeys);
    }
}


#pragma mark - FLEECE


- (FLValue) fleeceValueForKey: (NSString*)key {
    CBL_LOCK(_lock) {
        if (_dict != nullptr)
            return FLDict_GetValue(_dict, CBLStringBytes(key), _data.database.sharedKeys);
        else
            return nullptr;
    }
}


- (id) fleeceValueToObjectForKey: (NSString*)key {
    CBL_LOCK(_lock) {
        FLValue value = [self fleeceValueForKey: key];
        if (value != nullptr) {
            return [CBLData fleeceValueToObject: value
                                     datasource: _data.datasource
                                       database: _data.database];
        } else
            return nil;
    }
}


- (NSArray*) fleeceKeys {
    CBL_LOCK(_lock) {
        if (!_keys) {
            NSMutableArray* keys = [NSMutableArray arrayWithCapacity: FLDict_Count(_dict)];
            if (_dict != nullptr) {
                FLDictIterator iter;
                FLDictIterator_Begin(_dict, &iter);
                NSString *key;
                while (nullptr != (key = FLDictIterator_GetKey(&iter, _data.database.sharedKeys))) {
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
