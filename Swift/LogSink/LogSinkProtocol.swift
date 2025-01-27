//
//  LogSinkProtocol.swift
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// Log domain.
///
/// all:        All log domains.
/// database:   Database domain.
/// query:      Query domain.
/// replicator: Replicator domain.
/// network:    Network domain.
/// listener:   Listener domain.
///
public struct LogDomains: OptionSet {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    // Individual domains
    public static let database   = LogDomains(rawValue: 1 << 0)
    public static let query      = LogDomains(rawValue: 1 << 1)
    public static let replicator = LogDomains(rawValue: 1 << 2)
    public static let network    = LogDomains(rawValue: 1 << 3)

    #if COUCHBASE_ENTERPRISE
    public static let listener   = LogDomains(rawValue: 1 << 4)
    public static let all: LogDomains = [.database, .query, .replicator, .network, .listener]
    #else
    public static let all: LogDomains = [.database, .query, .replicator, .network]
    #endif
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

/// Logger protocol
public protocol LogSinkProtocol {
    
    /// The minimum log level to be logged.
    var level: LogLevel { get }
    
    /// The callback log function.
    func log(level: LogLevel, domain: LogDomains, message: String)
    
}
