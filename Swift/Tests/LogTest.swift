//
//  LogTest.swift
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

import XCTest
@testable import CouchbaseLiteSwift


class LogTest: CBLTestCase {
    
    static let logFileDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent("LogTestLogs")
    
    var backup: FileLoggerBackup?
    
    override func setUp() {
        super.setUp()
        
        backupFileLogger()
        try? FileManager.default.removeItem(atPath: LogTest.logFileDirectory)
    }
    
    override func tearDown() {
        super.tearDown()
        
        if let backup = self.backup {
            Database.log.file.config = backup.config
            Database.log.file.level = backup.level
            self.backup = nil
        }
    }
    
    func logFileConfig() -> LogFileConfiguration {
        return LogFileConfiguration(directory: LogTest.logFileDirectory)
    }
    
    func backupFileLogger() {
        backup = FileLoggerBackup(config: Database.log.file.config,
                                  level: Database.log.file.level)
    }
    
    func getLogsInDirectory(_ directory: String,
                            properties: [URLResourceKey] = [],
                            onlyInfoLogs: Bool = false) throws -> [URL]
    {
        let url = URL(fileURLWithPath: directory)
        let files = try FileManager.default.contentsOfDirectory(at: url,
                                                                includingPropertiesForKeys: properties,
                                                                options: .skipsSubdirectoryDescendants)
        return files.filter({ $0.pathExtension == "cbllog" &&
            (onlyInfoLogs ? $0.lastPathComponent.starts(with: "cbl_info_") : true) })
    }
    
    func writeOneKiloByteOfLog() {
        let message = "11223344556677889900" // 44Byte line
        for _ in 0..<23 { // 1012 Bytes
            Log.log(domain: .database, level: .error, message: "\(message)")
            Log.log(domain: .database, level: .warning, message: "\(message)")
            Log.log(domain: .database, level: .info, message: "\(message)")
            Log.log(domain: .database, level: .verbose, message: "\(message)")
            Log.log(domain: .database, level: .debug, message: "\(message)")
        }
        writeAllLogs("1") // ~25Bytes
    }
    
    func writeAllLogs(_ message: String) {
        Log.log(domain: .database, level: .error, message: message)
        Log.log(domain: .database, level: .warning, message: message)
        Log.log(domain: .database, level: .info, message: message)
        Log.log(domain: .database, level: .verbose, message: message)
        Log.log(domain: .database, level: .debug, message: message)
    }
    
    func isKeywordPresentInAnyLog(_ keyword: String, path: String) throws -> Bool {
        for file in try getLogsInDirectory(path) {
            let contents = try String(contentsOf: file, encoding: .ascii)
            if contents.contains(keyword) {
                return true
            }
        }
        return false
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
    
    func testFileLoggingLevels() throws {
        let config = self.logFileConfig()
        config.usePlainText = true
        Database.log.file.config = config
        
        for i in (1...5).reversed() {
            Database.log.file.level = LogLevel(rawValue: UInt8(i))!
            Log.log(domain: .database, level: .verbose, message: "TEST VERBOSE")
            Log.log(domain: .database, level: .info, message: "TEST INFO")
            Log.log(domain: .database, level: .warning, message: "TEST WARNING")
            Log.log(domain: .database, level: .error, message: "TEST ERROR")
        }
        
        let files = try FileManager.default.contentsOfDirectory(atPath: config.directory)
        for file in files {
            let log = (config.directory as NSString).appendingPathComponent(file)
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
    
    
    func testFileLoggingDefaultBinaryFormat() throws {
        let config = self.logFileConfig()
        Database.log.file.config = config
        Database.log.file.level = .info
        Log.log(domain: .database, level: .info, message: "TEST INFO")
        
        let files = try getLogsInDirectory(config.directory,
                                           properties: [.contentModificationDateKey],
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
    
    func testFileLoggingUsePlainText() throws {
        let config = self.logFileConfig()
        config.usePlainText = true
        Database.log.file.config = config
        Database.log.file.level = .info
        
        let inputString = "SOME TEST INFO"
        Log.log(domain: .database, level: .info, message: inputString)
        
        let files = try getLogsInDirectory(config.directory,
                                           properties: [.contentModificationDateKey],
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

    func testFileLoggingLogFilename() throws {
        let config = self.logFileConfig()
        Database.log.file.config = config
        Database.log.file.level = .debug
        let regex = "cbl_(debug|verbose|info|warning|error)_\\d+\\.cbllog"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        for file in try getLogsInDirectory(config.directory) {
            XCTAssert(predicate.evaluate(with: file.lastPathComponent))
        }
    }
    
    func testEnableAndDisableCustomLogging() throws {
        Log.log(domain: .database, level: .info, message: "IGNORE")
        let customLogger = LogTestLogger()
        Database.log.custom = customLogger
        
        customLogger.level = .none
        Database.log.custom = customLogger
        Log.log(domain: .database, level: .verbose, message: "TEST VERBOSE")
        Log.log(domain: .database, level: .info, message: "TEST INFO")
        Log.log(domain: .database, level: .warning, message: "TEST WARNING")
        Log.log(domain: .database, level: .error, message: "TEST ERROR")
        XCTAssertEqual(customLogger.lines.count, 0)
        
        customLogger.level = .verbose
        Database.log.custom = customLogger
        Log.log(domain: .database, level: .verbose, message: "TEST VERBOSE")
        Log.log(domain: .database, level: .info, message: "TEST INFO")
        Log.log(domain: .database, level: .warning, message: "TEST WARNING")
        Log.log(domain: .database, level: .error, message: "TEST ERROR")
        XCTAssertEqual(customLogger.lines.count, 4)
    }
    
    func testFileLoggingMaxSize() throws {
        let config = self.logFileConfig()
        config.usePlainText = true
        config.maxSize = 1024
        Database.log.file.config = config
        Database.log.file.level = .debug
        
        // this should create two files, as the 1KB logs + extra ~400Bytes
        writeOneKiloByteOfLog()
        
        guard let maxRotateCount = Database.log.file.config?.maxRotateCount else {
            fatalError("Config should be present!!")
        }
        var totalFilesShouldBeInDirectory = (maxRotateCount + 1) * 5
        
        #if !DEBUG
        totalFilesShouldBeInDirectory = totalFilesShouldBeInDirectory - 1
        #endif
        
        let totalLogFilesSaved = try getLogsInDirectory(config.directory)
        XCTAssertEqual(totalLogFilesSaved.count, totalFilesShouldBeInDirectory)
    }
    
    func testFileLoggingDisableLogging() throws {
        let config = self.logFileConfig()
        config.usePlainText = true
        Database.log.file.config = config
        Database.log.file.level = .none
        
        let message = UUID().uuidString
        writeAllLogs(message)
        
        XCTAssertFalse(try isKeywordPresentInAnyLog(message, path: config.directory))
    }
    
    func testFileLoggingReEnableLogging() throws {
        let config = self.logFileConfig()
        config.usePlainText = true
        Database.log.file.config = config
        
        // DISABLE LOGGING
        Database.log.file.level = .none
        let message = UUID().uuidString
        writeAllLogs(message)
        
        XCTAssertFalse(try isKeywordPresentInAnyLog(message, path: config.directory))
        
        // ENABLE LOGGING
        Database.log.file.level = .verbose
        writeAllLogs(message)
        
        for file in try getLogsInDirectory(config.directory) {
            if file.lastPathComponent.starts(with: "cbl_debug_") {
                continue
            }
            let contents = try String(contentsOf: file, encoding: .ascii)
            XCTAssert(contents.contains(message))
        }
    }
    
    func testFileLoggingHeader() throws {
        let config = self.logFileConfig()
        config.usePlainText = true
        Database.log.file.config = config
        Database.log.file.level = .verbose
        
        writeOneKiloByteOfLog()
        for file in try getLogsInDirectory(config.directory) {
            let contents = try String(contentsOf: file, encoding: .ascii)
            guard let firstLine = contents.components(separatedBy: "\n").first else {
                fatalError("log contents should be empty and needs header section")
            }
            XCTAssert(firstLine.contains("CouchbaseLite/"))
            XCTAssert(firstLine.contains("Build/"))
            XCTAssert(firstLine.contains("Commit/"))
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
    
    var config: LogFileConfiguration?
    
    var level: LogLevel
    
}
