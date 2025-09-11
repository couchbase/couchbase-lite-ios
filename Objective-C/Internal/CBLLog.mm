//
//  CBLLog.m
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

#import "CBLLog+Swift.h"
#import "CBLLogSinks+Internal.h"
#import "CBLLog+Internal.h"
#import "CBLLog.h"

@implementation CBLLog

void writeCBLLogMessage(C4LogDomain domain, C4LogLevel level, NSString *msg, ...) {
    // If CBLLogSinks is not initialized yet, the domain will be NULL.
    // To avoid crash from checking the log level for this edge case, just return.
    if (!domain) { return; }
    
    if (__builtin_expect(c4log_getLevel(domain) > level, true)) {
        return;
    }
    
    va_list args;
    va_start(args, msg);
    NSString *formatted = [[NSString alloc] initWithFormat: msg arguments: args];
    [CBLLogSinks writeCBLLog: domain level: level message: formatted];
}

#pragma mark - Swift interop

+ (void) writeSwiftLog: (CBLLogDomain)domain level: (CBLLogLevel)level message: (NSString*)message {
    C4LogDomain c4Domain;
    switch (domain) {
        case kCBLLogDomainDatabase:
            c4Domain = kCBL_LogDomainDatabase;
            break;
        case kCBLLogDomainQuery:
            c4Domain = kCBL_LogDomainQuery;
            break;
        case kCBLLogDomainReplicator:
            c4Domain = kCBL_LogDomainSync;
            break;
        case kCBLLogDomainNetwork:
            c4Domain = kCBL_LogDomainWebSocket;
            break;
        case kCBLLogDomainListener:
            c4Domain = kCBL_LogDomainListener;
            break;
        case kCBLLogDomainPeerDiscovery:
            c4Domain = kCBL_LogDomainDiscovery;
            break;
        case kCBLLogDomainMultipeer:
            c4Domain = kCBL_LogDomainP2P;
            break;
        default:
            c4Domain = kCBL_LogDomainDatabase;
    }
    writeCBLLogMessage(c4Domain, (C4LogLevel)level, @"%@", message);
}

@end
