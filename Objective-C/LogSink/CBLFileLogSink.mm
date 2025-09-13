//
//  CBLFileLogSink.mm
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
//

#import "CBLDefaults.h"
#import "CBLFileLogSink.h"
#import "CBLLogSinks+Internal.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"
#import "CBLVersion.h"

@implementation CBLFileLogSink

@synthesize level=_level, directory=_directory, usePlaintext=_usePlaintext;
@synthesize maxKeptFiles=_maxKeptFiles, maxFileSize=_maxFileSize;

- (instancetype) initWithLevel: (CBLLogLevel)level
                     directory: (NSString*)directory {
    return [self initWithLevel: level
                     directory: directory
                  usePlaintext: kCBLDefaultFileLogSinkUsePlaintext
                  maxKeptFiles: kCBLDefaultFileLogSinkMaxKeptFiles
                   maxFileSize: kCBLDefaultFileLogSinkMaxSize];
}

- (instancetype) initWithLevel: (CBLLogLevel)level
                     directory: (NSString*)directory
                  usePlaintext: (BOOL)usePlaintext
                  maxKeptFiles: (NSInteger)maxKeptFiles
                   maxFileSize: (unsigned long long)maxFileSize
{
    self = [super init];
    if (self) {
        CBLAssertNotNil(directory);
        _level = level;
        _directory = directory;
        _usePlaintext = usePlaintext;
        _maxKeptFiles = maxKeptFiles;
        _maxFileSize = maxFileSize;
    }
    return self;
}

+ (void) setup: (CBLFileLogSink*)logSink {
    NSError* error;
    
    CBLStringBytes directory;
    CBLStringBytes header;
    
    C4LogFileOptions options {};
    
    if (logSink) {
        if (logSink.directory.length > 0 && ![self setupLogDirectory: logSink.directory error: &error]) {
            CBLWarnError(Database, @"Cannot setup log directory at %@: %@", logSink.directory, error);
            return;
        }
        
        directory = CBLStringBytes(logSink.directory, false);
        header = CBLStringBytes([CBLVersion userAgent], false);
        
        options = {
            .base_path = directory,
            .log_level = (C4LogLevel)logSink.level,
            .max_rotate_count = static_cast<int32_t>(logSink.maxKeptFiles - 1),
            .max_size_bytes = static_cast<int64_t>(logSink.maxFileSize),
            .use_plaintext = static_cast<bool>(logSink.usePlaintext),
            .header = header
        };
    } else {
        options.log_level = kC4LogNone;
        options.base_path = kFLSliceNull;
    }
    
    C4Error c4err;
    if (!c4log_writeToBinaryFile(options, &c4err)) {
        convertError(c4err, &error);
        CBLWarnError(Database, @"Cannot enable file logging: %@", error);
    }
}

- (void) writeLogWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message {
    C4LogLevel c4level = (C4LogLevel)level;
    C4LogDomain c4domain;
    switch (domain) {
        case kCBLLogDomainDatabase:
            c4domain = kCBL_LogDomainDatabase;
            break;
        case kCBLLogDomainQuery:
            c4domain = kCBL_LogDomainQuery;
            break;
        case kCBLLogDomainReplicator:
            c4domain = kCBL_LogDomainSync;
            break;
        case kCBLLogDomainNetwork:
            c4domain = kCBL_LogDomainWebSocket;
            break;
#ifdef COUCHBASE_ENTERPRISE
        case kCBLLogDomainListener:
            c4domain = kCBL_LogDomainListener;
            break;
#endif
        default:
            c4domain = kCBL_LogDomainDatabase;
    }
        CBLStringBytes c4msg(message);
        c4slog(c4domain, c4level, c4msg);
}

+ (BOOL) setupLogDirectory: (NSString*)directory error: (NSError**)outError {
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
