//
//  CBLBaseLogger.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 4/25/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import "CBLBaseLogger.h"
#import "CBLLog+Internal.h"

@implementation CBLBaseLogger

@synthesize level=_level, domains=_domains;

- (instancetype) initWithLevel: (CBLLogLevel)level {
    return [self initWithLevel: level domains: kCBLLogDomainAll];
}

- (instancetype) initWithLevel:(CBLLogLevel)level domains:(CBLLogDomain)domains {
    self = [super init];
    if (self) {
        _level = level;
        _domains = domains;
    }
    return self;
}

- (void) logWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message {
    if (self.level > level || (self.domains & domain) == 0)
        return;
    
    [self writeLog: level domain: domain message: message];
}

- (void) writeLog:(CBLLogLevel)level domain:(CBLLogDomain)domain message:(NSString *)message {
    [NSException raise: NSInternalInconsistencyException
                format: @"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}

@end
