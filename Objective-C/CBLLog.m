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
#import "CBLLog+Internal.h"
#import "CBLLog+Logging.h"
#import "CBLLog+Swift.h"
#import "ExceptionUtils.h"

C4LogDomain kCBL_LogDomainDatabase;
C4LogDomain kCBL_LogDomainQuery;
C4LogDomain kCBL_LogDomainSync;
C4LogDomain kCBL_LogDomainWebSocket;

static const char* kLevelNames[6] = {"Debug", "Verbose", "Info", "WARNING", "ERROR", "none"};

// For bridging custom logger between Swift and Objective-C
// without making CBLLogger protocol public
@interface CBLCustomLogger : NSObject <CBLLogger>
- (instancetype) initWithLevel: (CBLLogLevel)level logger: (CBLCustomLoggerBlock)logger;
@end

@implementation CBLLog {
    CBLLogLevel _callbackLogLevel;
}

@synthesize console=_console, file=_file, custom=_custom;

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


static NSDictionary* domainDictionary = nil;

static CBLLogDomain toCBLLogDomain(C4LogDomain domain) {
    if (!domainDictionary) {
        domainDictionary = @{ @"DB": @(kCBLLogDomainDatabase),
                              @"Query": @(kCBLLogDomainQuery),
                              @"Sync": @(kCBLLogDomainReplicator),
                              @"SyncBusy": @(kCBLLogDomainReplicator),
                              @"BLIP": @(kCBLLogDomainNetwork),
                              @"WS": @(kCBLLogDomainNetwork) };
    }
    
    NSString* domainName = [NSString stringWithUTF8String: c4log_getDomainName(domain)];
    NSNumber* mapped = [domainDictionary objectForKey: domainName];
    return mapped ? mapped.integerValue : kCBLLogDomainDatabase;
}


static void logCallback(C4LogDomain domain, C4LogLevel level, const char *fmt, va_list args) {
    CBLLog* log = [CBLLog sharedInstance];
    
    // Level:
    CBLLogLevel lv = (CBLLogLevel)level;
    
    // Validate:
    BOOL shouldLogToConsole = lv >= log.console.level;
    BOOL shouldLogToCustom = log.custom && lv >= log.custom.level;
    if (!shouldLogToConsole && !shouldLogToCustom)
        return;
    
    // Domain:
    CBLLogDomain logDomain = toCBLLogDomain(domain);
    
    // Message:
    static char formatBuffer[2048];
    vsnprintf(formatBuffer, sizeof(formatBuffer), fmt, args);
    NSString* message = [NSString stringWithUTF8String: formatBuffer];
    
    // Console log:
    if (shouldLogToConsole)
        [log.console logWithLevel: lv domain: logDomain message: message];
    
    // Custom log:
    if (shouldLogToCustom)
        [log.custom logWithLevel: lv domain: logDomain message: message];
    
    // Breakpoint if enabled:
    if (level >= kC4LogWarning && [NSUserDefaults.standardUserDefaults boolForKey: @"CBLBreakOnWarning"])
        MYBreakpoint();     // stops debugger at breakpoint. You can resume normally.
}


// Initialize the CBLLog object and register the logging callback.
// It also sets up log domain levels based on user defaults named:
//   CBLLogLevel       Sets the default level for all domains; normally Warning
//   CBLLog            Sets the level for the default domain
//   CBLLog___         Sets the level for the '___' domain
// The level values can be Verbose or V or 2 for verbose level,
// or Debug or D or 3 for Debug level,
// or NO or false or 0 to disable entirely;
// any other value, such as YES or Y or 1, sets Info level.
- (instancetype) initWithDefault {
    self = [super init];
    if (self) {
        // The most default callback log level:
        C4LogLevel callbackLogLevel = kC4LogWarning;
        
        // Check if user overrides the default callback log level:
        NSString* userLogLevel = [NSUserDefaults.standardUserDefaults objectForKey: @"CBLLogLevel"];
        if (userLogLevel)
            callbackLogLevel = string2level(userLogLevel);
        
        // Enable callback logging:
        c4log_writeToCallback(callbackLogLevel, &logCallback, false);
        if (callbackLogLevel != kC4LogWarning)
            NSLog(@"CouchbaseLite minimum log level is %s", kLevelNames[callbackLogLevel]);
        
        // Set log level for each domains to the lowest:
        kCBL_LogDomainDatabase  = setNamedLogDomainLevel("DB", kC4LogDebug);
        kCBL_LogDomainQuery     = setNamedLogDomainLevel("Query", kC4LogDebug);
        kCBL_LogDomainSync      = setNamedLogDomainLevel("Sync", kC4LogDebug);
        kCBL_LogDomainWebSocket = setNamedLogDomainLevel("WS", kC4LogDebug);
        setNamedLogDomainLevel("BLIP", kC4LogDebug);
        setNamedLogDomainLevel("SyncBusy", kC4LogDebug);
        
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
        
        // Keep the current callback log level:
        _callbackLogLevel = (CBLLogLevel)callbackLogLevel;
        
        // Create console logger:
        _console = [[CBLConsoleLogger alloc] initWithLogLevel: _callbackLogLevel];
        
        // Create file logger which will enable file logging immediately with default log rotation:
        _file = [[CBLFileLogger alloc] initWithDefault];
    }
    return self;
}


#pragma mark - Public


- (void) setCustom: (id<CBLLogger>)custom {
    _custom = custom;
    [self synchronizeCallbackLogLevel];
}


#pragma mark - Internal


+ (instancetype) sharedInstance {
    static CBLLog* sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initWithDefault];
    });
    return sharedInstance;
}


- (void) synchronizeCallbackLogLevel {
    // Synchronize log level between console and custom:
    CBLLogLevel syncLogLevel = self.console.level;
    if (self.custom && self.custom.level < syncLogLevel)
        syncLogLevel = self.custom.level;
    
    if (syncLogLevel != _callbackLogLevel) {
        c4log_setCallbackLevel((C4LogLevel)syncLogLevel);
        _callbackLogLevel = syncLogLevel;
    }
}


#pragma mark - CBLLog+Swift


- (void) logTo: (CBLLogDomain)domain level: (CBLLogLevel)level message: (NSString*)message {
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
        default:
            c4Domain = kCBL_LogDomainDatabase;
    }
    cblLog(c4Domain, (C4LogLevel)level, @"%@", message);
}


- (void) setCustomLoggerWithLevel: (CBLLogLevel)level usingBlock: (CBLCustomLoggerBlock)logger {
    self.custom = [[CBLCustomLogger alloc] initWithLevel: level logger: logger];
}

@end


void cblLog(C4LogDomain domain, C4LogLevel level, NSString *msg, ...) {
    va_list args;
    va_start(args, msg);
    NSString *s = [[NSString alloc] initWithFormat: msg arguments: args];
    const char *cmsg = [s cStringUsingEncoding: NSUTF8StringEncoding];
    if (cmsg != NULL) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-security"
        c4log(domain, level, cmsg); // Using cmsg as a non-literal is intended here.
#pragma clang diagnostic pop
        va_end(args);
    } else
        CBLWarn(Database, @"Couldn't convert cbllog string to C string.");
}


NSString* CBLLog_GetLevelName(CBLLogLevel level) {
    return [NSString stringWithUTF8String: kLevelNames[level]];
}


NSString* CBLLog_GetDomainName(CBLLogDomain domain) {
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
        default:
            return @"Database";
    }
}


@implementation CBLCustomLogger {
    CBLLogLevel _level;
    CBLCustomLoggerBlock _logger;
}

- (instancetype) initWithLevel: (CBLLogLevel)level logger: (CBLCustomLoggerBlock)logger {
    self = [super init];
    if (self) {
        _level = level;
        _logger = logger;
    }
    return self;
}


- (CBLLogLevel) level {
    return _level;
}


- (void) logWithLevel:(CBLLogLevel)level domain:(CBLLogDomain)domain message:(NSString *)message {
    _logger(level, domain, message);
}

@end
