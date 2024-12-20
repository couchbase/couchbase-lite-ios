//
//  CBLFileLogSink.h
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
#import <CouchbaseLite/CBLLogTypes.h>

NS_ASSUME_NONNULL_BEGIN

@interface CBLFileLogSink : NSObject

/**
 The minimum log level of the log messages to be logged. The default log level for
 file logger is kCBLLogLevelNone which means no logging.
 */
@property (nonatomic, readonly) CBLLogLevel level;

/**
 The directory to store the log files.
 */
@property (nonatomic, copy, readonly) NSString* directory;

/**
 To use plain text file format instead of the default binary format.
 */
@property (nonatomic, readonly) BOOL usePlaintext;

/**
 The maximum size of a log file before being rotated in bytes.
 The default is ``kCBLDefaultMaxKeptFiles``
 */
@property (nonatomic, readonly) NSUInteger maxKeptFiles;

/**
 The Max number of rotated log files to keep.
 The default value is ``kCBLDefaultMaxFileSize``
 */
@property (nonatomic, readonly) NSInteger maxFileSize;

- (instancetype) initWithLevel: (CBLLogLevel) level
                     directory: (NSString*) directory;

- (instancetype) initWithLevel: (CBLLogLevel) level
                     directory: (NSString*) directory
                  usePlaintext: (BOOL) usePlainText
                  maxKeptFiles: (uint64_t) maxKeptFiles
                   maxFileSize: (NSInteger) maxFileSize;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
