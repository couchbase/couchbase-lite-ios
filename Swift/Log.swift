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
import CouchbaseLiteSwift_Private

/// Log allows to configure console and file logger or to set a custom logger.
public class Log {
    
    /// Console logger writing log messages to the system console.
    @available(*, deprecated, message: "Use LogSinks.console instead.")
    public let console = ConsoleLogger()
    
    /// File logger writing log messages to files.
    @available(*, deprecated, message: "Use LogSinks.file instead.")
    public let file = FileLogger()
    
    /// For setting a custom logger. Changing the log level of the assigned custom logger will
    /// require the custom logger to be reassigned so that the change can be affected.
    @available(*, deprecated, message: "Use LogSinks.custom instead.")
    public var custom: Logger? {
        didSet {
            if let logger = custom {
                let logLevel = CBLLogLevel(rawValue: UInt(logger.level.rawValue))!
                CBLDatabase.log().setCustomLoggerWith(logLevel) { (level, domain, message) in
                    let l = LogLevel(rawValue: UInt8(level.rawValue))!
                    let d = LogDomain(rawValue: domain.rawValue)!
                    logger.log(level: l, domain: d, message: message)
                }
            } else {
                CBLDatabase.log().custom = nil
            }
        }
    }
    
    // MARK: Internal
    
    init() { }
    
    /// Writes a log message to all the enabled log sinks.
    /// - Note: `Unsupported API` Internal used for testing purpose.
    static func log(domain: LogDomain, level: LogLevel, message: String) {
        let cDomain = CBLLogDomain.init(rawValue: UInt(domain.rawValue))
        let cLevel = CBLLogLevel(rawValue: UInt(level.rawValue))!
        CBLDatabase.log().log(to: cDomain, level: cLevel, message: message)
    }
    
}
