//
//  CBLCustomLogSink.m
//  CouchbaseLite
//
//  Created by Vlad Velicu on 02/12/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import "CBLCustomLogSink.h"

@implementation CBLCustomLogSink

@synthesize level = _level, domain=_domain, logSink = _logSink;

- (instancetype) initWithLevel: (CBLLogLevel)level
                       logSink: (id<CBLLogSinkProtocol>)logSink
{
    if (self) {
        [super self];
    }
    _level = level;
    _logSink = logSink;
    
    return self;
}

@end
