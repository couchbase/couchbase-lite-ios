//
//  CBLConsoleLogSink.m
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

#import "CBLConsoleLogSink.h"
#import "CBLLogSinks+Internal.h"

@implementation CBLConsoleLogSink

@synthesize level=_level, domain=_domain;

- (instancetype) initWithLevel: (CBLLogLevel)level {
    return [self initWithLevel: level domain: kCBLLogDomainAll];
}

- (instancetype) initWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain {
    self = [super init];
    if (self) {
        _level = level;
        _domain = domain;
    }
    return self;
}

- (void) writeLogWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message { 
    if (level < self.level || (self.domain & domain) == 0) {
        return;
    }
    
    static NSArray* logLevelNames = @[@"Debug", @"Verbose", @"Info", @"WARNING", @"ERROR", @"None"];
    NSString* levelName = logLevelNames[level];
    NSString* domainName = [self domainName: domain];
    NSLog(@"CouchbaseLite %@ %@: %@", domainName, levelName, message);
}

- (NSString*) domainName: (CBLLogDomain)domain {
    switch (domain) {
        case kCBLLogDomainDatabase:
            return @"Database";
            break;
        case kCBLLogDomainQuery:
            return @"Query";
            break;
        case kCBLLogDomainReplicator:
            return @"Replicator";
            break;
        case kCBLLogDomainNetwork:
            return @"Network";
            break;
#ifdef COUCHBASE_ENTERPRISE
        case kCBLLogDomainListener:
            return @"Listener";
            break;
#endif
        default:
            return @"Database";
    }
}

@end
