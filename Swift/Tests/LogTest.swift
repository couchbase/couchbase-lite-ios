//
//  LogTest.swift
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

import XCTest
@testable import CouchbaseLiteSwift


class LogTest: CBLTestCase {
    
    var backup: FileLoggerBackup?
    
    override func tearDown() {
        super.tearDown()
        
        if let backup = self.backup {
            Database.log.file.level = backup.level
            Database.log.file.directory = backup.directory
            Database.log.file.maxSize = backup.maxSize
            Database.log.file.maxRotateCount = backup.maxRotateCount
            Database.log.file.usePlainText = backup.usePlainText
            self.backup = nil
        }
    }
    
    func backupFileLogger() {
        backup = FileLoggerBackup(level: Database.log.file.level,
                              directory: Database.log.file.directory,
                           usePlainText: Database.log.file.usePlainText,
                                maxSize: Database.log.file.maxSize,
                         maxRotateCount: Database.log.file.maxRotateCount)
    }
    
    func testCustomLoggingLevels() throws {
        Log.log(domain: .database, level: .info, message: "IGNORE")
        let customLogger = LogTestLogger()
        Database.log.custom = customLogger
        
        for i in (1...5).reversed() {
            customLogger.reset()
            customLogger.level = LogLevel(rawValue: UInt8(i))!
            Database.log.custom = customLogger
            Log.log(domain: .database, level: .verbose, message: "TEST VERBOSE")
            Log.log(domain: .database, level: .info, message: "TEST INFO")
            Log.log(domain: .database, level: .warning, message: "TEST WARNING")
            Log.log(domain: .database, level: .error, message: "TEST ERROR")
            XCTAssertEqual(customLogger.lines.count, 5 - i)
        }
        
        Database.log.custom = nil
    }
    
    func testPlainTextLoggingLevels() throws {
        backupFileLogger()
        
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("LogTestLogs")
        try? FileManager.default.removeItem(atPath: path)
        
        Database.log.file.directory = path
        Database.log.file.usePlainText = true
        Database.log.file.maxRotateCount = 0
        
        for i in (1...5).reversed() {
            Database.log.file.level = LogLevel(rawValue: UInt8(i))!
            Log.log(domain: .database, level: .verbose, message: "TEST VERBOSE")
            Log.log(domain: .database, level: .info, message: "TEST INFO")
            Log.log(domain: .database, level: .warning, message: "TEST WARNING")
            Log.log(domain: .database, level: .error, message: "TEST ERROR")
        }
        
        let files = try FileManager.default.contentsOfDirectory(atPath: path)
        for file in files {
            let log = (path as NSString).appendingPathComponent(file)
            let content = try NSString(contentsOfFile: log, encoding: String.Encoding.utf8.rawValue)
            
            var lineCount = 0
            content.enumerateLines { (line, stop) in
                lineCount = lineCount + 1
            }
            
            let sfile = file as NSString
            if sfile.range(of: "verbose").location != NSNotFound {
                XCTAssertEqual(lineCount, 2)
            } else if sfile.range(of: "info").location != NSNotFound {
                XCTAssertEqual(lineCount, 3)
            } else if sfile.range(of: "warning").location != NSNotFound {
                XCTAssertEqual(lineCount, 4)
            } else if sfile.range(of: "error").location != NSNotFound {
                XCTAssertEqual(lineCount, 5)
            }
        }
    }
    
}

class LogTestLogger: Logger {
    
    var lines: [String] = []
    
    var level: LogLevel = .none
    
    func reset() {
        lines.removeAll()
    }
    
    func log(level: LogLevel, domain: LogDomain, message: String) {
        lines.append(message)
    }
    
}

struct FileLoggerBackup {
    
    var level: LogLevel
    
    var directory: String
    
    var usePlainText: Bool
    
    var maxSize: UInt64
    
    var maxRotateCount: Int
    
}
