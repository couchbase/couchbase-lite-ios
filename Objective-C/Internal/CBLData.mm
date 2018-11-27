//
//  CBLData.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLData.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLJSON.h"

#define kCBLMutableDictionaryTypeKey @kC4ObjectTypeProperty
#define kCBLBlobTypeName @kC4ObjectType_Blob

NSObject *const kCBLRemovedValue = [[NSObject alloc] init];


@implementation NSObject (CBLConversions)

- (id) cbl_toPlainObject {
    return self;
}

- (id) cbl_toCBLObject {
    if (self != kCBLRemovedValue) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"%@ is not a valid type. You may only pass NSNumber, "
                             "NSString, NSDate, CBLBlob, CBLDictionary, CBLArray or "
                             "NSDictionary/NSArray containing the above types.", [self class]];
    }
    return self;
}

@end


@implementation NSArray (CBLConversions)
- (id) cbl_toCBLObject {
    return [[CBLMutableArray alloc] initWithData: self];
}
@end

@implementation NSDictionary (CBLConversions)
- (id) cbl_toCBLObject {
    return [[CBLMutableDictionary alloc] initWithData: self];
}
@end

@implementation NSData (CBLConversions)
- (id) cbl_toCBLObject {
    return [[CBLBlob alloc] initWithContentType: @"application/octet-stream" data: self];
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
