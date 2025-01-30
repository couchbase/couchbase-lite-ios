//
//  CBLConsoleLogger.m
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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

#import "CBLConsoleLogger.h"
#import "CBLLog+Internal.h"
#import "CBLLogSinks+Internal.h"

@implementation CBLConsoleLogger

@synthesize level=_level, domains=_domains;

- (instancetype) initWithDefault {
    self = [super init];
    if (self) {
        _level = kCBLLogLevelWarning;
        _domains = kCBLLogDomainAll;
    }
    return self;
}

- (void) setLevel: (CBLLogLevel)level {
    CBL_LOCK(self) {
        _level = level;
        [self updateConsoleLogSink];
    }
}

- (CBLLogLevel) level {
    CBL_LOCK(self) {
        return _level;
    }
}

- (void) setDomains: (CBLLogDomain)domains {
    CBL_LOCK(self) {
        _domains = domains;
        [self updateConsoleLogSink];
    }
}

- (CBLLogDomain) domains {
    CBL_LOCK(self) {
        return _domains;
    }
}

- (void) updateConsoleLogSink {
    CBLConsoleLogSink* sink = [[CBLConsoleLogSink alloc] initWithLevel: _level domains: _domains];
    sink.version = kCBLLogAPIOld;
    CBLLogSinks.console = sink;
    
}

- (void) logWithLevel: (CBLLogLevel)level
               domain: (CBLLogDomain)domain
              message: (nonnull NSString*)message
{
    // Do nothing: Logging is an internal functionality.
}

@end
