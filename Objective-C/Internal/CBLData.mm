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

#define kCBLDictionaryTypeKey @"_cbltype"
#define kCBLBlobTypeName @"blob"

NSObject *const kCBLRemovedValue = [[NSObject alloc] init];

@implementation CBLData


+ (id) convertValue: (id)value listener: (id<CBLObjectChangeListener>)listener {
    if (!value) {
        return kCBLRemovedValue; // Represent removed key
    } else if ([value isKindOfClass: [CBLSubdocument class]]) {
        [((CBLSubdocument*)value).dictionary addChangeListener: listener];
        return value;
    } else if ([value isKindOfClass: [CBLArray class]]) {
        [value addChangeListener: listener];
        return value;
    } else if ([value isKindOfClass: [CBLReadOnlySubdocument class]]) {
        CBLReadOnlySubdocument* readonly = (CBLReadOnlySubdocument*)value;
        CBLSubdocument* subdocument = [[CBLSubdocument alloc] initWithFleeceData: readonly.data];
        [subdocument.dictionary addChangeListener: listener];
        return subdocument;
    } else if ([value isKindOfClass: [CBLReadOnlyArray class]]) {
        CBLReadOnlyArray* readonly = (CBLReadOnlyArray*)value;
        CBLArray* array = [[CBLArray alloc] initWithFleeceData: readonly.data];
        [array addChangeListener: listener];
        return array;
    } else if ([value isKindOfClass: [NSDictionary class]]) {
        CBLSubdocument* subdocument = [[CBLSubdocument alloc] init];
        [subdocument setDictionary: value];
        [subdocument.dictionary addChangeListener: self];
        return subdocument;
    } else if ([value isKindOfClass: [NSArray class]]) {
        CBLArray* array = [[CBLArray alloc] init];
        [array setArray: value];
        [array addChangeListener: self];
        return array;
    } else if ([value isKindOfClass: [NSDate class]]) {
        return [CBLJSON JSONObjectWithDate: value];
    } else {
        Assert(value == [NSNull null] ||
               [value isKindOfClass: [NSString class]] ||
               [value isKindOfClass: [NSNumber class]] ||
               [value isKindOfClass: [CBLBlob class]], @"Unsupported value type.");
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
                     c4doc: (CBLC4Document*)c4doc
                  database: (CBLDatabase*)database
{
    switch (FLValue_GetType(value)) {
        case kFLArray: {
            FLArray array = FLValue_AsArray(value);
            id data = [[CBLFLArray alloc] initWithArray: array c4doc: c4doc database: database];
            return [[CBLReadOnlyArray alloc] initWithFleeceData: data];
        }
        case kFLDict: {
            FLDict dict = FLValue_AsDict(value);
            CBLStringBytes typeKey(kCBLDictionaryTypeKey);
            cbl::SharedKeys sk = database.sharedKeys;
            FLSlice type = FLValue_AsString(FLDict_GetSharedKey(dict, typeKey, &sk));
            if(!type.buf) {
                id data = [[CBLFLDict alloc] initWithDict: dict c4doc: c4doc database: database];
                return [[CBLReadOnlySubdocument alloc] initWithFleeceData: data];
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

