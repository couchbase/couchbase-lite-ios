//
//  CBLLogSinks+Internal.h
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

#import "CBLLogSinks.h"
#import "CBLConsoleLogSink.h"
#import "CBLCustomLogSink.h"
#import "CBLFileLogSink.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, CBLLogAPI) {
    kCBLLogAPINone,
    kCBLLogAPIOld,
    kCBLLogAPINew,
};

@protocol CBLLogApiSource <NSObject>

@property (nonatomic) CBLLogAPI version;

@end

@interface CBLLogSinks ()

+ (void) writeCBLLog: (C4LogDomain)domain level: (C4LogLevel)level message: (NSString*)message;

+ (void) resetApiVersion;

+ (void) checkLogApiVersion: (id<CBLLogApiSource>) source;

@end

@interface CBLConsoleLogSink () <CBLLogSinkProtocol, CBLLogApiSource>

@end

@interface CBLCustomLogSink () <CBLLogSinkProtocol, CBLLogApiSource>

@end

@interface CBLFileLogSink () <CBLLogSinkProtocol, CBLLogApiSource>

+ (void) setup: (nullable CBLFileLogSink*)logSink;

@end

NS_ASSUME_NONNULL_END
