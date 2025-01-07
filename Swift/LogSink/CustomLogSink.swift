//
//  CustomLogSink.swift
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

public struct CustomLogSink {
    
    /// The minimum log level to be logged..
    public let level: LogLevel
    
    /// The callback log function.
    public let logSink: LogSinkProtocol
    
    public init(level: LogLevel, logSink: LogSinkProtocol) {
        self.level = level
        self.logSink = logSink
    }
}
