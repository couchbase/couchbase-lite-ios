//
//  CBLError.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/19/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLError.h"

@implementation CBLError

NSString* const kCBLErrorDomain = @"CouchbaseLite";

static NSDictionary* errorDesc;
+ (void) initialize {
    if (self == [CBLError class]) {
        errorDesc = @{
          @(kCBLErrorStatusForbidden) : @"forbidden"
        };
    }
}


+ (NSError*) createError: (CBLErrorStatus)status {
    return [self createError: status description: nil];
}


+ (NSError*) createError: (CBLErrorStatus)status description: (nullable NSString*)description {
    if (!description)
        description = errorDesc[@(status)];
    NSDictionary* info = @{
        NSLocalizedFailureReasonErrorKey: description,
        NSLocalizedDescriptionKey: description
    };
    return [NSError errorWithDomain: kCBLErrorDomain  code: status userInfo: info];
}


@end
