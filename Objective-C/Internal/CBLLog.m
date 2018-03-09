//
//  CBLLog.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLLog.h"
#import "CBLLog+Admin.h"
#import "ExceptionUtils.h"
#import "CBLDatabase.h"    // for CBLLogDomain


C4LogDomain kCBL_LogDomainDatabase;
C4LogDomain kCBL_LogDomainQuery;
C4LogDomain kCBL_LogDomainSync;
C4LogDomain kCBL_LogDomainWebSocket;

static const char* kLevelNames[6] = {"Debug", "Verbose", "Info", "WARNING", "ERROR", "none"};


void cblLog(C4LogDomain domain, C4LogLevel level, NSString *msg, ...) {
    const char *cmsg = CFStringGetCStringPtr((__bridge CFStringRef)msg, kCFStringEncodingUTF8);
    Assert(cmsg, @"Couldn't convert cbllog string to C string; maybe it's not a literal?");
    va_list args;
    va_start(args, msg);
    c4vlog(domain, level, cmsg, args);
    va_end(args);
}


static void logCallback(C4LogDomain domain, C4LogLevel level, const char *fmt, va_list args) {
    NSString* message = [[NSString alloc] initWithFormat: @(fmt) arguments: args];
    NSLog(@"CouchbaseLite %s %s: %@", c4log_getDomainName(domain), kLevelNames[level], message);
    if (level >= kC4LogWarning && [NSUserDefaults.standardUserDefaults boolForKey: @"CBLBreakOnWarning"])
        MYBreakpoint();     // stops debugger at breakpoint. You can resume normally.
}


static C4LogLevel string2level(NSString* value) {
    if (value == nil) {
#ifdef DEBUG
        return kC4LogDebug;
#else
        return kC4LogVerbose;
#endif
    }
    
    switch (value.length > 0 ? toupper([value characterAtIndex: 0]) : 'Y') {
        case 'N': case 'F': case '0':
            return kC4LogNone;
        case 'V': case '2':
            return kC4LogVerbose;
        case 'D': case '3'...'9':
            return kC4LogDebug;
        default:
            return kC4LogInfo;
    }
}


static C4LogDomain setNamedLogDomainLevel(const char *domainName, C4LogLevel level) {
    C4LogDomain domain = c4log_getDomain(domainName, false);
    if (domain)
        c4log_setLevel(domain, level);
    return domain;
}


void CBLLog_Init() {
    // First set the default log level, and register the log callback:
    C4LogLevel defaultLevel = string2level([NSUserDefaults.standardUserDefaults objectForKey: @"CBLLogLevel"]);
    c4log_writeToCallback(defaultLevel, &logCallback, false);
    if (defaultLevel != kC4LogWarning)
        NSLog(@"CouchbaseLite default log level is %s and above", kLevelNames[defaultLevel]);

    C4LogLevel domainLevel = (C4LogLevel) MAX(defaultLevel, kC4LogWarning);
    kCBL_LogDomainDatabase  = setNamedLogDomainLevel("DB", domainLevel);
    kCBL_LogDomainQuery     = setNamedLogDomainLevel("Query", domainLevel);
    kCBL_LogDomainSync      = setNamedLogDomainLevel("Sync", domainLevel);
    kCBL_LogDomainWebSocket = setNamedLogDomainLevel("WS", domainLevel);
    
    // Workaround for https://github.com/couchbase/couchbase-lite-ios/issues/2095
    setNamedLogDomainLevel("SQL", kC4LogWarning);

    // Now map user defaults starting with CBLLog... to log levels:
    NSDictionary* defaults = [NSUserDefaults.standardUserDefaults dictionaryRepresentation];
    for (NSString* key in defaults) {
        if ([key hasPrefix: @"CBLLog"] && ![key isEqualToString: @"CBLLogLevel"]) {
            const char *domainName = key.UTF8String + 6;
            if (*domainName == 0)
                domainName = "Default";
            C4LogDomain domain = c4log_getDomain(domainName, true);
            C4LogLevel level = string2level(defaults[key]);
            c4log_setLevel(domain, level);
            NSLog(@"CouchbaseLite logging to %s domain at level %s", domainName, kLevelNames[level]);
        }
    }
}


void CBLLog_SetLevel(CBLLogDomain domain, CBLLogLevel level)  {
    C4LogLevel c4level = (C4LogLevel)level;
    switch (domain) {
        case kCBLLogDomainAll:
            c4log_setLevel(kCBL_LogDomainDatabase, c4level);
            c4log_setLevel(kCBL_LogDomainQuery, c4level);
            c4log_setLevel(kCBL_LogDomainSync, c4level);
            setNamedLogDomainLevel("BLIP", c4level);
            c4log_setLevel(kCBL_LogDomainWebSocket, c4level);
            break;
        case kCBLLogDomainDatabase:
            c4log_setLevel(kCBL_LogDomainDatabase, c4level);
            break;
        case kCBLLogDomainQuery:
            c4log_setLevel(kCBL_LogDomainQuery, c4level);
            break;
        case kCBLLogDomainReplicator:
            c4log_setLevel(kCBL_LogDomainSync, c4level);
            break;
        case kCBLLogDomainNetwork:
            setNamedLogDomainLevel("BLIP", c4level);
            c4log_setLevel(kCBL_LogDomainWebSocket, c4level);
        default:
            break;
    }
}
