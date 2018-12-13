//
//  Log.swift
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

import Foundation

/// Log allows to configure console and file logger or to set a custom logger.
public class Log {
    
    /// Console logger writing log messages to the system console.
    public let console = ConsoleLogger()
    
    /// File logger writing log messages to files.
    public let file = FileLogger()
    
    /// For setting a custom logger.
    public var custom: Logger? {
        didSet {
            CBLDatabase.log().custom = custom != nil ? CustomLoggerBridge(logger: custom!) : nil
        }
    }
    
    // MARK: Internal
    
    init() { }
    
    // For Unit Tests
    
    static func log(domain: LogDomain, level: LogLevel, message: String) {
        let cDomain = CBLLogDomain.init(rawValue: UInt(domain.rawValue))
        let cLevel = CBLLogLevel(rawValue: UInt(level.rawValue))!
        CBLDatabase.log().log(to: cDomain, level: cLevel, message: message)
    }
}

/// Briging between Swift and Objective-C custom logger
class CustomLoggerBridge: NSObject, CBLLogger {
    
    let logger: Logger
    
    init(logger: Logger) {
        self.logger = logger
    }
    
    // MARK: CBLLogger
    
    var level: CBLLogLevel {
        return CBLLogLevel(rawValue: UInt(logger.level.rawValue))!
    }
    
    func log(with level: CBLLogLevel, domain: CBLLogDomain, message: String) {
        let l = LogLevel(rawValue: UInt8(level.rawValue))!
        let d = LogDomain(rawValue: UInt8(domain.rawValue))!
        logger.log(level: l, domain: d, message: message)
    }
    
}
