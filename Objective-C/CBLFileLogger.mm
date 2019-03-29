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

#import "CBLFileLogger.h"
#import "CBLLog+Internal.h"
#import "CBLLogFileConfiguration+Internal.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"
#import "CBLVersion.h"

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
    if (_level != level) {
        _level = level;
        c4log_setBinaryFileLevel((C4LogLevel)level);
    }
}


- (void) setConfig: (CBLLogFileConfiguration*)config {
    if (_config != config) {
        if (config) {
            // Copy and mark as READONLY
            config = [[CBLLogFileConfiguration alloc] initWithConfig: config readonly: YES];
        }
        _config = config;
        [self apply];
    }
}


- (void) logWithLevel: (CBLLogLevel)level
               domain: (CBLLogDomain)domain
              message: (nonnull NSString*)message
{
    // Do nothing: Logging will be done in Lite Core
}


- (void) apply {
    NSError* error;
    
    if (!_config) {
        c4log_setBinaryFileLevel(kC4LogNone);
        return;
    }
    
    if (![self setupLogDirectory: _config.directory error: &error]) {
        CBLWarnError(Database, @"Cannot setup log directory at %@: %@", _config.directory, error);
        return;
    }
    
    CBLStringBytes directory(_config.directory);
    
    C4LogFileOptions options = {
        .log_level = (C4LogLevel)self.level,
        .base_path = directory,
        .max_size_bytes = (int64_t)_config.maxSize,
        .max_rotate_count = (int32_t)_config.maxRotateCount,
        .use_plaintext = (bool)_config.usePlainText,
        .header = CBLStringBytes([CBLVersion userAgent])
    };
    
    C4Error c4err;
    if (!c4log_writeToBinaryFile(options, &c4err)) {
        convertError(c4err, &error);
        CBLWarnError(Database, @"Cannot enable file logging: %@", error);
    }
}


- (BOOL) setupLogDirectory: (NSString*)directory error: (NSError**)outError {
    NSError* error;
    if (![[NSFileManager defaultManager] createDirectoryAtPath: directory
                                   withIntermediateDirectories: YES
                                                    attributes: nil
                                                         error: &error]) {
        if (!CBLIsFileExistsError(error)) {
            if (outError)
                *outError = error;
            return NO;
        }
    }
    return YES;
}

@end
