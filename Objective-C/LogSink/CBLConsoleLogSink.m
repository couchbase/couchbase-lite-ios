//
//  CBLConsoleLogSink.m
//  CouchbaseLite
//
//  Created by Vlad Velicu on 02/12/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import "CBLConsoleLogSink.h"

@implementation CBLConsoleLogSink

@synthesize level=_level, domain=_domain;

- (instancetype) initWithLevel: (CBLLogLevel)level
                        domain: (CBLLogDomain)domain {
    self = [super init];
    if (self) {
        _level = level;
        _domain = domain;
    }
    return self;
}

- (instancetype) initWithLevel: (CBLLogLevel)level {
    return [self initWithLevel:level domain:kCBLLogDomainAll];
}

@end
