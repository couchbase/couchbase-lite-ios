//
//  CBLFileLogSink.h
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

/** A log sink that writes log messages to files. */
@interface CBLFileLogSink : NSObject

/** The minimum log level for log messages. Default is `kCBLLogLevelNone`, meaning no logging. */
@property (nonatomic, readonly) CBLLogLevel level;

/** The directory where log files will be stored. */
@property (nonatomic, copy, readonly) NSString* directory;

/** To use plain text file format instead of the default binary format. */
@property (nonatomic, readonly) BOOL usePlaintext;

/** The maximum number of log files to keep. Default is `kCBLDefaultMaxKeptFiles`. */
@property (nonatomic, readonly) NSInteger maxKeptFiles;

/** The maximum size of a log file before rotation. Default is `kCBLDefaultMaxFileSize`. */
@property (nonatomic, readonly) unsigned long long maxFileSize;

/**
 Initializes with log level and directory.
 
 @param level The minimum log level.
 @param directory The log file directory.
 */
- (instancetype) initWithLevel: (CBLLogLevel) level
                     directory: (NSString*) directory;

/**
 Initializes with full configuration options.

 @param level The minimum log level.
 @param directory The log file directory.
 @param usePlainText Whether to use plain text format.
 @param maxKeptFiles The maximum number of log files.
 @param maxFileSize The maximum size of a log file.
 */
- (instancetype) initWithLevel: (CBLLogLevel)level
                     directory: (NSString*)directory
                  usePlaintext: (BOOL)usePlainText
                  maxKeptFiles: (NSInteger)maxKeptFiles
                   maxFileSize: (unsigned long long)maxFileSize;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
