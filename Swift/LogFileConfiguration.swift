//
//  LogFileConfiguration.swift
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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

/// Log file configuration.
public class LogFileConfiguration {
    
    /// The directory to store the log files.
    public let directory: String
    
    /// To use plain text file format instead of the default binary format.
    public var usePlainText: Bool = false  {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// The maximum size of a log file before being rotated in bytes. The default is 500 Kilobytes.
    public var maxSize: UInt64 = defaultMaxSize {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// The Max number of rotated log files to keep. The default value is 1 which means
    /// one backup for a total of 2 log files.
    public var maxRotateCount: Int = 1 {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// Initializes with a directory to store the log files.
    public init(directory: String) {
        self.directory = directory
        self.readonly = false
    }
    
    // MARK: Internal
    
    private static let defaultMaxSize = UInt64(500 * 1024)
    
    private let readonly: Bool
    
    init(config: LogFileConfiguration, readonly: Bool) {
        self.readonly = readonly
        self.directory = config.directory
        self.usePlainText = config.usePlainText
        self.maxSize = config.maxSize
        self.maxRotateCount = config.maxRotateCount
    }
    
    func checkReadOnly() {
        if self.readonly {
            fatalError("This configuration object is readonly.")
        }
    }
    
    func toImpl() -> CBLLogFileConfiguration {
        let config = CBLLogFileConfiguration(directory: self.directory)
        config.usePlainText = self.usePlainText
        config.maxSize = self.maxSize
        config.maxRotateCount = self.maxRotateCount
        return config
    }
    
}
