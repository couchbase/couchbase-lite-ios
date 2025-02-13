//
//  CBLCustomLogSink.h
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

#import <Foundation/Foundation.h>
#import <CouchbaseLite/CBLLogTypes.h>

NS_ASSUME_NONNULL_BEGIN

/** Protocol for custom log sinks to handle log messages. */
@protocol CBLLogSinkProtocol <NSObject>

/** Writes a log message with the given level, domain, and content. */
- (void) writeLogWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message;

@end

/** A log sink that writes log messages to a custom log sink implementation. */
@interface CBLCustomLogSink : NSObject

/** The minimum log level of the log messages to be logged. The default log level is warning. */
@property (nonatomic, readonly) CBLLogLevel level;

/** The set of log domains of the log messages to be logged. The default is all domains. */
@property (nonatomic, readonly) CBLLogDomain domains;

/** The custom log sink implementation that receives the log messages. */
@property (nonatomic, readonly) id<CBLLogSinkProtocol> logSink;

/**
 Initializes a custom log sink with a specified log level and custom log sink implementation.
 
 @param level The minimum log level.
 @param logSink The custom log sink implementation.
 */
- (instancetype) initWithLevel: (CBLLogLevel)level
                       logSink: (id<CBLLogSinkProtocol>)logSink;

/**
 Initializes a custom log sink with a specified log level, log domains, and custom log sink implementation.
 
 @param level The minimum log level.
 @param domains The set of log domains.
 @param logSink The custom log sink implementation.
 */
- (instancetype) initWithLevel: (CBLLogLevel)level
                       domains: (CBLLogDomain)domains
                       logSink: (id<CBLLogSinkProtocol>)logSink;

@end

NS_ASSUME_NONNULL_END
