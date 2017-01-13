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

extern NSString* const kCBLDefaultDomain;
extern NSString* const kCBLDatabaseDomain;

void cbllog(NSString* domain, C4LogLevel level, NSString *msg, ...)
    __attribute__((format(__NSString__, 3, 4)));

#define CBLDebug(DOMAIN, FMT, ARGS...)   cbllog(kCBL##DOMAIN##Domain, kC4LogDebug, FMT, ##ARGS)
#define CBLLog(DOMAIN, FMT, ARGS...)     cbllog(kCBL##DOMAIN##Domain, kC4LogInfo, FMT, ##ARGS)
#define CBLWarn(DOMAIN, FMT, ARGS...)    cbllog(kCBL##DOMAIN##Domain, kC4LogWarning, FMT, ##ARGS)
#define CBLError(DOMAIN, FMT, ARGS...)   cbllog(kCBL##DOMAIN##Domain, kC4LogError, FMT, ##ARGS)

NS_ASSUME_NONNULL_END
    
#ifdef __cplusplus
}
#endif
