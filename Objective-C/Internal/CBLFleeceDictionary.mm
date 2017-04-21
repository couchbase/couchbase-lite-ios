//
//  CBLFleeceDictionary.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFleeceDictionary.h"
#import "CBLFleeceArray.h"
#import "CBLDatabase.h"
#import "CBLDocument+Internal.h"
#import "CBLC4Document.h"
#import "CBLInternal.h"
#import "CBLJSON.h"
#import "CBLReadOnlyArray.h"
#import "CBLReadOnlySubdocument.h"
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"


@implementation CBLFleeceDictionary {
    FLDict _dict;
    CBLC4Document* _document;
    CBLDatabase* _database;
    cbl::SharedKeys _sharedKeys;
}


- (instancetype) initWithDict: (FLDict) dict
                     document: (CBLC4Document*)document
                     database: (CBLDatabase*)database
{
    self = [super init];
    if (self) {
        _dict = dict;
        _document = document;
        _database = database;
        _sharedKeys = _database.sharedKeys;
    }
    return self;
}


+ (instancetype) withDict: (FLDict)dict
                 document: (CBLC4Document*)document
                 database: (CBLDatabase *)database
{
    return [[self alloc] initWithDict: dict document: document database: database];
}


+ (instancetype) empty {
    return [[self alloc] init];
}


- (id<CBLReadOnlyDictionary>) data {
    return self;
}


- (id) documentData {
    return _document;
}


- (NSUInteger) count {
    return FLDict_Count(_dict);
}


- (nullable id) objectForKey: (NSString*)key {
    return [self fleeceValueToObject: [self fleeceValueForKey: key]];
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
    return $castIf(NSString, [self objectForKey: key]);
}


- (nullable NSNumber*) numberForKey: (NSString*)key {
    return $castIf(NSNumber, [self objectForKey: key]);
}


- (nullable NSDate*) dateForKey: (NSString*)key {
    return [CBLJSON dateWithJSONObject: [self stringForKey: key]];
}


- (nullable CBLBlob*) blobForKey: (NSString*)key {
    return $castIf(CBLBlob, [self objectForKey: key]);
}


- (nullable CBLReadOnlySubdocument*) subdocumentForKey: (NSString*)key {
    return $castIf(CBLReadOnlySubdocument, [self objectForKey: key]);
}


- (nullable CBLReadOnlyArray*) arrayForKey: (NSString*)key {
    return $castIf(CBLReadOnlyArray, [self objectForKey: key]);
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
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity: FLDict_Count(_dict)];
    FLDictIterator iter;
    FLDictIterator_Begin(_dict, &iter);
    NSString *key;
    while (nullptr != (key = FLDictIterator_GetKey(&iter, &_sharedKeys))) {
        FLValue value = [self fleeceValueForKey: key];
        id typedObject = [self toTypedObject: value];
        if (typedObject)
            dict[key] = typedObject;
        else
            dict[key] = FLValue_GetNSObject(value, &_sharedKeys);
        FLDictIterator_Next(&iter);
    }
    return dict;
}


#pragma mark - SUBSCRIPTION


- (CBLReadOnlyFragment*) objectForKeyedSubscript: (NSString*)key {
    return [[CBLReadOnlyFragment alloc] initWithValue: [self objectForKey: key]];
}


#pragma mark - FLEECE


- (FLValue) fleeceValueForKey: (NSString*)key {
    return _dict != nullptr ? FLDict_GetSharedKey(_dict, CBLStringBytes(key), &_sharedKeys) : nullptr;
}


- (id) fleeceValueToObject: (FLValue)value {
    switch (FLValue_GetType(value)) {
        case kFLArray: {
            FLArray array = FLValue_AsArray(value);
            id data = [self fleeceArray: array];
            return [[CBLReadOnlyArray alloc] initWithData: data];
        }
        case kFLDict: {
            FLDict dict = FLValue_AsDict(value);
            FLSlice type = [self dictionaryType: dict];
            if(!type.buf) {
                id data = [self fleeceDictionary: dict];
                return [[CBLReadOnlySubdocument alloc] initWithData: data];
            } else {
                id result = FLValue_GetNSObject(value, &_sharedKeys);
                return [self dictionaryToObject: result];
            }
        }
        case kFLUndefined:
            return nil;
        default:
            return FLValue_GetNSObject(value, &_sharedKeys);
    }
}


- (CBLFleeceArray*) fleeceArray: (FLArray)array {
    return [CBLFleeceArray withArray: array document: _document database: _database];
}


- (CBLFleeceDictionary*) fleeceDictionary: (FLDict)dict {
    return [CBLFleeceDictionary withDict: dict document: _document database: _database];
}


- (nullable CBLBlob*) toTypedObject: (FLValue) value {
    if (FLValue_GetType(value) == kFLDict) {
        FLDict dict = FLValue_AsDict(value);
        FLSlice type = [self dictionaryType: dict];
        if(!type.buf) {
            id result = FLValue_GetNSObject(value, &_sharedKeys);
            return [self dictionaryToObject: result];
        }
    }
    return nil;
}


- (FLSlice) dictionaryType: (FLDict)dict {
    FLSlice typeKey = FLSTR("_cbltype");
    FLValue type = FLDict_GetSharedKey(dict, typeKey, &_sharedKeys);
    return FLValue_AsString(type);
}


- (id) dictionaryToObject: (NSDictionary*)dict {
    NSString* type = dict[@"_cbltype"];
    if (type) {
        if ([type isEqualToString: @"blob"])
            return [[CBLBlob alloc] initWithDatabase: _database properties: dict];
    }
    return nil; // Invalid!
}


@end
