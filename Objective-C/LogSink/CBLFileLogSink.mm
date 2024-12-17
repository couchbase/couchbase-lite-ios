//
//  CBLFileLogSink.mm
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

#import "CBLFileLogSink.h"
#import "CBLDefaults.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"
#import "CBLVersion.h"

@implementation CBLFileLogSink

@synthesize level=_level, directory=_directory, usePlainText=_usePlainText, maxKeptFiles=_maxKeptFiles, maxFileSize=_maxFileSize;

- (instancetype) initWithLevel: (CBLLogLevel)level
                     directory: (NSString*)directory {
    return [self initWithLevel: level
                     directory: directory
                  usePlainText: kCBLDefaultFileLogSinkUsePlaintext
                  maxKeptFiles: kCBLDefaultFileLogSinkMaxKeptFiles
                   maxFileSize: kCBLDefaultFileLogSinkMaxSize];
}

- (instancetype) initWithLevel: (CBLLogLevel) level
                     directory: (NSString*) directory
                  usePlainText: (BOOL) usePlainText
                  maxKeptFiles: (uint64_t) maxKeptFiles
                   maxFileSize: (NSInteger) maxFileSize
{
    self = [super init];
    if (self) {
        CBLAssertNotNil(directory);
        _level = level;
        _directory = directory;
        _usePlainText = usePlainText;
        _maxKeptFiles = maxKeptFiles;
        _maxFileSize = maxFileSize;
    }
    return self;
}

+ (void) setup: (CBLFileLogSink*)logSink {
    NSError* error;
    
    C4LogFileOptions options {};
    if (logSink) {
        if (![self setupLogDirectory: logSink.directory error: &error]) {
            CBLWarnError(Database, @"Cannot setup log directory at %@: %@", logSink.directory, error);
            return;
        }
        
        options = {
            .base_path = CBLStringBytes(logSink.directory),
            .log_level = (C4LogLevel)logSink.level,
            .max_rotate_count = static_cast<int32_t>(logSink.maxKeptFiles - 1),
            .max_size_bytes = logSink.maxFileSize,
            .use_plaintext = logSink.usePlainText,
            .header = CBLStringBytes([CBLVersion userAgent])
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
