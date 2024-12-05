//
//  CBLLogSinks.m
//  CouchbaseLite
//
//  Created by Vlad Velicu on 02/12/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import "CBLLogSinks+Internal.h"
#import "CBLLog+Logging.h"

extern "C" {
#import "ExceptionUtils.h"
}

static const char* kLevelNames[6] = {"Debug", "Verbose", "Info", "WARNING", "ERROR", "none"};
static CBLLogLevel _sDomainsLevel = kCBLLogLevelNone;
static CBLLogLevel _sCallbackLevel = kCBLLogLevelNone;

static CBLConsoleLogSink* _sConsole = nil;
static CBLCustomLogSink* _sCustom = nil;
static CBLFileLogSink* _sFile = nil;

@implementation CBLLogSinks

@synthesize console = _console, file = _file, custom = _custom;
NSDictionary* domainDictionary = nil;

- (instancetype) init {
    self = [super init];
    if (self) {
        updateLogLevels();
    }
    return self;
}

- (void) setConsoleSink: (CBLConsoleLogSink*) console {
    _console = console;
    updateLogLevels();
}

- (void) setFileSink: (CBLFileLogSink*) file {
    if(file.level != _file.level) {
        c4log_setBinaryFileLevel((C4LogLevel)file.level);
    }
    _file = file;
    updateLogLevels();
}

- (void) setCustomSink: (CBLCustomLogSink*) custom {
    _custom = custom;
    updateLogLevels();
}


- (void)setConsole:(CBLConsoleLogSink*)console {
    _console = console;
    updateLogLevels();
}

static void c4Callback(C4LogDomain d, C4LogLevel l, const char *msg, va_list args) {
    NSString* message = [NSString stringWithUTF8String: msg];
    
    CBLLogSinks* sinks = [CBLLogSinks sharedInstance];
    
    CBLLogLevel level = (CBLLogLevel)l;
    CBLLogDomain domain = toCBLLogDomain(d);
    
    logConsoleSink(sinks.console, level, domain, message);
    logCustomSink(sinks.custom, level, domain, message);
}

static void logConsoleSink(CBLConsoleLogSink* console, CBLLogLevel level, CBLLogDomain domain, NSString* msg){
    if (level < console.level || (console.domain & domain) == 0) {
        return;
    }
    NSString* levelName = CBLLog_GetLevelName(level);
    NSString* domainName = CBLLog_GetDomainName(domain);
    NSLog(@"CouchbaseLite %@ %@: %@", domainName, levelName, msg);
}

static void logCustomSink(CBLCustomLogSink* custom, CBLLogLevel level, CBLLogDomain domain, NSString* msg) {
    if (custom.logSink == nil || level < custom.level || (custom.domain & domain) == 0) {
        return;
    }
    [custom.logSink writeLog:level domain:domain message:msg];
}

static void updateLogLevels() {
    CBLLogLevel customLevel = (_sCustom.logSink != nil) ? _sCustom.level : kCBLLogLevelNone;
    CBLLogLevel callbackLevel = std::min(_sConsole.level, customLevel);
    CBLLogLevel domainsLevel = std::min(callbackLevel, _sFile.level);
    C4LogLevel c4Level = (C4LogLevel)domainsLevel;
    
    if(_sDomainsLevel != domainsLevel) {
        const NSArray* c4Domains = @[@"DB", @"Query", @"Sync", @"WS", @"Listener"];
        for (NSString* domain in c4Domains) {
            C4LogDomain c4domain = c4log_getDomain([domain UTF8String], true);
            if (c4domain)
                c4log_setLevel(c4domain, c4Level);
        }
        
        const NSArray* platformDomains = @[@"BLIP", @"BLIPMessages", @"SyncBusy", @"TLS", @"Changes", @"Zip"];
        for (NSString* domain in platformDomains) {
            C4LogDomain c4domain = c4log_getDomain([domain UTF8String], false);
            if (c4domain)
                c4log_setLevel(c4domain, c4Level);
        }
        _sDomainsLevel = domainsLevel;
    }
    
    if (_sCallbackLevel != callbackLevel) {
        c4log_writeToCallback(c4Level, &c4Callback, true);
        _sCallbackLevel = callbackLevel;
    }
}

// unused yet
static void log(C4LogDomain d, C4LogLevel l, const char *msg) {
    NSString* message = [NSString stringWithUTF8String: msg];
    
    CBLLogSinks* sinks = [CBLLogSinks sharedInstance];
    
    CBLLogLevel level = (CBLLogLevel)l;
    CBLLogDomain domain = toCBLLogDomain(d);
    
    logConsoleSink(sinks.console, level, domain, message);
    logCustomSink(sinks.custom, level, domain, message);
    
    c4log(d, l, "%s", msg);
}

#pragma mark - Internal
+ (instancetype) sharedInstance {
    static CBLLogSinks* sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
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

static NSString* CBLLog_GetLevelName(CBLLogLevel level) {
    return [NSString stringWithUTF8String: kLevelNames[level]];
}

static NSString* CBLLog_GetDomainName(CBLLogDomain domain) {
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
