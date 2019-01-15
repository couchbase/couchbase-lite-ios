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

/// File logger used for writing log messages to files. The binary file format will
/// be used by default. To change the file format to plain text, set the usePlainText
/// property to true.
public class FileLogger {
    
    private static let defaultMaxSize = UInt64(500 * 1024)
    
    /// The minimum log level of the log messages to be logged. The default log level for
    /// file logger is warning.
    public var level: LogLevel = .info {
        didSet {
            CBLDatabase.log().file.level = CBLLogLevel(rawValue: UInt(level.rawValue))!
        }
    }
    
    /// The directory to store the log files.
    public var directory: String = CBLDatabase.log().file.directory {
        didSet {
            CBLDatabase.log().file.directory = directory
        }
    }
    
    /// To use plain text file format instead of the default binary format.
    public var usePlainText: Bool = false {
        didSet {
            CBLDatabase.log().file.usePlainText = usePlainText
        }
    }
    
    /// The maximum size of a log file before being rotation. The default is 1024 bytes.
    public var maxSize: UInt64 = defaultMaxSize {
        didSet {
            CBLDatabase.log().file.maxSize = maxSize
        }
    }
    
    /// The maximum number of rotated log files to keep. The default is 1 which means no rotation.
    public var maxRotateCount: Int = 1 {
        didSet(value) {
            CBLDatabase.log().file.maxRotateCount = value
        }
    }
    
    init() { }
}
