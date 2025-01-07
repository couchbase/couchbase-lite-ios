//
//  CBLCustomLogSink.m
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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

#import "CBLCustomLogSink.h"
#import "CBLLogSinks+Internal.h"

@implementation CBLCustomLogSink

@synthesize level = _level, domain=_domain, logSink = _logSink;

- (instancetype) initWithLevel: (CBLLogLevel)level logSink: (id<CBLLogSinkProtocol>)logSink {
    [CBLLogSinks checkLogApiVersion: LogAPINew];
    self = [super init];
    if (self) {
        _domain = kCBLLogDomainAll;
        _level = level;
        _logSink = logSink;
    }
    return self;
}

- (void) writeLogWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message {
    if (level < self.level || (self.domain & domain) == 0) {
        return;
    }
    [self.logSink writeLogWithLevel: level domain: domain message: message];
}

@end
