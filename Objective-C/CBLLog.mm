//
//  CBLLog.mm
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
#import "CBLLog+Internal.h"
#import "CBLLog+Logging.h"
#import "CBLLog+Swift.h"
#import "CBLLogSinks+Internal.h"

// For bridging custom logger between Swift and Objective-C
// without making CBLLogger protocol public
__deprecated_msg("Use CBLCustomLogSink instead.");
@interface CBLCustomLogger : NSObject <CBLLogger>
- (instancetype) initWithLevel: (CBLLogLevel)level logger: (CBLCustomLoggerBlock)logger;
@end

// For bridging old custom logger and new custom log sink
@interface CBLCustomLogSinkBridge : NSObject <CBLLogSinkProtocol>
- (instancetype) initWithLogger: (id<CBLLogger>)logger;
@end

@implementation CBLLog

@synthesize console=_console, file=_file, custom=_custom;

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
        // Initialize new logging system
        [CBLLogSinks init];
        
        [CBLLogSinks setVAPI: LogAPINone];
        
        // Create console logger:
        _console = [[CBLConsoleLogger alloc] initWithDefault];
        
        // Create file logger:
        _file = [[CBLFileLogger alloc] initWithDefault];
        
        [CBLLogSinks setVAPI: LogAPINew];
    }
    return self;
}

#pragma mark - Public

- (void) setCustom: (id<CBLLogger>)custom {
    LogAPI version;
    CBL_LOCK(self) {
        version = [CBLLogSinks vAPI];
        _custom = custom;
    }
    [self updateCustomLogSink];
    [CBLLogSinks setVAPI: version];
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

- (void) updateCustomLogSink {
    [CBLLogSinks setVAPI: LogAPINew];
    CBLCustomLogSinkBridge* bridge = [[CBLCustomLogSinkBridge alloc] initWithLogger: _custom];
    CBLLogSinks.custom = [[CBLCustomLogSink alloc] initWithLevel: _custom.level logSink: bridge];
}

void cblLog(C4LogDomain domain, C4LogLevel level, NSString *msg, ...) {
    va_list args;
    va_start(args, msg);
    
    NSString *formatted = [[NSString alloc] initWithFormat: msg arguments: args];
    
    LogAPI version = [CBLLogSinks vAPI];
    [CBLLogSinks setVAPI: LogAPINew];
    [CBLLogSinks writeCBLLog: domain level: level message: formatted];
    [CBLLogSinks setVAPI: version];
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
#ifdef COUCHBASE_ENTERPRISE
        case kCBLLogDomainListener:
            c4Domain = kCBL_LogDomainListener;
            break;
#endif
        default:
            c4Domain = kCBL_LogDomainDatabase;
    }
    cblLog(c4Domain, (C4LogLevel)level, @"%@", message);
}

- (void) setCustomLoggerWithLevel: (CBLLogLevel)level usingBlock: (CBLCustomLoggerBlock)logger {
    self.custom = [[CBLCustomLogger alloc] initWithLevel: level logger: logger];
}

@end

@implementation CBLCustomLogger {
    CBLLogLevel _level;
    CBLCustomLoggerBlock _logger;
}

- (instancetype) initWithLevel: (CBLLogLevel)level logger: (CBLCustomLoggerBlock)logger {
    [CBLLogSinks checkLogApiVersion: LogAPIOld];
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

- (void) logWithLevel:(CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message {
    _logger(level, domain, message);
}

@end

@implementation CBLCustomLogSinkBridge {
    id<CBLLogger> _logger;
}

- (instancetype) initWithLogger: (id<CBLLogger>)logger {
    self = [super init];
    if (self) {
        _logger = logger;
    }
    return self;
}

- (void) writeLogWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message {
    [_logger logWithLevel: level domain: domain message: message];
}

@end
