//
//  CBLLog.h
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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

@protocol CBLLogger;
@class CBLConsoleLogger;
@class CBLFileLogger;

NS_ASSUME_NONNULL_BEGIN

/**
 Log allows to configure console and file logger or to set a custom logger.
 */
@interface CBLLog : NSObject

/** Console logger writing log messages to the system console. */
@property (readonly, nonatomic) CBLConsoleLogger* console;

/** File logger writing log messages to files. */
@property (readonly, nonatomic) CBLFileLogger* file;

/** For setting a custom logger. Changing the log level of the assigned custom logger will require
 the custom logger to be reassigned so that the change can be affected. */
@property (nonatomic, nullable) id<CBLLogger> custom;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
