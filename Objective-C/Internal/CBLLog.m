//
//  CBLLog.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLLog.h"

NSString* const kCBLDefaultDomain = @"";
NSString* const kCBLDatabaseDomain = @"Database";

void cbllog(NSString* domain, C4LogLevel level, NSString *msg, ...) {
    @autoreleasepool {
        va_list args;
        va_start(args, msg);
        NSString* message = [[NSString alloc] initWithFormat: msg arguments: args];
        C4LogDomain d = c4log_getDomain(domain.UTF8String, true);
        c4log(d, level, message.UTF8String);
        va_end(args);
    }
}
