//
//  CBLData.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLData.h"
#import "CBLArray.h"
#import "CBLBlob.h"
#import "CBLSubdocument.h"
#import "CBLReadOnlyArray.h"
#import "CBLReadOnlySubdocument.h"

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


@end

