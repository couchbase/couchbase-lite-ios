//
//  CBLConsoleLogSink.h
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

/** A log sink that writes log messages to the console. */
@interface CBLConsoleLogSink : NSObject

/** The minimum log level of the log messages to be logged. The default log level is warning. */
@property (nonatomic, readonly) CBLLogLevel level;

/** The set of log domains of the log messages to be logged. The default is all domains. */
@property (nonatomic, readonly) CBLLogDomain domains;

/**
 Initializes a console log sink with a specified log level.
 
 @param level The minimum log level.
 */
- (instancetype) initWithLevel: (CBLLogLevel)level;

/**
 Initializes a console log sink with a specified log level and log domains.
 
 @param level The minimum log level.
 @param domains The set of log domains.
 */
- (instancetype) initWithLevel: (CBLLogLevel)level domains: (CBLLogDomain)domains;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
