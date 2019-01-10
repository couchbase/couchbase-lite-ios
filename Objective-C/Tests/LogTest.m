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


- (NSArray<NSURL*>*) getLogsInDirectory: (nullable NSString*)directory
                             properties: (nullable NSArray<NSURLResourceKey>*)keys
                           onlyInfoLogs: (BOOL)onlyInfo {
    directory = directory ? directory : CBLDatabase.log.file.directory;
    NSURL* path = [NSURL URLWithString: directory];
    AssertNotNil(path);
    
    NSError* error;
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL: path
                                                   includingPropertiesForKeys: keys ? keys : @[]
                                                                      options: 0
                                                                        error: &error];
    NSString* format = @"pathExtension == 'cbllog'";
    if (onlyInfo) {
        format = [NSString stringWithFormat: @"%@ && lastPathComponent BEGINSWITH 'cbl_info_'", format];
    }
    NSPredicate* predicate = [NSPredicate predicateWithFormat: format];
    return [files filteredArrayUsingPredicate: predicate];
}


- (void) writeOneKiloByteOfLog {
    NSString* inputString = @"11223344556677889900"; // 20B + (27B, 24B, 24B, 24B, 29B)  ~44B line
    for(int i = 0; i < 23; i++) {
        CBLDebug(Database, @"%@", inputString);
        CBLLogInfo(Database, @"%@", inputString);
        CBLLogVerbose(Database, @"%@", inputString);
        CBLWarn(Database, @"%@", inputString);
        CBLWarnError(Database, @"%@", inputString);
    }
    [NSThread sleepForTimeInterval: 1];
}


- (void) writeAllLogs: (NSString*)string {
    CBLDebug(Database, @"%@", string);
    CBLLogInfo(Database, @"%@", string);
    CBLLogVerbose(Database, @"%@", string);
    CBLWarn(Database, @"%@", string);
    CBLWarnError(Database, @"%@", string);
}


- (BOOL) isKeywordPresentInAnyLog: (NSString*)keyword path: (NSString*)path {
    NSArray* files = [self getLogsInDirectory: path properties: nil onlyInfoLogs: NO];
    NSError* error;
    for (NSURL* url in files) {
        NSString* contents = [NSString stringWithContentsOfURL: url
                                                      encoding: NSASCIIStringEncoding
                                                         error: &error];
        AssertNil(error);
        if ([contents rangeOfString: keyword].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}


#pragma mark - TESTS


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
                                                      encoding: NSASCIIStringEncoding
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
    
    NSArray* files = [self getLogsInDirectory: nil properties: nil onlyInfoLogs: NO];
    Assert(files.count >= 5, "because there should be at least 5 log entries in the folder");
}


- (void) testDefaultLogFormat {
    CBLLogInfo(Database, @"TEST INFO");
    
    NSArray* files = [self getLogsInDirectory: nil
                                   properties: @[NSFileModificationDate]
                                 onlyInfoLogs: YES];
    NSArray* sorted = [files sortedArrayUsingComparator: ^NSComparisonResult(NSURL* url1,
                                                                             NSURL* url2) {
        NSError* err;
        NSDate *date1 = nil;
        [url1 getResourceValue: &date1
                        forKey: NSURLContentModificationDateKey
                         error: &err];
        
        NSDate* date2 = nil;
        [url2 getResourceValue: &date2
                        forKey: NSURLContentModificationDateKey
                         error: &err];
        return [date1 compare: date2];
    }];
    
    NSURL* last = [sorted lastObject];
    AssertNotNil(last);
    
    NSError* error;
    NSFileHandle* sourceFileHandle = [NSFileHandle fileHandleForReadingFromURL: last error: &error];
    NSData* begainData = [sourceFileHandle readDataOfLength: 4];
    Byte *bytes = (Byte *)[begainData bytes];
    Assert(bytes[0] == 0xcf && bytes[1] == 0xb2 && bytes[2] == 0xab && bytes[3] == 0x1b,
           @"because the log should be in binary format");
}


- (void) testPlainText {
    CBLDatabase.log.file.usePlainText = YES;
    NSString* input = @"SOME TEST MESSAGE";
    CBLLogInfo(Database, @"%@", input);
    
    NSArray* files = [self getLogsInDirectory: nil
                                   properties: @[NSFileModificationDate]
                                 onlyInfoLogs: YES];
    NSArray* sorted = [files sortedArrayUsingComparator: ^NSComparisonResult(NSURL* url1,
                                                                             NSURL* url2) {
        NSError* err;
        NSDate *date1 = nil;
        [url1 getResourceValue: &date1
                        forKey: NSURLContentModificationDateKey
                         error: &err];
        
        NSDate* date2 = nil;
        [url2 getResourceValue: &date2
                        forKey: NSURLContentModificationDateKey
                         error: &err];
        return [date1 compare: date2];
    }];
    
    NSURL* last = [sorted lastObject];
    AssertNotNil(last);
    
    
    NSError* error;
    NSString* contents = [NSString stringWithContentsOfURL: last
                                                  encoding: NSASCIIStringEncoding
                                                     error: &error];
    Assert([contents rangeOfString: input].location != NSNotFound);
}


- (void) testMaxSize {
    [self backupFileLogger];
    
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"LogTestLogs"];
    [[NSFileManager defaultManager] removeItemAtPath: path error: nil];
    
    CBLDatabase.log.file.directory = path;
    CBLDatabase.log.file.usePlainText = YES;
    CBLDatabase.log.file.maxSize = 1024;
    CBLDatabase.log.file.level = kCBLLogLevelDebug;
    
    // 2048 Byte
    [self writeOneKiloByteOfLog];
    [self writeOneKiloByteOfLog];
    
    NSUInteger totalFilesInDirectory = (CBLDatabase.log.file.maxRotateCount + 1) * 5;
#if !DEBUG
    totalFilesInDirectory = totalFilesInDirectory - 1;
#endif
    NSArray* files = [self getLogsInDirectory: path properties: nil onlyInfoLogs: NO];
    AssertEqual(files.count, totalFilesInDirectory);
}


- (void) testDisableLogging {
    [self backupFileLogger];
    
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"LogTestLogs"];
    [[NSFileManager defaultManager] removeItemAtPath: path error: nil];
    
    CBLDatabase.log.file.directory = path;
    CBLDatabase.log.file.level = kCBLLogLevelNone;
    CBLDatabase.log.file.usePlainText = YES;
    
    NSString* inputString = [[NSUUID UUID] UUIDString];
    [self writeAllLogs: inputString];
    
    AssertFalse([self isKeywordPresentInAnyLog: inputString path: path]);
}


- (void) testReEnableLogging {
    [self backupFileLogger];
    
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"LogTestLogs"];
    [[NSFileManager defaultManager] removeItemAtPath: path error: nil];
    
    CBLDatabase.log.file.directory = path;
    CBLDatabase.log.file.level = kCBLLogLevelNone;
    CBLDatabase.log.file.usePlainText = YES;
    
    NSString* inputString = [[NSUUID UUID] UUIDString];
    [self writeAllLogs: inputString];
    
    AssertFalse([self isKeywordPresentInAnyLog: inputString path: path]);
    
    CBLDatabase.log.file.level = kCBLLogLevelVerbose;
    [self writeAllLogs: inputString];
    
    NSArray* files = [self getLogsInDirectory: path properties: nil onlyInfoLogs: NO];
    NSError* error;
    for (NSURL* url in files) {
        if ([url.lastPathComponent hasPrefix: @"cbl_debug_"]) {
            continue;
        }
        NSString* contents = [NSString stringWithContentsOfURL: url
                                                      encoding: NSASCIIStringEncoding
                                                         error: &error];
        AssertNil(error);
        Assert([contents rangeOfString: inputString].location != NSNotFound);
    }
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
