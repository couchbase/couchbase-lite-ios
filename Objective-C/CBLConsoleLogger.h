//
//  CBLConsoleLogger.h
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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
#import "CBLLogger.h"

NS_ASSUME_NONNULL_BEGIN

/** Console logger for writing log messages to the system console. */
@interface CBLConsoleLogger : NSObject <CBLLogger>

/** The minimum log level of the log messages to be logged. The default log level for
    console logger is warning. */
@property (nonatomic) CBLLogLevel level;

/** The set of log domains of the log messages to be logged. By default, the log
    messages of all domains will be logged. */
@property (nonatomic) CBLLogDomain domains;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
