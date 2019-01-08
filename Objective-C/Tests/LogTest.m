//
//  LogTest.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLTestCase.h"
#import "CBLLog+Logging.h"

@interface LogTestLogger : NSObject <CBLLogger>

@property (nonatomic) CBLLogLevel level;

@property (nonatomic, readonly) NSArray* lines;

- (void) reset;

@end

@interface FileLoggerBackup: NSObject

@property (nonatomic) CBLLogLevel level;

@property (nonatomic) NSString* directory;

@property (nonatomic) BOOL usePlainText;

@property (nonatomic) uint64_t maxSize;

@property (nonatomic) NSInteger maxRotateCount;

@end

@interface LogTest : CBLTestCase

@end

@implementation LogTest {
    FileLoggerBackup* _backup;
}

- (void) tearDown {
    [super tearDown];
    if (_backup) {
        CBLDatabase.log.file.level = _backup.level;
        CBLDatabase.log.file.directory = _backup.directory;
        CBLDatabase.log.file.maxSize = _backup.maxSize;
        CBLDatabase.log.file.maxRotateCount = _backup.maxRotateCount;
        CBLDatabase.log.file.usePlainText = _backup.usePlainText;
        _backup = nil;
    }
}


- (void) backupFileLogger {
    _backup = [[FileLoggerBackup alloc] init];
    _backup.level = CBLDatabase.log.file.level;
    _backup.directory = CBLDatabase.log.file.directory;
    _backup.maxSize = CBLDatabase.log.file.maxSize;
    _backup.maxRotateCount = CBLDatabase.log.file.maxRotateCount;
    _backup.usePlainText = CBLDatabase.log.file.usePlainText;
}


- (NSArray<NSURL*>*) logsInDirectory: (nullable NSString*)directory {
    if (directory == nil) {
        directory = CBLDatabase.log.file.directory;
    }
    NSError* error;
    NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsSubdirectoryDescendants | NSDirectoryEnumerationSkipsHiddenFiles;
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL: [NSURL URLWithString: directory]
                                                   includingPropertiesForKeys: @[]
                                                                      options: options
                                                                        error: &error];
    NSPredicate* predicate = [NSPredicate predicateWithFormat: @"pathExtension == 'cbllog'"];
    return [files filteredArrayUsingPredicate: predicate];
}


- (void) testCustomLoggingLevels {
    CBLLogInfo(Database, @"IGNORE");
    LogTestLogger* customLogger = [[LogTestLogger alloc] init];
    CBLDatabase.log.custom = customLogger;
    
    for (NSUInteger i = 5; i >= 1; i--) {
        [customLogger reset];
        customLogger.level = (CBLLogLevel)i;
        CBLDatabase.log.custom = customLogger;
        CBLLogVerbose(Database, @"TEST VERBOSE");
        CBLLogInfo(Database, @"TEST INFO");
        CBLWarn(Database, @"TEST WARNING");
        CBLWarnError(Database, @"TEST ERROR");
        AssertEqual(customLogger.lines.count, 5 - i);
    }
}


- (void) testPlainTextLoggingLevels {
    [self backupFileLogger];
    
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"LogTestLogs"];
    [[NSFileManager defaultManager] removeItemAtPath: path error: nil];
    
    CBLDatabase.log.file.directory = path;
    CBLDatabase.log.file.usePlainText = YES;
    CBLDatabase.log.file.maxRotateCount = 0;
    
    for (NSUInteger i = 5; i >= 1; i--) {
        CBLDatabase.log.file.level = (CBLLogLevel)i;
        CBLLogVerbose(Database, @"TEST VERBOSE");
        CBLLogInfo(Database, @"TEST INFO");
        CBLWarn(Database, @"TEST WARNING");
        CBLWarnError(Database, @"TEST ERROR");
    }
    
    NSError* error;
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: path error: &error];
    for (NSString* file in files) {
        NSString* log = [path stringByAppendingPathComponent: file];
        NSString* content = [NSString stringWithContentsOfFile: log
                                                      encoding: NSUTF8StringEncoding
                                                         error: &error];
        __block int lineCount = 0;
        [content enumerateLinesUsingBlock: ^(NSString *line, BOOL *stop) {
            lineCount++;
        }];
        
        if ([file rangeOfString: @"verbose"].location != NSNotFound)
            AssertEqual(lineCount, 2);
        else if ([file rangeOfString: @"info"].location != NSNotFound)
            AssertEqual(lineCount, 3);
        else if ([file rangeOfString: @"warning"].location != NSNotFound)
            AssertEqual(lineCount, 4);
        else if ([file rangeOfString: @"error"].location != NSNotFound)
            AssertEqual(lineCount, 5);
    }
}


- (void) testDefaultLocation {
    CBLLogInfo(Database, @"TEST INFO");
    
    NSArray* files = [self logsInDirectory: nil];
    
    Assert(files.count >= 5, "because there should be at least 5 log entries in the folder");
}

@end


@implementation LogTestLogger {
    NSMutableArray* _lines;
}

@synthesize level=_level;

- (instancetype) init {
    self = [super init];
    if (self) {
        _level = kCBLLogLevelNone;
        _lines = [NSMutableArray new];
    }
    return self;
}


- (NSArray*) lines {
    return _lines;
}


- (void) reset {
    [_lines removeAllObjects];
}


- (void)logWithLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain message: (NSString*)message {
    [_lines addObject: message];
}

@end


@implementation FileLoggerBackup

@synthesize level=_level, directory=_directory, usePlainText=_usePlainText;
@synthesize maxSize=_maxSize, maxRotateCount=_maxRotateCount;

@end
