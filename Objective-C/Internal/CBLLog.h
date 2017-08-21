//
//  CBLLog.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#pragma once
#import <Foundation/Foundation.h>
#import "c4.h"

#ifdef __cplusplus
extern "C" {
#endif
    
NS_ASSUME_NONNULL_BEGIN

// Must be called at startup to register the logging callback. It also sets up log domain levels
// based on user defaults named:
//   CBLLogLevel       Sets the default level for all domains; normally Warning
//   CBLLog            Sets the level for the default domain
//   CBLLog___         Sets the level for the '___' domain
// The level values can be Verbose or V or 2 for verbose level,
// or Debug or D or 3 for Debug level,
// or NO or false or 0 to disable entirely;
// any other value, such as YES or Y or 1, sets Info level.
//
// Also, setting the user default CBLBreakOnWarning to YES/true will cause a breakpoint after any
// warning is logged.
void CBLLog_Init(void);


// Log domains. Other domains can be created like so:
//    C4LogDomain kCBLQueryLogDomain;
//    ... then inside a +initialize method:
//    kCBLQueryLogDomain = c4log_getDomain("Query", true);

#define kCBL_LogDomainDefault kC4DefaultLog

// TODO: Sync Lite and LiteCore log domains:
extern C4LogDomain kCBL_LogDomainDatabase;
extern C4LogDomain kCBL_LogDomainDB;        // LiteCore Domain
extern C4LogDomain kCBL_LogDomainQuery;
extern C4LogDomain kCBL_LogDomainSQL;       // LiteCore Domain
extern C4LogDomain kCBL_LogDomainSync;      // LiteCore Domain
extern C4LogDomain kCBL_LogDomainBLIP;      // LiteCore Domain
extern C4LogDomain kCBL_LogDomainActor;     // LiteCore Domain
extern C4LogDomain kCBL_LogDomainWebSocket; // LiteCore Domain
extern C4LogDomain kCBL_LogDomainWSMock;    // LiteCore Domain

// Logging functions. For the domain, just use the part of the name between kCBL… and …LogDomain.
#define CBLLogToAt(DOMAIN, LEVEL, FMT, ...)        \
        ({if (__builtin_expect(c4log_getLevel(kCBL_LogDomain##DOMAIN) <= LEVEL, false))   \
              cblLog(kCBL_LogDomain##DOMAIN, LEVEL, FMT, ## __VA_ARGS__);})
#define CBLLogVerbose(DOMAIN, FMT, ...) CBLLogToAt(DOMAIN, kC4LogVerbose, FMT, ## __VA_ARGS__)
#define CBLLog(DOMAIN, FMT, ...)        CBLLogToAt(DOMAIN, kC4LogInfo,    FMT, ## __VA_ARGS__)
#define CBLWarn(DOMAIN, FMT, ...)       CBLLogToAt(DOMAIN, kC4LogWarning, FMT, ## __VA_ARGS__)
#define CBLWarnError(DOMAIN, FMT, ...)  CBLLogToAt(DOMAIN, kC4LogError,   FMT, ## __VA_ARGS__)

// CBLDebug calls are stripped out of release builds.
#if DEBUG
#define CBLDebug(DOMAIN, FMT, ...)      CBLLogToAt(DOMAIN, kC4LogDebug,   FMT, ## __VA_ARGS__)
#else
#define CBLDebug(DOMAIN, FMT, ...)      ({ })
#endif
    
#define CBLSetLogLevel(DOMAIN, LEVEL) c4log_setLevel(kCBL_LogDomain##DOMAIN, LEVEL)

void cblLog(C4LogDomain domain, C4LogLevel level, NSString *msg, ...)
    __attribute__((format(__NSString__, 3, 4)));

NS_ASSUME_NONNULL_END
    
#ifdef __cplusplus
}
#endif
