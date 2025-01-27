//
//  FileLogSink.swift
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

public struct FileLogSink {
    
    /// The minimum log level of the log messages to be logged. The default log level for
    /// file logger is kCBLLogLevelNone which means no logging.
    public let level: LogLevel
    
    /// The directory to store the log files.
    public let directory: String
    
    /// To use plain text file format instead of the default binary format.
    /// The default is ``defaultUsePlaintext``
    public let usePlaintext: Bool
    
    /// The maximum size of a log file before being rotated in bytes.
    /// The default is ``defaultMaxKeptFiles``
    public let maxKeptFiles: Int
    
    /// The max number of rotated log files to keep.
    /// The default value is ``defaultMaxSize``
    public let maxFileSize: UInt
    
    public init(level: LogLevel, directory: String, usePlainText: Bool = defaultUsePlaintext, maxKeptFiles: Int = defaultMaxKeptFiles, maxFileSize: UInt = defaultMaxSize) {
        self.level = level
        self.directory = directory
        self.usePlaintext = usePlainText
        self.maxKeptFiles = maxKeptFiles
        self.maxFileSize = maxFileSize
    }
}
