//
//  CBLLog.mm
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

#import "CBLLog+Swift.h"
#import "CBLLogSinks+Internal.h"
#import "CBLLog+Internal.h"
#import "CBLLog+Deprecated.h"
#import "CBLLog.h"
#import "CBLConsoleLogger.h"
#import "CBLFileLogger.h"
#import "CBLLogger.h"
#import "CBLLock.h"
#import "CBLException.h"

// Bridges the deprecated custom logger (id<CBLLogger>) onto a new CBLCustomLogSink.
@interface CBLCustomLogger : NSObject <CBLLogger>
- (instancetype) initWithLevel: (CBLLogLevel)level logger: (CBLCustomLoggerBlock)logger;
@end

@interface CBLCustomLogSinkBridge : NSObject <CBLLogSinkProtocol>
- (instancetype) initWithLogger: (id<CBLLogger>)logger;
@end

@implementation CBLLog

@synthesize console=_console, file=_file, custom=_custom;

- (instancetype) initWithDefault {
    self = [super init];
    if (self) {
        // Ensure the new logging system is initialized:
        CBLAssertNotNil(CBLLogSinks.self);

        // Create the deprecated console and file loggers (they bridge to CBLLogSinks):
        _console = [[CBLConsoleLogger alloc] initWithDefault];
        _file = [[CBLFileLogger alloc] initWithDefault];
    }
    return self;
}

#pragma mark - Public (Deprecated)

- (id<CBLLogger>) custom {
    CBL_LOCK(self) {
        return _custom;
    }
}

- (void) setCustom: (id<CBLLogger>)custom {
    CBL_LOCK(self) {
        _custom = custom;
        [self updateCustomLogSink];
    }
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
    // Always install an Old-version sink (even when _custom is nil) so the deprecated
    // API consistently commits kCBLLogAPIOld. Setting CBLLogSinks.custom = nil would pass
    // a nil source to checkLogApiVersion, which defaults to kCBLLogAPINew and would then
    // conflict with the old API.
    CBLCustomLogSinkBridge* bridge = [[CBLCustomLogSinkBridge alloc] initWithLogger: _custom];
    CBLCustomLogSink* sink = [[CBLCustomLogSink alloc] initWithLevel: _custom.level logSink: bridge];
    sink.version = kCBLLogAPIOld;
    CBLLogSinks.custom = sink;
}

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
        case kCBLLogDomainMDNS:
            c4Domain = kCBL_LogDomainMDNS;
            break;
        case kCBLLogDomainMultipeer:
            c4Domain = kCBL_LogDomainP2P;
            break;
        default:
            c4Domain = kCBL_LogDomainDatabase;
    }
    writeCBLLogMessage(c4Domain, (C4LogLevel)level, @"%@", message);
}

- (void) setCustomLoggerWithLevel: (CBLLogLevel)level usingBlock: (CBLCustomLoggerBlock)logger {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.custom = [[CBLCustomLogger alloc] initWithLevel: level logger: logger];
#pragma clang diagnostic pop
}

@end

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

- (void) logWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message {
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
