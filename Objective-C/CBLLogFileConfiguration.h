//
//  CBLLogFileConfiguration.h
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

/**
 Log file configuration.
 */
@interface CBLLogFileConfiguration : NSObject

/**
 The directory to store the log files.
 */
@property (nonatomic, readonly) NSString* directory;

/**
 To use plain text file format instead of the default binary format.
 */
@property (nonatomic) BOOL usePlainText;

/**
 The maximum size of a log file before being rotated in bytes.
 The default is ``kCBLDefaultLogFileMaxSize``
 */
@property (nonatomic) uint64_t maxSize;

/**
 The Max number of rotated log files to keep.
 The default value is ``kCBLDefaultLogFileMaxRotateCount``
 */
@property (nonatomic) NSInteger maxRotateCount;

/**
 Initializes with a directory to store the log files.

 @param directory The directory.
 @return The CBLLogFileConfiguration object.
 */
- (instancetype) initWithDirectory: (NSString*)directory;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
