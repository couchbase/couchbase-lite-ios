//
//  CBLCustomLogger.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 4/25/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import "CBLCustomLogger.h"
#import "CBLLog+Swift.h"

@implementation CBLCustomLogger {
    CBLCustomLoggerBlock _logger;
}

- (instancetype) initWithLevel: (CBLLogLevel)level logger: (CBLCustomLoggerBlock)logger {
    self = [super initWithLevel: level];
    if (self) {
        _logger = logger;
    }
    return self;
}

//- (void) logWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString *)message {
//    _logger(level, domain, message);
//}

- (void) writeLog:(CBLLogLevel)level domain:(CBLLogDomain)domain message:(NSString *)message {
    [NSException raise: NSInternalInconsistencyException
                format: @"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}

@end
