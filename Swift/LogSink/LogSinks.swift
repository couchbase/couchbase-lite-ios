//
//  LogSinks.swift
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
import CouchbaseLiteSwift_Private
import CouchbaseLite

public class LogSinks {
    
    /// The console log sink instance.
    /// - Note: Enabled with warning level by default
    public static var console: ConsoleLogSink? = .init(level: .warning) {
        didSet {
            CBLLogSinks.console = CBLConsoleLogSink(level: CBLLogLevel(rawValue: UInt((self.console!.level.rawValue)))!,
                                                    domain: CBLLogDomain(rawValue: UInt((self.console!.domain.rawValue))))
        }
    }
    /// The file log sink instance.
    /// - Note: Disabled by default
    public static var file: FileLogSink? = nil {
        didSet {
            CBLLogSinks.file = CBLFileLogSink(level: CBLLogLevel(rawValue: UInt((self.file!.level.rawValue)))!,
                                              directory: self.file!.directory,
                                              usePlaintext: self.file!.usePlaintext,
                                              maxKeptFiles: self.file!.maxKeptFiles,
                                              maxFileSize: self.file!.maxFileSize)
        }
    }
    
    /// The custom log sink instance.
    /// - Note: Disabled by default
    public static var custom: CustomLogSink? = nil {
        didSet {
            CBLLogSinks.custom = CBLCustomLogSink(level: CBLLogLevel(rawValue: UInt((self.custom!.level.rawValue)))!,
                                                  logSink: self.custom!.logSink as! CBLLogSinkProtocol)
        }
    }

}
