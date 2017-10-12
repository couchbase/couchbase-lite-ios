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


@end

