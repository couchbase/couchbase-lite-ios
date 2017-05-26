//
//  CBLStatus.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLStatus.h"
#import "CBLCoreBridge.h"

NSString* const kCBLErrorDomain = @"CouchbaseLite";

static NSDictionary* statusDesc = @{
    @(kCBLStatusForbidden) : @"forbidden",
    @(kCBLStatusNotFound)  : @"not found"
};


BOOL convertError(const C4Error &c4err, NSError** outError) {
    NSCAssert(c4err.code != 0 && c4err.domain != 0, @"No C4Error");
    static NSString* const kNSErrorDomains[kC4MaxErrorDomainPlus1] =
        {nil, @"LiteCore", NSPOSIXErrorDomain, @"3", @"SQLite", @"Fleece", @"DNS", @"WebSocket"};
    if (outError) {
        NSString* msgStr = sliceResult2string(c4error_getMessage(c4err));
        *outError = [NSError errorWithDomain: kNSErrorDomains[c4err.domain] code: c4err.code
                                    userInfo: @{NSLocalizedDescriptionKey: msgStr}];
    }
    return NO;
}


BOOL convertError(const FLError &flErr, NSError** outError) {
    NSCAssert(flErr != 0, @"No C4Error");
    if (outError)
        *outError = [NSError errorWithDomain: FLErrorDomain code: flErr userInfo: nil];
    return NO;
}


BOOL createError(CBLStatus status,  NSError** outError) {
    return createError(status, nil, outError);
}


BOOL createError(CBLStatus status,  NSString* desc, NSError** outError) {
    if (outError) {
        if (!desc)
            desc = statusDesc[@(status)];
        NSDictionary* info = @{ NSLocalizedFailureReasonErrorKey: desc,
                                NSLocalizedDescriptionKey: desc };
        *outError = [NSError errorWithDomain: kCBLErrorDomain  code: status userInfo: info];
    }
    return NO;
}
