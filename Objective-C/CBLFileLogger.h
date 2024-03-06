//
//  CBLFileLogger.h
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
#import <CouchbaseLite/CBLLogger.h>

@class CBLLogFileConfiguration;

NS_ASSUME_NONNULL_BEGIN

/**
 File logger used for writing log messages to files. To enable the file logger,
 setup the log file configuration and specifiy the log level as desired.
 
 It is important to configure your CBLLogFileConfiguration object appropriately before setting
 to a logger. Logger make a copy of the configuration settings you provide and use those settings
 to configure the logger. Once configured, the logger object ignores any changes you make to the
 CBLLogFileConfiguration object.
 */
@interface CBLFileLogger : NSObject <CBLLogger>

/**
 The log file configuration for configuring the log directory, file format, and rotation policy.
 The config property is nil by default. Setting the config property to nil will disable the file
 logging.
 */
@property (nonatomic, nullable) CBLLogFileConfiguration* config;

/**
 The minimum log level of the log messages to be logged. The default log level for
 file logger is kCBLLogLevelNone which means no logging.
 */
@property (nonatomic) CBLLogLevel level;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
