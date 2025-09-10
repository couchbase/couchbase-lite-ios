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

/// Log allows to configure console and file logger or to set a custom logger.
public class Log {
    
    // MARK: Internal
    
    init() { }
    
    // For Unit Tests
    
    static func log(domain: LogDomain, level: LogLevel, message: String) {
        LogSinks.custom?.logSink.writeLog(level: level, domain: domain, message: message)
    }
    
}
