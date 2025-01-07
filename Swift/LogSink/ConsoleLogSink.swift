//
//  ConsoleLogSink.swift
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

public struct ConsoleLogSink {
    
    /// The minimum log level of the log messages to be logged. The default log level for
    /// console logger is warning.
    public let level: LogLevel
    
    /// The set of log domains of the log messages to be logged. By default, the log
    /// messages of all domains will be logged.
    public let domain: LogDomains
    
    public init(level: LogLevel, domain: LogDomains = .all) {
        self.level = level
        self.domain = domain
    }
}
