//
//  CBLLogSinks.mm
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
#import "CBLLogSinks+Internal.h"
#import "CBLLogSinks+Reset.h"
#import "CBLLog+Logging.h"
#import "CBLStringBytes.h"

C4LogDomain kCBL_LogDomainDatabase;
C4LogDomain kCBL_LogDomainQuery;
C4LogDomain kCBL_LogDomainSync;
C4LogDomain kCBL_LogDomainWebSocket;
C4LogDomain kCBL_LogDomainListener;

static NSArray* c4Domains = @[@"DB", @"Query", @"Sync", @"WS", @"Listener"];
static NSArray* platformDomains = @[@"BLIP", @"BLIPMessages", @"SyncBusy", @"TLS", @"Changes", @"Zip"];

static CBLLogLevel _domainsLevel = kCBLLogLevelNone;
static CBLLogLevel _callbackLevel = kCBLLogLevelNone;

static CBLConsoleLogSink* _console = nil;
static CBLCustomLogSink* _custom = nil;
static CBLFileLogSink* _file = nil;

// Note:
//
// This class is implemented with a minimum logging. The interface defines
// console, custom, and file property as nonatomic, so the expectation
// is not to set up the log sinks object concurrently. However, at least,
// the lock to access console and custom is required to avoid crash from accessing
// garbage objects as LiteCore's log callback may be called from a background thread.

@implementation CBLLogSinks

static CBLLogAPI _vAPI;
NSDictionary* domainDictionary = nil;

+ (void) initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Cache log domain for logging from the platforms:
        kCBL_LogDomainDatabase  = c4log_getDomain("DB", true);
        kCBL_LogDomainQuery  = c4log_getDomain("Query", true);
        kCBL_LogDomainSync  = c4log_getDomain("Sync", true);
        kCBL_LogDomainWebSocket  = c4log_getDomain("WS", true);
        kCBL_LogDomainListener  = c4log_getDomain("Listener", true);
        
        // Create the default warning console log:
        self.console = [[CBLConsoleLogSink alloc] initWithLevel: kCBLLogLevelWarning];
        
        [self resetApiVersion];
    });
}

+ (void) setConsole:(nullable CBLConsoleLogSink*)console {
    CBL_LOCK(self) {
        [self checkLogApiVersion: console];
        _console = console;
    }
    [self updateLogLevels];
}

+ (CBLConsoleLogSink*) console {
    CBL_LOCK(self) {
        return _console;
    }
}

+ (void) setCustom: (nullable CBLCustomLogSink*) custom {
    CBL_LOCK(self) {
        [self checkLogApiVersion: custom];
        _custom = custom;
    }
    [self updateLogLevels];
}

+ (CBLCustomLogSink*) custom {
    CBL_LOCK(self) {
        return _custom;
    }
}

+ (void) setFile: (nullable CBLFileLogSink*) file {
    CBL_LOCK(self) {
        [self checkLogApiVersion: file];
        _file = file;
    }
    [CBLFileLogSink setup: file];
    [self updateLogLevels];
}

+ (CBLFileLogSink*) file {
    CBL_LOCK(self) {
        return _file;
    }
}

+ (void) updateLogLevels {
    CBLConsoleLogSink* console = self.console;
    CBLLogLevel consoleLevel = console != nil ? console.level : kCBLLogLevelNone;
    
    CBLCustomLogSink* custom = self.custom;
    CBLLogLevel customLevel = custom.logSink != nil ? custom.level : kCBLLogLevelNone;
    
    CBLFileLogSink* file = self.file;
    CBLLogLevel fileLevel = file != nil ? file.level : kCBLLogLevelNone;
    
    CBLLogLevel callbackLevel = std::min(consoleLevel, customLevel);
    CBLLogLevel domainsLevel = std::min(callbackLevel, fileLevel);
    C4LogLevel c4Level = (C4LogLevel)domainsLevel;
    
    if (_domainsLevel != domainsLevel) {
        for (NSString* domain in c4Domains) {
            C4LogDomain c4domain = c4log_getDomain([domain UTF8String], false);
            if (c4domain)
                c4log_setLevel(c4domain, c4Level);
        }
        
        for (NSString* domain in platformDomains) {
            C4LogDomain c4domain = c4log_getDomain([domain UTF8String], false);
            if (c4domain)
                c4log_setLevel(c4domain, c4Level);
        }
        _domainsLevel = domainsLevel;
    }
    
    if (_callbackLevel != callbackLevel) {
        c4log_writeToCallback(c4Level, &c4Callback, true);
        _callbackLevel = callbackLevel;
    }
}

static void c4Callback(C4LogDomain c4domain, C4LogLevel c4level, const char *msg, va_list args) {
    NSString* message = [NSString stringWithUTF8String: msg];
    CBLLogLevel level = (CBLLogLevel) c4level;
    CBLLogDomain domain = toCBLLogDomain(c4domain);
    [CBLLogSinks.console writeLogWithLevel: level domain: domain message :message];
    [CBLLogSinks.custom writeLogWithLevel: level domain: domain message :message];
}

+ (void) writeCBLLog: (C4LogDomain)c4domain level: (C4LogLevel)c4level message: (NSString*)message {
    CBLLogLevel level = (CBLLogLevel) c4level;
    CBLLogDomain domain = toCBLLogDomain(c4domain);
    
    [CBLLogSinks.console writeLogWithLevel: level domain: domain message :message];
    [CBLLogSinks.file writeLogWithLevel: level domain: domain message :message];
    [CBLLogSinks.custom writeLogWithLevel: level domain: domain message :message];
}


static CBLLogDomain toCBLLogDomain(C4LogDomain domain) {
    if (!domainDictionary) {
        domainDictionary = @{ @"DB": @(kCBLLogDomainDatabase),
                              @"Query": @(kCBLLogDomainQuery),
                              @"Sync": @(kCBLLogDomainReplicator),
                              @"SyncBusy": @(kCBLLogDomainReplicator),
                              @"Changes": @(kCBLLogDomainDatabase),
                              @"BLIP": @(kCBLLogDomainNetwork),
                              @"WS": @(kCBLLogDomainNetwork),
                              @"BLIPMessages": @(kCBLLogDomainNetwork),
                              @"Zip": @(kCBLLogDomainNetwork),
                              @"TLS": @(kCBLLogDomainNetwork),
#ifdef COUCHBASE_ENTERPRISE
                              @"Listener": @(kCBLLogDomainListener)
#endif
        };
    }
    
    NSString* domainName = [NSString stringWithUTF8String: c4log_getDomainName(domain)];
    NSNumber* mapped = [domainDictionary objectForKey: domainName];
    return mapped ? mapped.integerValue : kCBLLogDomainDatabase;
}

#pragma mark - Internal

+ (void) resetApiVersion {
    _vAPI = kCBLLogAPINone;
}

+ (void) checkLogApiVersion: (id<CBLLogApiSource>) source {
    CBLLogAPI version = source ? source.version :  kCBLLogAPINew;
    if (_vAPI == kCBLLogAPINone) {
        _vAPI = version;
    } else if (_vAPI != version) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"Cannot use both new and old Logging API simultaneously."];
    }
}

@end
