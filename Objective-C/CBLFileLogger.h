//
//  CBLFileLogger.h
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

/**
 File logger used for writing log messages to files. The binary file format will be used by default.
 To change the file format to plain text, set the usePlainText property to true.
 */
@interface CBLFileLogger : NSObject <CBLLogger>

/**
 The minimum log level of the log messages to be logged. The default log level for
 file logger is warning.
 */
@property (nonatomic) CBLLogLevel level;

/**
 The directory to store the log files.
 */
@property (nonatomic) NSString* directory;

/**
 To use plain text file format instead of the default binary format.
 */
@property (nonatomic) BOOL usePlainText;

/**
 The maximum size of a log file before being rotation. The default is 1024 bytes.
 */
@property (nonatomic) uint64_t maxSize;


/**
 The maximum number of rotated log files to keep. The default is 1 which means no rotation.
 */
@property (nonatomic) NSInteger maxRotateCount;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
