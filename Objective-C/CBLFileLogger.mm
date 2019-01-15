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
#import "CBLDatabase+Internal.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"
#import "CBLVersion.h"

#define kCBLFileLoggerDefaultMaxSize 500*1024

@implementation CBLFileLogger

@synthesize level=_level, directory=_directory, usePlainText=_usePlainText;
@synthesize maxSize=_maxSize, maxRotateCount=_maxRotateCount;

- (instancetype) initWithDefault {
    self = [super init];
    if (self) {
        _level = kCBLLogLevelInfo;
        _directory = [self defaultDirectory];
        _usePlainText = NO;
        _maxSize = kCBLFileLoggerDefaultMaxSize;
        _maxRotateCount = 1;
        [self apply];
    }
    return self;
}


- (NSString*) defaultDirectory {
#if !TARGET_OS_IPHONE
    NSString* bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID) {
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
        return [paths[0] stringByAppendingPathComponent:
                [NSString stringWithFormat: @"Logs/%@/CouchbaseLite", bundleID]];
    } else
        return [[NSFileManager.defaultManager currentDirectoryPath]
                stringByAppendingPathComponent: @"CouchbaseLite/Logs"];
#else
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [paths[0] stringByAppendingPathComponent: @"CouchbaseLite/Logs"];
#endif
}


- (void) setLevel: (CBLLogLevel)level {
    if (_level != level) {
        _level = level;
        c4log_setBinaryFileLevel((C4LogLevel)level);
    }
}


- (void) setDirectory: (NSString *)directory {
    if (_directory != directory) {
        _directory = directory;
        [self apply];
    }
}


- (void) setUsePlainText: (BOOL)usePlainText {
    if (_usePlainText != usePlainText) {
        _usePlainText = usePlainText;
        [self apply];
    }
}


- (void) setMaxSize: (uint64_t)maxSize {
    if (_maxSize != maxSize) {
        _maxSize = maxSize;
        [self apply];
    }
}


- (void) setMaxRotateCount: (NSInteger)maxRotateCount {
    if (_maxRotateCount != maxRotateCount) {
        _maxRotateCount = maxRotateCount;
        [self apply];
    }
}


- (void) logWithLevel: (CBLLogLevel)level
               domain: (CBLLogDomain)domain
              message: (nonnull NSString*)message
{
    // Do nothing
}


- (void) apply {
    NSError* error;
    if (![self setupLogDirectory: self.directory error: &error]) {
        CBLWarnError(Database, @"Cannot setup log directory at %@: %@", self.directory, error);
        return;
    }
    
    C4LogFileOptions options = {
        .log_level = (C4LogLevel)self.level,
        .base_path = CBLStringBytes(self.directory),
        .max_size_bytes = (int64_t)self.maxSize,
        .max_rotate_count = (int32_t)self.maxRotateCount,
        .use_plaintext = (bool)self.usePlainText,
        .header = CBLStringBytes([CBLVersion userAgent])
    };
    
    C4Error c4err;
    if (!c4log_writeToBinaryFile(options, &c4err)) {
        convertError(c4err, &error);
        CBLWarnError(Database, @"Cannot enable file logging: %@", error);
    }
    
    c4log_setBinaryFileLevel((C4LogLevel)self.level);
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
