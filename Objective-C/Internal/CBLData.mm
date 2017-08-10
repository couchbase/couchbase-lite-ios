//
//  CBLData.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLData.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"

#define kCBLDictionaryTypeKey @kC4ObjectTypeProperty
#define kCBLBlobTypeName @kC4ObjectType_Blob

NSObject *const kCBLRemovedValue = [[NSObject alloc] init];


@implementation NSObject (CBLConversions)

- (BOOL) cbl_fleeceEncode: (FLEncoder)encoder
                 database: (CBLDatabase*)database
                    error: (NSError**)outError
{
    // This is overridden by CBL content classes like CBLDictionary and CBLBlob...
    FLEncoder_WriteNSObject(encoder, self);
    return YES;
}

- (id) cbl_toPlainObject {
    return self;
}

- (id) cbl_toCBLObject {
    if (self != kCBLRemovedValue) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"Instances of %@ cannot be added to Couchbase Lite documents",
                             [self class]];
    }
    return self;
}

@end


@implementation NSArray (CBLConversions)
- (id) cbl_toCBLObject {
    CBLArray* array = [[CBLArray alloc] init];
    [array setArray: self];
    return array;
}
@end

@implementation NSDictionary (CBLConversions)
- (id) cbl_toCBLObject {
    CBLDictionary* dict = [[CBLDictionary alloc] init];
    [dict setDictionary: self];
    return dict;
}
@end

@implementation NSDate (CBLConversions)
- (id) cbl_toCBLObject {
    return [CBLJSON JSONObjectWithDate: self];
}
@end

@implementation NSString (CBLConversions)
- (id) cbl_toCBLObject {
    return self;
}
@end

@implementation NSNumber (CBLConversions)
- (id) cbl_toCBLObject {
    return self;
}
@end

@implementation NSNull (CBLConversions)
- (id) cbl_toCBLObject {
    return self;
}
@end


@implementation CBLData


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

