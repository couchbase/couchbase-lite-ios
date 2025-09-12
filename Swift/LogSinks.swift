//
//  LogSinks.swift
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
import CouchbaseLiteSwift_Private

/// Log domain.
///
/// database:   Database domain.
/// query:      Query domain.
/// replicator: Replicator domain.
/// network:    Network domain.
/// listener:   Listener domain.
public enum LogDomain: UInt8 {
    case database       = 1
    case query          = 2
    case replicator     = 4
    case network        = 8
    case listener       = 16
    case peerDiscovery  = 32
    case multipeer      = 64
}

/// Log level.
///
/// - Debug:   Debug log messages. Only present in debug builds of CouchbaseLite.
/// - verbose: Verbose log messages.
/// - info:    Informational log messages.
/// - warning: Warning log messages.
/// - error:   Error log messages. These indicate immediate errors that need to be addressed.
/// - none:    Disabling log messages of a given log domain.
public enum LogLevel: UInt8 {
    case debug = 0
    case verbose
    case info
    case warning
    case error
    case none
}

/// A static container for managing the three log sinks used by Couchbase Lite.
public class LogSinks {
    /// The console log sink, enabled by default with a warning level.
    public static var console: ConsoleLogSink? = .init(level: .warning) {
        didSet {
            if let console = self.console {
                let level = CBLLogLevel(rawValue: UInt(console.level.rawValue))!
                let domains = CBLLogDomain(rawValue: UInt(console.domains.rawValue))
                CBLLogSinks.console = CBLConsoleLogSink(level: level, domains: domains)
            } else {
                CBLLogSinks.console = nil
            }
        }
    }
    
    /// The file log sink, disabled by default.
    public static var file: FileLogSink? = nil {
        didSet {
            if let file = self.file {
                let level = CBLLogLevel(rawValue: UInt(file.level.rawValue))!
                CBLLogSinks.file = CBLFileLogSink(level: level,
                                                  directory: file.directory,
                                                  usePlaintext: file.usePlaintext,
                                                  maxKeptFiles: Int(file.maxKeptFiles),
                                                  maxFileSize: UInt(file.maxFileSize))
            } else {
                CBLLogSinks.file = nil
            }
        }
    }
    
    /// The custom log sink, disabled by default.
    public static var custom: CustomLogSink? = nil {
        didSet {
            if let custom = self.custom {
                let level = CBLLogLevel(rawValue: UInt(custom.level.rawValue))!
                let domains = CBLLogDomain(rawValue: UInt(custom.domains.rawValue))
                let logSink = CustomLogSinkBridge(logSink: custom.logSink)
                CBLLogSinks.custom = CBLCustomLogSink(level: level, domains: domains, logSink: logSink)
            } else {
                CBLLogSinks.custom = nil
            }
        }
    }
    
    /// For bridging between swift and objective custom log sink.
    private class CustomLogSinkBridge : NSObject, CBLLogSinkProtocol {
        let logSink: LogSinkProtocol
        
        init(logSink: LogSinkProtocol) {
            self.logSink = logSink
        }
        
        func writeLog(with level: CBLLogLevel, domain: CBLLogDomain, message: String) {
            let logLevel = LogLevel.init(rawValue: UInt8(level.rawValue))!
            let logDomain = LogDomain.init(rawValue: UInt8(domain.rawValue))!
            logSink.writeLog(level:logLevel, domain: logDomain, message: message)
        }
    }
}
