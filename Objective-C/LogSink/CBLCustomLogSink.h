//
//  CBLCustomLogSink.h
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

@interface CBLCustomLogSink : NSObject

/** The minimum log level of the log messages to be logged. The default log level for console logger is warning. */
@property (nonatomic, readonly) CBLLogLevel level;

@property (nonatomic, readonly) id<CBLLogSinkProtocol> logSink;

- (instancetype) initWithLevel: (CBLLogLevel) level logSink: (id<CBLLogSinkProtocol>) logSink;

@end

NS_ASSUME_NONNULL_END
