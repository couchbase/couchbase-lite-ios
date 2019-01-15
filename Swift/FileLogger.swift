//
//  FileLogger.swift
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

/// File logger used for writing log messages to files. To enable the file logger,
/// setup the log file configuration and specify the log level as desired.
public class FileLogger {
    
    /// The log file configuration for configuring the log directory, file format, and rotation
    /// policy. The config property is nil by default. Setting the config property to nil will
    /// disable the file logging.
    public var config: LogFileConfiguration? {
        didSet {
            CBLDatabase.log().file.config = config?.toImpl()
        }
    }
    
    /// The minimum log level of the log messages to be logged. The default log level for
    /// file logger is none which means no logging.
    public var level: LogLevel = .none {
        didSet {
            CBLDatabase.log().file.level = CBLLogLevel(rawValue: UInt(level.rawValue))!
        }
    }
    
    // MARK: Internal
    
    init() { }
}
