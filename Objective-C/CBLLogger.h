//
//  CBLLogger.h
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

#import <CouchbaseLite/CBLLogTypes.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Logger protocol
 */
__deprecated_msg("Use CBLLogSinkProtocol instead.");
@protocol CBLLogger <NSObject>

/** The minimum log level to be logged. */
@property (readonly, nonatomic) CBLLogLevel level;

/** The callback log method. */
- (void) logWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message;

@end

NS_ASSUME_NONNULL_END
