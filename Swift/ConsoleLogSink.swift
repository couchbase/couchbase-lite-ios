//
//  ConsoleLogSink.swift
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

/// Log domain options that can be enabled in the console logger.
public struct LogDomains: OptionSet {
    
    /// Raw value.
    public let rawValue: Int
    
    /// Constructor with the raw value.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// Database domain.
    public static let database = LogDomains(rawValue: Int(LogDomain.database.rawValue))
    
    /// Query domain.
    public static let query = LogDomains(rawValue: Int(LogDomain.query.rawValue))
    
    /// Replicator domain.
    public static let replicator = LogDomains(rawValue: Int(LogDomain.replicator.rawValue))
    
    /// Network domain.
    public static let network = LogDomains(rawValue: Int(LogDomain.network.rawValue))
    
    /// Listener domain.
    public static let listener = LogDomains(rawValue: Int(LogDomain.listener.rawValue))
    
    /// Peer Discovery domain.
    public static let peerDiscovery = LogDomains(rawValue: Int(LogDomain.peerDiscovery.rawValue))
    
    /// Multipeer Replication domain.
    public static let multipeer = LogDomains(rawValue: Int(LogDomain.multipeer.rawValue))
    
    /// All domains.
    public static let all: LogDomains = [
        .database, .query, .replicator, .network, .listener, .peerDiscovery, .multipeer
    ]
}

/// A log sink that writes log messages to the console.
public struct ConsoleLogSink {
    /// The minimum log level of the log messages to be logged.
    public let level: LogLevel
    
    /// The set of log domains of the log messages to be logged.
    public let domains: LogDomains
    
    /// Initializes a ConsoleLogSink with the specified log level and optional log domains.
    public init(level: LogLevel, domains: LogDomains = .all) {
        self.level = level
        self.domains = domains
    }
}
