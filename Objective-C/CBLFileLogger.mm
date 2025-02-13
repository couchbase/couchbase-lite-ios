//
//  CBLFileLogger.mm
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

#import "CBLDefaults.h"
#import "CBLFileLogger.h"
#import "CBLLog+Internal.h"
#import "CBLLogFileConfiguration+Internal.h"
#import "CBLLogSinks+Internal.h"

@implementation CBLFileLogger

@synthesize level=_level, config=_config;

- (instancetype) initWithDefault {
    self = [super init];
    if (self) {
        _level = kCBLLogLevelNone;
    }
    return self;
}

- (void) setLevel: (CBLLogLevel)level {
    CBL_LOCK(self) {
        if (_level != level) {
            _level = level;
            [self updateFileLogSink];
        }
    }
}

- (CBLLogLevel) level {
    CBL_LOCK(self) {
        return _level;
    }
}

- (void) setConfig: (CBLLogFileConfiguration*)config {
    CBL_LOCK(self) {
        if (_config != config) {
            if (config) {
                // Copy and mark as READONLY
                config = [[CBLLogFileConfiguration alloc] initWithConfig: config readonly: YES];
            }
            _config = config;
        }
        [self updateFileLogSink];
    }
}

- (CBLLogFileConfiguration*) config {
    CBL_LOCK(self) {
        return _config;
    }
}

- (void) updateFileLogSink {
    if(_config) {
        NSInteger maxRotateCount = (_config.maxRotateCount > 0) ? _config.maxRotateCount : kCBLDefaultLogFileMaxRotateCount;
        CBLFileLogSink* sink = [[CBLFileLogSink alloc] initWithLevel: _level
                                                           directory: _config.directory
                                                        usePlaintext: _config.usePlainText
                                                        maxKeptFiles: maxRotateCount + 1
                                                         maxFileSize: _config.maxSize
                                ];
        sink.version = kCBLLogAPIOld;
        CBLLogSinks.file = sink;
    } else {
        CBLFileLogSink* sink = [[CBLFileLogSink alloc] initWithLevel: kCBLLogLevelNone
                                                           directory: @""
                                                        usePlaintext: false
                                                        maxKeptFiles: 0
                                                         maxFileSize: 0
                                ];
        sink.version = kCBLLogAPIOld;
        CBLLogSinks.file = sink;
    }
}

- (void) logWithLevel: (CBLLogLevel)level
               domain: (CBLLogDomain)domain
              message: (nonnull NSString*)message
{
    // Do nothing: Logging is an internal functionality.
}

@end
