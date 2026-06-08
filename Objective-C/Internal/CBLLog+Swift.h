//
//  CBLLog+Swift.h
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

#import "CBLLog.h"
#import "CBLLogTypes.h"
#import "CBLLogger.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^CBLCustomLoggerBlock)(CBLLogLevel, CBLLogDomain, NSString*);

@interface CBLLog ()

+ (void) writeSwiftLog: (CBLLogDomain)domain level: (CBLLogLevel)level message: (NSString*)message;

// Used by the deprecated Swift Log.custom to install a custom logger backed by a block.
- (void) setCustomLoggerWithLevel: (CBLLogLevel)level usingBlock: (CBLCustomLoggerBlock)logger;

@end

NS_ASSUME_NONNULL_END
