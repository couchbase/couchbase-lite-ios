//
//  CustomLogSink.swift
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

import Foundation

/// Protocol for custom log sinks to handle log messages.
public protocol LogSinkProtocol {
    /// Writes a log message with the given level, domain, and content.
    func writeLog(level: LogLevel, domain: LogDomain, message: String)
}

/// A log sink that writes log messages to a custom log sink implementation.
public struct CustomLogSink {
    /// The minimum log level to be logged.
    public let level: LogLevel
    
    /// The set of log domains of the log messages to be logged.
    public let domains: LogDomains
    
    /// The custom log sink implementation.
    public let logSink: LogSinkProtocol
    
    /// Initializes a ConsoleLogSink with the specified log level and the custom log sink implementation.
    /// The default log domain is set to all domains.
    public init(level: LogLevel, logSink: LogSinkProtocol) {
        self.init(level: level, domains: .all, logSink: logSink)
    }
    
    /// Initializes a ConsoleLogSink with the specified log level, log domains, and the custom log sink implementation.
    public init(level: LogLevel, domains: LogDomains, logSink: LogSinkProtocol) {
        self.level = level
        self.logSink = logSink
        self.domains = domains
    }
}
