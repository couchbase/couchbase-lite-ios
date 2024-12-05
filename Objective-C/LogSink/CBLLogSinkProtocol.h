//
//  CBLLogSinkProtocol.h
//  CouchbaseLite
//
//  Created by Vlad Velicu on 05/12/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Log domain.
 */
typedef NS_OPTIONS(NSUInteger, CBLLogDomain) {
    kCBLLogDomainAll            = 1 << 0 | 1 << 1 | 1 << 2 | 1 << 3 | 1 << 4, ///< All domains
    kCBLLogDomainDatabase       = 1 << 0, ///< Database domain.
    kCBLLogDomainQuery          = 1 << 1, ///< Query domain.
    kCBLLogDomainReplicator     = 1 << 2, ///< Replicator domain.
    kCBLLogDomainNetwork        = 1 << 3, ///< Network domain.
#ifdef COUCHBASE_ENTERPRISE
    kCBLLogDomainListener       = 1 << 4  ///< Listener domain.
#endif
};

/**
 Log level.
 */
typedef NS_ENUM(NSUInteger, CBLLogLevel) {
    kCBLLogLevelDebug,      ///< Debug log messages. Only present in debug builds of CouchbaseLite.
    kCBLLogLevelVerbose,    ///< Verbose log messages.
    kCBLLogLevelInfo,       ///< Informational log messages.
    kCBLLogLevelWarning,    ///< Warning log messages.
    kCBLLogLevelError,      ///< Error log messages.
    kCBLLogLevelNone        ///< Disabling log messages of a given log domain.
};

@protocol CBLLogSinkProtocol <NSObject>

- (void) writeLog: (CBLLogLevel)level
           domain: (CBLLogDomain)domain
          message: (NSString*)message;

@end

NS_ASSUME_NONNULL_END
