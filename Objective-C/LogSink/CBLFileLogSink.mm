//
//  CBLFileLogSink.m
//  CouchbaseLite
//
//  Created by Vlad Velicu on 02/12/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import "CBLFileLogSink.h"
#import "CBLDefaults.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"
#import "CBLVersion.h"

@implementation CBLFileLogSink

@synthesize level=_level, domain=_domain, directory=_directory, usePlainText=_usePlainText, maxKeptFiles=_maxKeptFiles, maxFileSize=_maxFileSize;

- (instancetype) initWithLevel: (CBLLogLevel) level
                        domain: (CBLLogDomain) domain
                     directory: (NSString*) directory
                  usePlainText: (BOOL) usePlainText
                  maxKeptFiles: (uint64_t) maxKeptFiles
                   maxFileSize: (NSInteger) maxFileSize
{
    self = [super init];
    if (self) {
        CBLAssertNotNil(directory);
        _level = level;
        _domain = domain;
        _directory = directory;
        _usePlainText = usePlainText;
        _maxKeptFiles = maxKeptFiles;
        _maxFileSize = maxFileSize;
    }
    [self c4opts];
    return self;
}

- (instancetype) initWithLevel: (CBLLogLevel)level
                        domain: (CBLLogDomain)domain
                     directory: (NSString*)directory {
    return [self initWithLevel: level
                        domain: domain
                     directory: directory
                  usePlainText: kCBLDefaultFileLogSinkUsePlaintext
                  maxKeptFiles: kCBLDefaultFileLogSinkMaxKeptFiles
                   maxFileSize: kCBLDefaultFileLogSinkMaxSize
            ];
}

- (void) c4opts {
    NSError* error;

    if (![self setupLogDirectory: self.directory error: &error]) {
        CBLWarnError(Database, @"Cannot setup log directory at %@: %@", self.directory, error);
        return;
    }
    
    C4LogFileOptions options = {
        .base_path = CBLStringBytes(self.directory),
        .log_level = (C4LogLevel)self.level,
        .max_rotate_count = (int32_t)(self.maxKeptFiles > 0 ? self.maxKeptFiles - 1 : self.maxKeptFiles + 1),
        .max_size_bytes = self.maxFileSize,
        .use_plaintext = self.usePlainText,
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
