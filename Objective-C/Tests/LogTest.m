//
//  LogTest.m
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

#import "CBLTestCase.h"
#import "CBLLog+Internal.h"
#import "CBLTestCustomLogSink.h"

@interface LogTest : CBLTestCase

@end

@implementation LogTest {
    NSString* logFileDirectory;
    CBLFileLogSink* _fileBackup;
    CBLConsoleLogSink* _consoleBackup;
}

- (void) setUp {
    [super setUp];
    NSString* folderName = [NSString stringWithFormat: @"LogTestLogs_%d", arc4random()];
    logFileDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent: folderName];
    _fileBackup = CBLLogSinks.file;
    _consoleBackup = CBLLogSinks.console;
}

- (void) tearDown {
    [[NSFileManager defaultManager] removeItemAtPath: logFileDirectory error: nil];
    CBLLogSinks.file = _fileBackup;
    CBLLogSinks.console = _consoleBackup;

    CBLLogSinks.custom = nil;
    _fileBackup = nil;
    _consoleBackup = nil;
    [super tearDown];
}

- (NSArray<NSURL*>*) getLogsInDirectory: (NSString*)directory
                             properties: (nullable NSArray<NSURLResourceKey>*)keys
                           onlyInfoLogs: (BOOL)onlyInfo {
    AssertNotNil(directory);
    NSURL* path = [NSURL fileURLWithPath: directory];
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
    [self writeAllLogs: @"-"]; // 25B : total ~1037Bytes
}

- (void) writeAllLogs: (NSString*)string {
    CBLDebug(Database, @"%@", string);
    CBLLogInfo(Database, @"%@", string);
    CBLLogVerbose(Database, @"%@", string);
    CBLWarn(Database, @"%@", string);
    CBLWarnError(Database, @"%@", string);
}

- (void) testCustomLoggingLevels {
    CBLLogInfo(Database, @"IGNORE");
    for (NSUInteger i = 5; i >= 1; i--) {
        CBLTestCustomLogSink* logSink = [[CBLTestCustomLogSink alloc] init];
        CBLCustomLogSink* customSink = [[CBLCustomLogSink alloc] initWithLevel: (CBLLogLevel)i logSink: logSink];
        CBLLogSinks.custom = customSink;
        CBLLogVerbose(Database, @"TEST VERBOSE");
        CBLLogInfo(Database, @"TEST INFO");
        CBLWarn(Database, @"TEST WARNING");
        CBLWarnError(Database, @"TEST ERROR");
        AssertEqual(logSink.lines.count, 5 - i);
    }
}

- (void) testFileLoggingLevels {
    for (NSUInteger i = 5; i >= 1; i--) {
        CBLLogSinks.file = [[CBLFileLogSink alloc] initWithLevel: (CBLLogLevel)i
                                                       directory: logFileDirectory
                                                    usePlaintext: YES
                                                    maxKeptFiles: kCBLDefaultFileLogSinkMaxKeptFiles
                                                     maxFileSize: kCBLDefaultLogFileMaxSize];
        CBLLogVerbose(Database, @"TEST VERBOSE");
        CBLLogInfo(Database, @"TEST INFO");
        CBLWarn(Database, @"TEST WARNING");
        CBLWarnError(Database, @"TEST ERROR");
    }
    
    NSError* error;
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: logFileDirectory
                                                                         error: &error];
    for (NSString* file in files) {
        NSString* log = [logFileDirectory stringByAppendingPathComponent: file];
        NSString* content = [NSString stringWithContentsOfFile: log
                                                      encoding: NSUTF8StringEncoding
                                                         error: &error];
        __block int lineCount = 0;
        [content enumerateLinesUsingBlock: ^(NSString *line, BOOL *stop) {
            lineCount++;
        }];
        
        if ([file rangeOfString: @"verbose"].location != NSNotFound)
            AssertEqual(lineCount, 3);
        else if ([file rangeOfString: @"info"].location != NSNotFound)
            AssertEqual(lineCount, 4);
        else if ([file rangeOfString: @"warning"].location != NSNotFound)
            AssertEqual(lineCount, 5);
        else if ([file rangeOfString: @"error"].location != NSNotFound)
            AssertEqual(lineCount, 6);
    }
}

- (void) testFileLoggingDefaultBinaryFormat {
    CBLLogSinks.file = [[CBLFileLogSink alloc] initWithLevel: kCBLLogLevelInfo
                                                   directory: logFileDirectory];
    
    CBLLogInfo(Database, @"TEST INFO");
    NSArray* files = [self getLogsInDirectory: CBLLogSinks.file.directory
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
    AssertNotNil(begainData);
    Byte *bytes = (Byte *)[begainData bytes];
    Assert(bytes[0] == 0xcf && bytes[1] == 0xb2 && bytes[2] == 0xab && bytes[3] == 0x1b,
           @"because the log should be in binary format");
}

- (void) testFileLoggingUsePlainText {
    CBLLogSinks.file = [[CBLFileLogSink alloc] initWithLevel: kCBLLogLevelInfo
                                                   directory: logFileDirectory
                                                usePlaintext: YES
                                                maxKeptFiles: kCBLDefaultFileLogSinkMaxKeptFiles
                                                 maxFileSize: kCBLDefaultLogFileMaxSize];
    
    NSString* input = @"SOME TEST MESSAGE";
    CBLLogInfo(Database, @"%@", input);
    
    NSArray* files = [self getLogsInDirectory: CBLLogSinks.file.directory
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

- (void) testFileLoggingLogFilename {
    CBLLogSinks.file = [[CBLFileLogSink alloc] initWithLevel: kCBLLogLevelDebug directory: logFileDirectory];
    
    NSString* regex = @"cbl_(debug|verbose|info|warning|error)_\\d+\\.cbllog";
    NSPredicate* predicate = [NSPredicate predicateWithFormat: @"SELF MATCHES %@", regex];
    NSArray* files = [self getLogsInDirectory: CBLLogSinks.file.directory properties: nil onlyInfoLogs: NO];
    for (NSURL* file in files) {
        Assert([predicate evaluateWithObject: file.lastPathComponent]);
    }
}

- (void) testEnableAndDisableCustomLogging {
    CBLLogInfo(Database, @"IGNORE");
    CBLTestCustomLogSink* logSink = [[CBLTestCustomLogSink alloc] init];
    CBLLogSinks.custom = [[CBLCustomLogSink alloc] initWithLevel: kCBLLogLevelNone logSink: logSink];
    CBLLogVerbose(Database, @"TEST VERBOSE");
    CBLLogInfo(Database, @"TEST INFO");
    CBLWarn(Database, @"TEST WARNING");
    CBLWarnError(Database, @"TEST ERROR");
    AssertEqual(logSink.lines.count, 0);
    
    CBLLogSinks.custom = [[CBLCustomLogSink alloc] initWithLevel: kCBLLogLevelVerbose logSink: logSink];
    CBLLogVerbose(Database, @"TEST VERBOSE");
    CBLLogInfo(Database, @"TEST INFO");
    CBLWarn(Database, @"TEST WARNING");
    CBLWarnError(Database, @"TEST ERROR");
    AssertEqual(logSink.lines.count, 4);
}

- (void) testFileLoggingMaxSize {
    CBLLogSinks.file = [[CBLFileLogSink alloc] initWithLevel: kCBLLogLevelInfo directory: logFileDirectory];
    AssertEqual(CBLLogSinks.file.maxFileSize, kCBLDefaultFileLogSinkMaxSize);
    AssertEqual(CBLLogSinks.file.maxKeptFiles, kCBLDefaultFileLogSinkMaxKeptFiles);
    AssertEqual(CBLLogSinks.file.usePlaintext, kCBLDefaultLogFileUsePlaintext);
    CBLLogSinks.file = [[CBLFileLogSink alloc] initWithLevel: kCBLLogLevelDebug
                                                   directory: logFileDirectory
                                                usePlaintext: YES
                                                maxKeptFiles: 2
                                                 maxFileSize: 1024];
    AssertEqual(CBLLogSinks.file.maxFileSize, 1024);
    AssertEqual(CBLLogSinks.file.maxKeptFiles, 2);
    
    // this should create three files, as the 1KB + 1KB + extra ~400-500Bytes.
    [self writeOneKiloByteOfLog];
    [self writeOneKiloByteOfLog];
    
    NSUInteger totalFilesShouldBeInDirectory = CBLLogSinks.file.maxKeptFiles * 5;
#if !DEBUG
    totalFilesShouldBeInDirectory = totalFilesShouldBeInDirectory - 1;
#endif
    NSArray* files = [self getLogsInDirectory: CBLLogSinks.file.directory properties: nil onlyInfoLogs: NO];
    AssertEqual(files.count, totalFilesShouldBeInDirectory);
}

- (void) testFileLoggingReEnableLogging {
    NSString* inputString = [[NSUUID UUID] UUIDString];
    NSInteger count = 0;
    CBLLogSinks.file = [[CBLFileLogSink alloc] initWithLevel: kCBLLogLevelVerbose
                                                   directory: logFileDirectory
                                                usePlaintext: YES
                                                maxKeptFiles: kCBLDefaultFileLogSinkMaxKeptFiles
                                                 maxFileSize: kCBLDefaultLogFileMaxSize];
    [self writeAllLogs: inputString];
    
    // Disable file logging
    CBLLogSinks.file = nil;
    [self writeAllLogs: inputString];
    
    // Re-enable file logging
    
    CBLLogSinks.file = [[CBLFileLogSink alloc] initWithLevel: kCBLLogLevelVerbose
                                                   directory: logFileDirectory
                                                usePlaintext: YES
                                                maxKeptFiles: kCBLDefaultFileLogSinkMaxKeptFiles
                                                 maxFileSize: kCBLDefaultLogFileMaxSize];
    [self writeAllLogs: inputString];
    NSArray* files = [self getLogsInDirectory: CBLLogSinks.file.directory properties: nil onlyInfoLogs: NO];
    NSError* error;
    for (NSURL* url in files) {
        NSString* contents = [NSString stringWithContentsOfURL: url
                                                      encoding: NSASCIIStringEncoding
                                                         error: &error];
        AssertNil(error);
        if ([contents rangeOfString: inputString].location != NSNotFound) count++;
    }
    
    AssertEqual(count, 8);
}

- (void) testFileLoggingHeader {
    CBLLogSinks.file = [[CBLFileLogSink alloc] initWithLevel: kCBLLogLevelVerbose
                                                   directory: logFileDirectory
                                                usePlaintext: YES
                                                maxKeptFiles: kCBLDefaultFileLogSinkMaxKeptFiles
                                                 maxFileSize: kCBLDefaultLogFileMaxSize];
    [self writeOneKiloByteOfLog];
    NSArray* files = [self getLogsInDirectory: CBLLogSinks.file.directory properties: nil onlyInfoLogs: NO];
    NSError* error;
    for (NSURL* url in files) {
        NSString* contents = [NSString stringWithContentsOfURL: url
                                                      encoding: NSASCIIStringEncoding
                                                         error: &error];
        NSAssert(!error, @"Error reading file: %@", [error localizedDescription]);
        NSArray<NSString *> *lines = [contents componentsSeparatedByString:@"\n"];
        
        // Check if the log file contains at least two lines
        NSAssert(lines.count >= 2, @"log contents should have at least two lines: information and header section");
        NSString *secondLine = lines[1];

        NSAssert([secondLine rangeOfString:@"CouchbaseLite/"].location != NSNotFound, @"Second line should contain 'CouchbaseLite/'");
        NSAssert([secondLine rangeOfString:@"Build/"].location != NSNotFound, @"Second line should contain 'Build/'");
        NSAssert([secondLine rangeOfString:@"Commit/"].location != NSNotFound, @"Second line should contain 'Commit/'");
    }
}

- (void) testNonASCII {
    CBLTestCustomLogSink* logSink = [[CBLTestCustomLogSink alloc] init];
    CBLLogSinks.custom = [[CBLCustomLogSink alloc] initWithLevel: kCBLLogLevelVerbose logSink: logSink];
    
    NSString* hebrew = @"מזג האוויר נחמד היום"; // The weather is nice today.
    CBLMutableDocument* document = [self createDocument: @"doc1"];
    [document setString: hebrew forKey: @"hebrew"];
    NSError* error;
    [self.defaultCollection saveDocument: document error: &error];
    AssertNil(error);
    
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]]
                                     from: kDATA_SRC_DB];
    AssertNotNil(q);
    NSEnumerator* rs = [q execute:&error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], 1u);
    NSString* expectedHebrew = [NSString stringWithFormat: @"[{\"hebrew\":\"%@\"}]", hebrew];
    BOOL found = NO;
    for (NSString* line in logSink.lines) {
        if ([line containsString: expectedHebrew]) {
            found = YES;
        }
    }
    Assert(found);
    
    CBLLogSinks.custom = nil;
}

- (void) testPercentEscape {
    CBLTestCustomLogSink* logSink = [[CBLTestCustomLogSink alloc] init];
    CBLLogSinks.custom = [[CBLCustomLogSink alloc] initWithLevel: kCBLLogLevelInfo logSink: logSink];

    CBLLogInfo(Database, @"Hello %%s there");
    
    BOOL found = NO;
    for (NSString* line in logSink.lines) {
        if ([line containsString:  @"Hello %s there"]) {
            found = YES;
        }
    }
    Assert(found);
    
    CBLLogSinks.custom = nil;
}

@end
