//
//  CBLConsoleLogSink.h
//  CouchbaseLite
//
//  Created by Vlad Velicu on 02/12/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CBLLogSinkProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@interface CBLConsoleLogSink : NSObject

/** The minimum log level of the log messages to be logged. The default log level for
    console logger is warning. */
@property (nonatomic, assign, readonly) CBLLogLevel level;

/** The set of log domains of the log messages to be logged. By default, the log
    messages of all domains will be logged. */
@property (nonatomic, assign, readonly) CBLLogDomain domain;

- (instancetype) initWithLevel: (CBLLogLevel)level
                        domain: (CBLLogDomain)domain;

- (instancetype) initWithLevel: (CBLLogLevel)level;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
