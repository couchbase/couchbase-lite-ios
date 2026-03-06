//
//  CBLConsoleLogSink.m
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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
#import <os/log.h>

static const char * const kSubsystem = "com.couchbase.CouchbaseLite";

static NSArray* logLevelNames = @[@"Debug", @"Verbose", @"Info", @"WARNING", @"ERROR", @"none"];

@implementation CBLConsoleLogSink

@synthesize level=_level, domains=_domains;

- (instancetype) initWithLevel: (CBLLogLevel)level {
    return [self initWithLevel: level domains: kCBLLogDomainAll];
}

- (instancetype) initWithLevel: (CBLLogLevel)level domains: (CBLLogDomain)domains {
    self = [super init];
    if (self) {
        _level = level;
        _domains = domains;
    }
    return self;
}

- (void) writeLogWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message { 
    if (level < _level || (domain != kCBLLogDomainDefault && (_domains & domain) == 0)) {
        return;
    }
    
    NSString* levelName = logLevelNames[level];
    NSString* domainName = [self domainName: domain];
    os_log_with_type([self osLogForDomain: domain], [self osLogTypeForLevel: level],
                     "CouchbaseLite %{public}@ %{public}@: %{public}@",
                     domainName, levelName, message);
}

- (NSString*) domainName: (CBLLogDomain)domain {
    switch (domain) {
        case kCBLLogDomainDatabase:
            return @"Database";
        case kCBLLogDomainQuery:
            return @"Query";
        case kCBLLogDomainReplicator:
            return @"Replicator";
        case kCBLLogDomainNetwork:
            return @"Network";
        case kCBLLogDomainListener:
            return @"Listener";
        case kCBLLogDomainPeerDiscovery:
            return @"PeerDiscovery";
        case kCBLLogDomainMDNS:
            return @"mDNS";
        case kCBLLogDomainMultipeer:
            return @"Multipeer";
        default:
            return @"Default";
    }
}

- (os_log_type_t) osLogTypeForLevel: (CBLLogLevel)level {
    switch (level) {
        case kCBLLogLevelDebug:
        case kCBLLogLevelVerbose:
            return OS_LOG_TYPE_DEBUG;
        case kCBLLogLevelInfo:
            return OS_LOG_TYPE_INFO;
        case kCBLLogLevelWarning:
            return OS_LOG_TYPE_DEFAULT;
        case kCBLLogLevelError:
            return OS_LOG_TYPE_ERROR;
        default:
            return OS_LOG_TYPE_DEFAULT;
    }
}

- (os_log_t) osLogForDomain: (CBLLogDomain)domain {
    switch (domain) {
        case kCBLLogDomainDatabase: {
            static os_log_t log = os_log_create(kSubsystem, "Database");
            return log;
        }
        case kCBLLogDomainQuery: {
            static os_log_t log = os_log_create(kSubsystem, "Query");
            return log;
        }
        case kCBLLogDomainReplicator: {
            static os_log_t log = os_log_create(kSubsystem, "Replicator");
            return log;
        }
        case kCBLLogDomainNetwork: {
            static os_log_t log = os_log_create(kSubsystem, "Network");
            return log;
        }
        case kCBLLogDomainListener: {
            static os_log_t log = os_log_create(kSubsystem, "Listener");
            return log;
        }
        case kCBLLogDomainPeerDiscovery: {
            static os_log_t log = os_log_create(kSubsystem, "PeerDiscovery");
            return log;
        }
        case kCBLLogDomainMDNS: {
            static os_log_t log = os_log_create(kSubsystem, "mDNS");
            return log;
        }
        case kCBLLogDomainMultipeer: {
            static os_log_t log = os_log_create(kSubsystem, "Multipeer");
            return log;
        }
        default: {
            static os_log_t log = os_log_create(kSubsystem, "Default");
            return log;
        }
    }
}

@end
