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
    
    // MARK: HELPERS
    
    func backupFileLogger() {
        backup = FileLoggerBackup(level: Database.log.file.level,
                              directory: Database.log.file.directory,
                           usePlainText: Database.log.file.usePlainText,
                                maxSize: Database.log.file.maxSize,
                         maxRotateCount: Database.log.file.maxRotateCount)
    }
    
    func writeOneKiloByteOfLog() {
        /// add a second delay to skip the filesystem flush
        Thread.sleep(forTimeInterval: 1.0)
        
        let message = "11223344556677889900" // 44Byte line
        for _ in 0..<20 { // 880Bytes
            Log.log(domain: .database, level: .error, message: "\(message)")
            Log.log(domain: .database, level: .warning, message: "\(message)")
            Log.log(domain: .database, level: .info, message: "\(message)")
            Log.log(domain: .database, level: .verbose, message: "\(message)")
            Log.log(domain: .database, level: .debug, message: "\(message)")
        }
        writeAllLogs("123456789") // 33 Bytes
        
        /// header section contains ~111 Bytes
        /// total of 111 + 880 + 33 = 1024
    }
    
    func writeAllLogs(_ message: String) {
        Log.log(domain: .database, level: .error, message: message)
        Log.log(domain: .database, level: .warning, message: message)
        Log.log(domain: .database, level: .info, message: message)
        Log.log(domain: .database, level: .verbose, message: message)
        Log.log(domain: .database, level: .debug, message: message)
    }
    
    func isKeywordPresentInAnyLog(_ keyword: String,
                                  path: String = Database.log.file.directory) throws -> Bool {
        for file in try getLogsInDirectory(path) {
            let contents = try String(contentsOf: file, encoding: .ascii)
            if contents.contains(keyword) {
                return true
            }
        }
        return false
    }
    
    func getLogsInDirectory(_ directory: String = Database.log.file.directory,
                            properties: [URLResourceKey] = [],
                            onlyInfoLogs: Bool = false) throws -> [URL] {
        guard let url = URL(string: directory) else {
            fatalError("valid directory should be provided")
        }
        
        let files = try FileManager.default.contentsOfDirectory(at: url,
                                                                includingPropertiesForKeys: properties,
                                                                options: .skipsSubdirectoryDescendants)
        return files.filter({ $0.pathExtension == "cbllog" &&
            (onlyInfoLogs ? $0.lastPathComponent.starts(with: "cbl_info_") : true) })
    }
    
    // MARK: TESTS
    
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
    
    func testDefaultLocation() throws {
        Log.log(domain: .database, level: .info, message: "TEST INFO")
        
        let files = try getLogsInDirectory()
        XCTAssert(files.count >= 5, "because there should be at least 5 log entries in the folder")
    }
    
    func testDefaultLogFormat() throws {
        Database.log.file.usePlainText = false
        Log.log(domain: .database, level: .info, message: "TEST INFO")
        
        let files = try getLogsInDirectory(properties: [.contentModificationDateKey],
                                           onlyInfoLogs: true)
        let sorted = files.sorted { (url1, url2) -> Bool in
            guard let date1 = try! url1
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
                else {
                    fatalError("modification date is missing for the URL")
            }
            guard let date2 = try! url2
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
                else {
                    fatalError("modification date is missing for the URL")
            }
            return date1.compare(date2) == .orderedAscending
        }
        
        guard let last = sorted.last else {
            fatalError("last item shouldn't be empty")
        }
        let handle = try FileHandle.init(forReadingFrom: last)
        let data = handle.readData(ofLength: 4)
        let bytes = [UInt8](data)
        XCTAssert(bytes[0] == 0xcf && bytes[1] == 0xb2 && bytes[2] == 0xab && bytes[3] == 0x1b,
                  "because the log should be in binary format");
    }
    
    func testPlainText() throws {
        Database.log.file.usePlainText = true
        let inputString = "SOME TEST INFO"
        Log.log(domain: .database, level: .info, message: inputString)
        
        let files = try getLogsInDirectory(properties: [.contentModificationDateKey],
                                           onlyInfoLogs: true)
        let sorted = files.sorted { (url1, url2) -> Bool in
            guard let date1 = try! url1
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
                else {
                    fatalError("modification date is missing for the URL")
            }
            guard let date2 = try! url2
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
                else {
                    fatalError("modification date is missing for the URL")
            }
            return date1.compare(date2) == .orderedAscending
        }
        
        guard let last = sorted.last else {
            fatalError("last item shouldn't be empty")
        }
        
        let contents = try String(contentsOf: last, encoding: .ascii)
        XCTAssert(contents.contains(contents))
    }
    
    func testMaxSize() throws {
        backupFileLogger()
        
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("LogTestLogs")
        try? FileManager.default.removeItem(atPath: path)
        
        Database.log.file.directory = path
        Database.log.file.usePlainText = true
        Database.log.file.maxSize = 1024
        Database.log.file.level = .debug
        
        writeOneKiloByteOfLog()
        /// after the 1KB of logs, closing of DB will write ~200Bytes.
        /// which will create an extra file
        
        var totalFilesInDirectory = (Database.log.file.maxRotateCount + 1) * 5
        
        #if !DEBUG
        totalFilesInDirectory = totalFilesInDirectory - 1
        #endif
        
        let totalLogFilesSaved = try getLogsInDirectory(path)
        XCTAssertEqual(totalLogFilesSaved.count, totalFilesInDirectory)
    }
    
    func testDisableLogging() throws {
        backupFileLogger()
        
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("LogTestLogs")
        try? FileManager.default.removeItem(atPath: path)
        
        Database.log.file.directory = path
        Database.log.file.usePlainText = true
        Database.log.file.level = .none
        
        let message = UUID().uuidString
        writeAllLogs(message)
        
        XCTAssertFalse(try isKeywordPresentInAnyLog(message, path: path))
    }
    
    func testReEnableLogging() throws {
        backupFileLogger()
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("LogTestLogs")
        try? FileManager.default.removeItem(atPath: path)
        Database.log.file.directory = path
        Database.log.file.usePlainText = true
        
        // DISABLE LOGGING
        Database.log.file.level = .none
        let message = UUID().uuidString
        writeAllLogs(message)
        
        XCTAssertFalse(try isKeywordPresentInAnyLog(message, path: path))
        
        // ENABLE LOGGING
        Database.log.file.level = .verbose
        writeAllLogs(message)
        
        for file in try getLogsInDirectory(path) {
            if file.lastPathComponent.starts(with: "cbl_debug_") {
                continue
            }
            let contents = try String(contentsOf: file, encoding: .ascii)
            XCTAssert(contents.contains(message))
        }
    }
    
    func testLogFilename() throws {
        let regex = "cbl_(debug|verbose|info|warning|error)_\\d+\\.cbllog"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        for file in try getLogsInDirectory() {
            XCTAssert(predicate.evaluate(with: file.lastPathComponent))
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
