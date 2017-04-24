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
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"

#define kCBLDictionaryTypeKey @"_cbltype"

#define kCBLBlobTypeName @"blob"

@implementation CBLData


+ (BOOL) validateValue: (id)value {
    // TODO: This validation could have performance impact.
    return value == nil || value == [NSNull null] ||
        [value isKindOfClass: [NSString class]] ||
        [value isKindOfClass: [NSNumber class]] ||
        [value isKindOfClass: [NSDate class]] ||
        [value isKindOfClass: [CBLBlob class]] ||
        [value isKindOfClass: [CBLSubdocument class]] ||
        [value isKindOfClass: [CBLArray class]] ||
        [value isKindOfClass: [CBLReadOnlySubdocument class]] ||
        [value isKindOfClass: [CBLReadOnlyArray class]] ||
        [value isKindOfClass: [NSDictionary class]] ||
        [value isKindOfClass: [NSArray class]];
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

