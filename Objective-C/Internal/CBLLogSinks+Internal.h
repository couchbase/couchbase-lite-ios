//
//  CBLLogSinks+Internal.h
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

#import "CBLLogSinks.h"
#import "CBLConsoleLogSink.h"
#import "CBLCustomLogSink.h"
#import "CBLFileLogSink.h"

NS_ASSUME_NONNULL_BEGIN

// Internal Default Log Domain
extern const CBLLogDomain kCBLLogDomainDefault;

@interface CBLLogSinks ()

+ (void) writeCBLLog: (C4LogDomain)domain level: (C4LogLevel)level message: (NSString*)message;

@end

@interface CBLConsoleLogSink () <CBLLogSinkProtocol>

@end

@interface CBLCustomLogSink () <CBLLogSinkProtocol>

@end

@interface CBLFileLogSink () <CBLLogSinkProtocol>

+ (void) setup: (nullable CBLFileLogSink*)logSink;

@end

NS_ASSUME_NONNULL_END
