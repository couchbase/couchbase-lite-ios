//
//  FileLogSink.swift
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

/// A log sink that writes log messages to files.
public struct FileLogSink {
    /// The minimum log level of the log messages to be logged.
    public let level: LogLevel
    
    /// The directory where the log files will be stored.
    public let directory: String
    
    /// To use plain text file format instead of the default binary format.
    /// The default is ``defaultUsePlaintext``
    public let usePlaintext: Bool
    
    /// The max number of rotated log files to keep.
    /// The default value is ``defaultMaxSize``
    public let maxFileSize: UInt64
    
    /// The maximum size of a log file before being rotated in bytes.
    /// The default is ``defaultMaxKeptFiles``
    public let maxKeptFiles: Int
    
    /// Initializes a FileLogSink with the specified log level, directory, and optional parameters.
    ///
    /// - Parameters:
    ///   - level: The minimum log level for messages to be logged.
    ///   - directory: The directory where the log files will be stored.
    ///   - usePlainText: An optional flag indicating whether to use plain text format for the log files. Default is using the binary format.
    ///   - maxKeptFiles: An optional maximum number of rotated log files to keep. Default is `defaultMaxKeptFiles`.
    ///   - maxFileSize: An optional maximum size of a log file before being rotated in bytes. Default is `defaultMaxSize`.
    public init(level: LogLevel, directory: String, usePlainText: Bool = defaultUsePlaintext,
                maxKeptFiles: Int = defaultMaxKeptFiles, maxFileSize: UInt64 = defaultMaxSize) {
        self.level = level
        self.directory = directory
        self.usePlaintext = usePlainText
        self.maxKeptFiles = maxKeptFiles
        self.maxFileSize = maxFileSize
    }
}
