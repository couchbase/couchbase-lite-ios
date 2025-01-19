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

@implementation CBLConsoleLogger

@synthesize level=_level, domains=_domains;

static NSMutableDictionary<NSNumber *, os_log_t>* osLogDictionary;
static NSString* _sysID;

- (instancetype) initWithLogLevel: (CBLLogLevel)level {
    self = [super init];
    if (self) {
        _level = level;
        _domains = kCBLLogDomainAll;
        _sysID = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
        [self initializeOSLogDomains];
    }
    return self;
}

- (void) setLevel: (CBLLogLevel)level {
    _level = level;
    [[CBLLog sharedInstance] synchronizeCallbackLogLevel];
}

- (void) logWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message {
    if (self.level > level || (self.domains & domain) == 0)
        return;
    
    os_log_t osLogDomain = osLogDictionary[@(domain)];
    os_log_type_t osLogType = osLogTypeForLevel(level);
    os_log_with_type(osLogDomain, osLogType, "%@", message);
}

static os_log_type_t osLogTypeForLevel(CBLLogLevel level) {
    switch (level) {
        case kCBLLogLevelDebug:
            return OS_LOG_TYPE_DEBUG;
        case kCBLLogLevelVerbose:
            return OS_LOG_TYPE_INFO; // Map verbose to info
        case kCBLLogLevelInfo:
            return OS_LOG_TYPE_INFO;
        case kCBLLogLevelWarning:
            return OS_LOG_TYPE_ERROR; // Map warning to error
        case kCBLLogLevelError:
            return OS_LOG_TYPE_ERROR;
        default:
            return OS_LOG_TYPE_DEFAULT; // Default log type
    }
}

- (void) initializeOSLogDomains {
    osLogDictionary = [NSMutableDictionary dictionary];
    
    osLogDictionary[@(kCBLLogDomainDatabase)] = os_log_create([_sysID UTF8String], "Database");
    osLogDictionary[@(kCBLLogDomainQuery)] = os_log_create([_sysID UTF8String], "Query");
    osLogDictionary[@(kCBLLogDomainReplicator)] = os_log_create([_sysID UTF8String], "Replicator");
    osLogDictionary[@(kCBLLogDomainNetwork)] = os_log_create([_sysID UTF8String], "Network");
    
    #ifdef COUCHBASE_ENTERPRISE
    osLogDictionary[@(kCBLLogDomainListener)] = os_log_create([_sysID UTF8String], "Listener");
    #endif
}

+ (void) logAlways: (NSString*)message {
    os_log(osLogDictionary[@(kCBLLogDomainDatabase)], "%@", message);
}

@end
