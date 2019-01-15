//
//  ConsoleLogger.swift
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

import Foundation

/// Console logger for writing log messages to the system console.
public class ConsoleLogger {
    
    /// The minimum log level of the log messages to be logged. The default log level for
    /// console logger is warning.
    public var level: LogLevel = .warning {
        didSet {
            CBLDatabase.log().console.level = CBLLogLevel(rawValue: UInt(level.rawValue))!
        }
    }
    
    /// The set of log domains of the log messages to be logged. By default, the log
    /// messages of all domains will be logged.
    public var domains: Set<LogDomain> = [.all] {
        didSet {
            var domain: UInt8 = 0
            for d in domains {
                domain = domain | d.rawValue
            }
            CBLDatabase.log().console.domains = CBLLogDomain(rawValue: UInt(domain))
        }
    }
    
    // MARK: Internal
    
    init() { }
}
