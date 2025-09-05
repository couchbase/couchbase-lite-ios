//
//  Logger.swift
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
public enum LogDomain: UInt {
    /// Database domain.
    case database       = 1
    
    /// Query domain.
    case query          = 2
    
    /// Replicator domain.
    case replicator     = 4
    
    /// Network domain.
    case network        = 8
    
    /// Listener domain.
    case listener       = 16
    
    /// Peer Discovery domain.
    case peerDiscovery  = 32
    
    /// mDNS specific logs used for DNS-SD peer discovery
    case mdns           = 64
    
    /// Multipeer Replication domain
    case multipeer      = 512
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
public protocol Logger {
    
    /// The minimum log level to be logged.
    var level: LogLevel { get }
    
    /// The callback log function.
    func log(level: LogLevel, domain: LogDomain, message: String)
    
}
