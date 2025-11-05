//
//  LogSinkTest.swift
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

import XCTest
@testable import CouchbaseLiteSwift

class LogSinkTest: CBLTestCase {
    
    var logFileDirectory: String!
    
    var backupConsoleLogSink: ConsoleLogSink?
    
    var backupFileLogSink: FileLogSink?
    
    var backupCustomLogSink: CustomLogSink?
    
    override func setUp() {
        super.setUp()
        let folderName = "LogTestLogs_\(Int.random(in: 1...1000))"
        logFileDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(folderName)
        backupLoggerConfig()
    }
    
    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(atPath: logFileDirectory)
        restoreLoggerConfig()
    }
    
    func backupLoggerConfig() {
        backupConsoleLogSink = LogSinks.console
        backupFileLogSink = LogSinks.file
        backupCustomLogSink = LogSinks.custom
    }
    
    func restoreLoggerConfig() {
        LogSinks.console = backupConsoleLogSink
        LogSinks.file = backupFileLogSink
        LogSinks.custom = backupCustomLogSink
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
            Log._log(domain: .database, level: .error, message: "\(message)")
            Log._log(domain: .database, level: .warning, message: "\(message)")
            Log._log(domain: .database, level: .info, message: "\(message)")
            Log._log(domain: .database, level: .verbose, message: "\(message)")
            Log._log(domain: .database, level: .debug, message: "\(message)")
        }
        writeAllLogs("1") // ~25Bytes
    }
    
    func writeAllLogs(_ message: String) {
        Log._log(domain: .database, level: .error, message: message)
        Log._log(domain: .database, level: .warning, message: message)
        Log._log(domain: .database, level: .info, message: message)
        Log._log(domain: .database, level: .verbose, message: message)
        Log._log(domain: .database, level: .debug, message: message)
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
    
    func testDefaltLogSinks() throws {
        XCTAssertNotNil(LogSinks.console)
        XCTAssertEqual(LogSinks.console?.level, .warning)
        XCTAssertEqual(LogSinks.console?.domains, .all)
        XCTAssertNil(LogSinks.custom)
        XCTAssertNil(LogSinks.file)
    }
    
    func testFileLogSinkProperties() throws {
        var logSink = FileLogSink(level: .info, directory: logFileDirectory)
        XCTAssertEqual(logSink.level, .info)
        XCTAssertEqual(logSink.directory, logFileDirectory)
        XCTAssertFalse(logSink.usePlaintext)
        XCTAssertEqual(logSink.maxKeptFiles, FileLogSink.defaultMaxKeptFiles)
        XCTAssertEqual(logSink.maxFileSize, FileLogSink.defaultMaxSize)
        
        logSink = FileLogSink(level: .verbose, directory: logFileDirectory,
                              usePlainText: true, maxKeptFiles: 10, maxFileSize: 2048)
        XCTAssertEqual(logSink.level, .verbose)
        XCTAssertEqual(logSink.directory, logFileDirectory)
        XCTAssertTrue(logSink.usePlaintext)
        XCTAssertEqual(logSink.maxKeptFiles, 10)
        XCTAssertEqual(logSink.maxFileSize, 2048)
    }
    
    func testFileLogSinkLogLevels() throws {
        for i in (1...5).reversed() {
            let level = LogLevel(rawValue: UInt8(i))!
            LogSinks.file = FileLogSink(level: level, directory: logFileDirectory, usePlainText: true)
            Log._log(domain: .database, level: .verbose, message: "TEST VERBOSE")
            Log._log(domain: .database, level: .info, message: "TEST INFO")
            Log._log(domain: .database, level: .warning, message: "TEST WARNING")
            Log._log(domain: .database, level: .error, message: "TEST ERROR")
        }
        
        let files = try FileManager.default.contentsOfDirectory(atPath: logFileDirectory)
        for file in files {
            let log = (logFileDirectory as NSString).appendingPathComponent(file)
            let content = try NSString(contentsOfFile: log, encoding: String.Encoding.utf8.rawValue)
            
            var lineCount = 0
            content.enumerateLines { (line, stop) in
                lineCount = lineCount + 1
            }
            
            let sfile = file as NSString
            if sfile.range(of: "verbose").location != NSNotFound {
                XCTAssertEqual(lineCount, 3)
            } else if sfile.range(of: "info").location != NSNotFound {
                XCTAssertEqual(lineCount, 4)
            } else if sfile.range(of: "warning").location != NSNotFound {
                XCTAssertEqual(lineCount, 5)
            } else if sfile.range(of: "error").location != NSNotFound {
                XCTAssertEqual(lineCount, 6)
            }
        }
    }
    
    func testFileLogSinkBinaryFormat() throws {
        LogSinks.file = FileLogSink(level: .info, directory: logFileDirectory, usePlainText: false)
        
        Log._log(domain: .database, level: .info, message: "TEST INFO")
        
        let files = try getLogsInDirectory(logFileDirectory,
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
    
    func testFileLogSinkPlainTextFormat() throws {
        LogSinks.file = FileLogSink(level: .info, directory: logFileDirectory, usePlainText: true)
        
        let inputString = "SOME TEST INFO"
        Log._log(domain: .database, level: .info, message: inputString)
        
        let files = try getLogsInDirectory(logFileDirectory,
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
        XCTAssert(contents.contains(inputString))
    }

    func testFileLogSinkFilename() throws {
        LogSinks.file = FileLogSink(level: .debug, directory: logFileDirectory, usePlainText: true)
        let regex = "cbl_(debug|verbose|info|warning|error)_\\d+\\.cbllog"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        for file in try getLogsInDirectory(logFileDirectory) {
            XCTAssert(predicate.evaluate(with: file.lastPathComponent))
        }
    }
    
    func testFileLogSinkMaxSize() throws {
        LogSinks.file = FileLogSink(level: .debug,
                                    directory: logFileDirectory,
                                    usePlainText: true,
                                    maxKeptFiles: 3,
                                    maxFileSize: 1024)
        
        // This should create three files(per level) => 2KB logs + extra
        writeOneKiloByteOfLog()
        writeOneKiloByteOfLog()
        
        let totalFilesShouldBeInDirectory = LogSinks.file!.maxKeptFiles * 5
        let totalLogFilesSaved = try getLogsInDirectory(logFileDirectory)
        XCTAssertEqual(totalLogFilesSaved.count, Int(totalFilesShouldBeInDirectory))
    }
    
    func testDisableFileLogSink() throws {
        LogSinks.file = FileLogSink(level: .none,
                                    directory: logFileDirectory,
                                    usePlainText: true,
                                    maxKeptFiles: 3,
                                    maxFileSize: 1024)
        let message = UUID().uuidString
        writeAllLogs(message)
        XCTAssertFalse(try isKeywordPresentInAnyLog(message, path: logFileDirectory))
        
        LogSinks.file = nil
        writeAllLogs(message)
        XCTAssertFalse(try isKeywordPresentInAnyLog(message, path: logFileDirectory))
    }
    
    func testReEnableFileLogSink() throws {
        var count = 0
        let message = UUID().uuidString
        LogSinks.file = FileLogSink(level: .verbose,
                                    directory: logFileDirectory,
                                    usePlainText: true)
        writeAllLogs(message)
        
        // Disable file logging
        LogSinks.file = nil
        writeAllLogs(message)
        
        // Re-enable file logging
        LogSinks.file = FileLogSink(level: .verbose,
                                    directory: logFileDirectory,
                                    usePlainText: true)
        writeAllLogs(message)
        
        for file in try getLogsInDirectory(logFileDirectory) {
            let contents = try String(contentsOf: file, encoding: .ascii)
            if contents.contains(message) {
                count += 1
            }
        }
        
        XCTAssertEqual(count, 8)
    }
    
    func testLogFileHeader() throws {
        LogSinks.file = FileLogSink(level: .verbose,
                                    directory: logFileDirectory,
                                    usePlainText: true)
        
        writeOneKiloByteOfLog()
        for file in try getLogsInDirectory(logFileDirectory) {
            let contents = try String(contentsOf: file, encoding: .ascii)
            let lines = contents.components(separatedBy: "\n")
            
            // Check if the log file contains at least two lines
            guard lines.count >= 2 else {
                fatalError("log contents should have at least two lines: information and header section")
            }
            let secondLine = lines[1]

            XCTAssert(secondLine.contains("CouchbaseLite/"))
            XCTAssert(secondLine.contains("Build/"))
            XCTAssert(secondLine.contains("Commit/"))
        }
    }
    
    func testConsoleLogSinkProperties() throws {
        LogSinks.console = ConsoleLogSink(level: .verbose)
        XCTAssertEqual(LogSinks.console?.level, .verbose)
        XCTAssertEqual(LogSinks.console?.domains, .all)
        
        LogSinks.console = ConsoleLogSink(level: .info, domains: .replicator)
        XCTAssertEqual(LogSinks.console?.level, .info)
        XCTAssertEqual(LogSinks.console?.domains, .replicator)
    }
    
    func testCustomLogSinkProperties() throws {
        var logSink = TestCustomLogSink()
        LogSinks.custom = CustomLogSink(level: .verbose, logSink: logSink)
        XCTAssertEqual(LogSinks.custom?.level, .verbose)
        XCTAssert(LogSinks.custom?.logSink as? TestCustomLogSink === logSink)
        XCTAssertEqual(LogSinks.custom?.domains, .all)
        
        LogSinks.custom = CustomLogSink(level: .info, domains: .replicator, logSink: logSink)
        XCTAssertEqual(LogSinks.custom?.level, .info)
        XCTAssertEqual(LogSinks.custom?.domains, .replicator)
        XCTAssert(LogSinks.custom?.logSink as? TestCustomLogSink === logSink)
    }
    
    func testEnableDisableCustomLogSink() throws {
        var logSink = TestCustomLogSink()
        LogSinks.custom = CustomLogSink(level: .verbose, logSink: logSink)
        Log._log(domain: .database, level: .verbose, message: "TEST VERBOSE")
        Log._log(domain: .database, level: .info, message: "TEST INFO")
        Log._log(domain: .database, level: .warning, message: "TEST WARNING")
        Log._log(domain: .database, level: .error, message: "TEST ERROR")
        XCTAssertEqual(logSink.lines.count, 4)
        
        logSink = TestCustomLogSink()
        LogSinks.custom = CustomLogSink(level: .none, logSink: logSink)
        Log._log(domain: .database, level: .verbose, message: "TEST VERBOSE")
        Log._log(domain: .database, level: .info, message: "TEST INFO")
        Log._log(domain: .database, level: .warning, message: "TEST WARNING")
        Log._log(domain: .database, level: .error, message: "TEST ERROR")
        XCTAssertEqual(logSink.lines.count, 0)
    }
    
    func testCustomLogSinkLevels() throws {
        Log._log(domain: .database, level: .info, message: "IGNORE")
        for i in (1...5).reversed() {
            let level = LogLevel(rawValue: UInt8(i))!
            let logSink = TestCustomLogSink()
            LogSinks.custom = CustomLogSink(level: level, logSink: logSink)
            Log._log(domain: .database, level: .verbose, message: "TEST VERBOSE")
            Log._log(domain: .database, level: .info, message: "TEST INFO")
            Log._log(domain: .database, level: .warning, message: "TEST WARNING")
            Log._log(domain: .database, level: .error, message: "TEST ERROR")
            XCTAssertEqual(logSink.lines.count, 5 - i)
        }
    }
    
    func testCustomLogSinkDomains() throws {
        let domains: [LogDomains] = [.database, .query, .replicator, .network]
        let names = ["database", "query", "replicator", "network"]
        
        // Single Domain
        for i in 0..<domains.count {
            let logSink = TestCustomLogSink()
            LogSinks.custom = CustomLogSink(level: .debug, domains: domains[i], logSink: logSink)
            for j in 0..<domains.count {
<<<<<<< Updated upstream
                Log.log(domain: LogDomain(rawValue: domains[j].rawValue)!, level: .verbose, message: names[j])
=======
<<<<<<< Updated upstream
                Log.log(domain: LogDomain(rawValue: UInt(domains[j].rawValue))!, level: .verbose, message: names[j])
=======
                Log._log(domain: LogDomain(rawValue: domains[j].rawValue)!, level: .verbose, message: names[j])
>>>>>>> Stashed changes
>>>>>>> Stashed changes
            }
            XCTAssertEqual(logSink.lines.count, 1)
            XCTAssertEqual(logSink.lines[0], names[i])
        }
        
        // Domain Combination:
        for i in 0..<domains.count {
            var combined: LogDomains = []
            for j in 0...i {
                combined.insert(domains[j])
            }
            
            let logSink = TestCustomLogSink()
            LogSinks.custom = CustomLogSink(level: .debug, domains: combined, logSink: logSink)
            for j in 0..<domains.count {
<<<<<<< Updated upstream
                Log.log(domain: LogDomain(rawValue: domains[j].rawValue)!, level: .verbose, message: names[j])
=======
<<<<<<< Updated upstream
                Log.log(domain: LogDomain(rawValue: UInt(domains[j].rawValue))!, level: .verbose, message: names[j])
=======
                Log._log(domain: LogDomain(rawValue: domains[j].rawValue)!, level: .verbose, message: names[j])
>>>>>>> Stashed changes
>>>>>>> Stashed changes
            }
            
            XCTAssertEqual(logSink.lines.count, i + 1)
            for j in 0...i {
                XCTAssertEqual(logSink.lines[j], names[j])
            }
        }
        
        // All Domain
        let logSink = TestCustomLogSink()
        LogSinks.custom = CustomLogSink(level: .debug, domains: .all, logSink: logSink)
        for i in 0..<domains.count {
<<<<<<< Updated upstream
            Log.log(domain: LogDomain(rawValue: domains[i].rawValue)!, level: .verbose, message: names[i])
=======
<<<<<<< Updated upstream
            Log.log(domain: LogDomain(rawValue: UInt(domains[i].rawValue))!, level: .verbose, message: names[i])
=======
            Log._log(domain: LogDomain(rawValue: domains[i].rawValue)!, level: .verbose, message: names[i])
>>>>>>> Stashed changes
>>>>>>> Stashed changes
        }
        XCTAssertEqual(logSink.lines.count, names.count)
        for i in 0..<names.count {
            XCTAssertEqual(logSink.lines[i], names[i])
        }
    }
    
    func testPercentEscape() throws {
        let logSink = TestCustomLogSink()
        LogSinks.custom = CustomLogSink(level: .info, logSink: logSink)
        Log._log(domain: .database, level: .info, message: "Hello %s there")
        var found: Bool = false
        for line in logSink.lines {
            if line.contains("Hello %s there") {
                found = true
            }
        }
        XCTAssert(found)
    }
}
