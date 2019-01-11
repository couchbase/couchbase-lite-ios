//
//  CBLLog+Swift.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/13/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLLog.h"
#import "CBLLogger.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^CBLCustomLoggerBlock)(CBLLogLevel, CBLLogDomain, NSString*);

@interface CBLLog ()

- (void) logTo: (CBLLogDomain)domain level: (CBLLogLevel)level message: (NSString*)message;

- (void) setCustomLoggerWithLevel: (CBLLogLevel)level usingBlock: (CBLCustomLoggerBlock)logger;

@end

NS_ASSUME_NONNULL_END
