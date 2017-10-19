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
#import "CBLStringBytes.h"

#define kCBLDictionaryTypeKey @kC4ObjectTypeProperty
#define kCBLBlobTypeName @kC4ObjectType_Blob

NSObject *const kCBLRemovedValue = [[NSObject alloc] init];


@implementation NSObject (CBLConversions)

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


namespace cbl {
    bool asBool (id object) {
        // Boolean conversion is a special case because any non-numeric non-null JSON value is true.
        if (object == nil)
            return false;
        else if ([object isKindOfClass: [NSNumber class]])
            return [object boolValue];
        else
            return object != (__bridge id)kCFNull;
    }

    NSInteger asInteger (id object)    {return [$castIf(NSNumber, object) integerValue];}
    long long asLongLong(id object)    {return [$castIf(NSNumber, object) longLongValue];}
    float     asFloat   (id object)    {return [$castIf(NSNumber, object) floatValue];}
    double    asDouble  (id object)    {return [$castIf(NSNumber, object) doubleValue];}
    NSNumber* asNumber  (id object)    {return $castIf(NSNumber, object);}
    NSString* asString  (id object)    {return $castIf(NSString, object);}
    NSDate*   asDate    (id object)    {return [CBLJSON dateWithJSONObject: object];}
}
