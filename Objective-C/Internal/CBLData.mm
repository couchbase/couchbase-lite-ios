//
//  CBLData.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLData.h"
#import "CBLDocument+Internal.h"
#import "CBLInternal.h"
#import "CBLJSON.h"
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"

#define kCBLDictionaryTypeKey @kC4ObjectTypeProperty
#define kCBLBlobTypeName @kC4ObjectType_Blob

NSObject *const kCBLRemovedValue = [[NSObject alloc] init];


@implementation CBLData


+ (id) convertValue: (id)value {
    if ([value isKindOfClass: [CBLDictionary class]]) {
        return value;
    } else if ([value isKindOfClass: [CBLArray class]]) {
        return value;
    } else if ([value isKindOfClass: [CBLReadOnlyDictionary class]]) {
        CBLReadOnlyDictionary* readonly = (CBLReadOnlyDictionary*)value;
        CBLDictionary* dict = [[CBLDictionary alloc] initWithFleeceData: readonly.data];
        return dict;
    } else if ([value isKindOfClass: [CBLReadOnlyArray class]]) {
        CBLReadOnlyArray* readonly = (CBLReadOnlyArray*)value;
        CBLArray* array = [[CBLArray alloc] initWithFleeceData: readonly.data];
        return array;
    } else if ([value isKindOfClass: [NSDictionary class]]) {
        CBLDictionary* dict = [[CBLDictionary alloc] init];
        [dict setDictionary: value];
        return dict;
    } else if ([value isKindOfClass: [NSArray class]]) {
        CBLArray* array = [[CBLArray alloc] init];
        [array setArray: value];
        return array;
    } else if ([value isKindOfClass: [NSDate class]]) {
        return [CBLJSON JSONObjectWithDate: value];
    } else {
        NSParameterAssert(value == kCBLRemovedValue ||
                          value == [NSNull null] ||
                          [value isKindOfClass: [NSString class]] ||
                          [value isKindOfClass: [NSNumber class]] ||
                          [value isKindOfClass: [CBLBlob class]]);
    }
    return value;
}


+ (BOOL) booleanValueForObject: (id)object {
    if (!object || object == [NSNull null])
        return NO;
    else {
        id n = $castIf(NSNumber, object);
        return n ? [n boolValue] : YES;
    }
}


+ (id) fleeceValueToObject: (FLValue)value
                datasource: (id <CBLFLDataSource>)datasource
                  database: (CBLDatabase*)database
{
    switch (FLValue_GetType(value)) {
        case kFLArray: {
            FLArray array = FLValue_AsArray(value);
            id flData = [[CBLFLArray alloc] initWithArray: array
                                               datasource: datasource database: database];
            return [[CBLReadOnlyArray alloc] initWithFleeceData: flData];
        }
        case kFLDict: {
            FLDict dict = FLValue_AsDict(value);
            CBLStringBytes typeKey(kCBLDictionaryTypeKey);
            cbl::SharedKeys sk = database.sharedKeys;
            FLSlice type = FLValue_AsString(FLDict_GetSharedKey(dict, typeKey, &sk));
            if(!type.buf) {
                id flData = [[CBLFLDict alloc] initWithDict: dict
                                                 datasource: datasource database: database];
                return [[CBLReadOnlyDictionary alloc] initWithFleeceData: flData];
            } else {
                id result = FLValue_GetNSObject(value, &sk);
                return [self dictionaryToCBLObject: result database: database];
            }
        }
        default: {
            cbl::SharedKeys sk = database.sharedKeys;
            return FLValue_GetNSObject(value, &sk);
        }
    }
}


+ /* private */ (id) dictionaryToCBLObject: (NSDictionary*)dict database: (CBLDatabase*)database {
    NSString* type = dict[kCBLDictionaryTypeKey];
    if (type) {
        if ([type isEqualToString: kCBLBlobTypeName])
            return [[CBLBlob alloc] initWithDatabase: database properties: dict];
    }
    return nil;
}


@end

