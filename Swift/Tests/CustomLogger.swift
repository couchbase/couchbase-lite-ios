//
//  CustomLogger.swift
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
import CouchbaseLiteSwift

class CustomLogger: LogSinkProtocol {
    
    var lines: [String] = []
    
    var level: LogLevel = .none
    
    func reset() {
        lines.removeAll()
    }
    
    func log(level: LogLevel, domain: LogDomains, message: String) {
        lines.append(message)
    }
    
    func containsString(_ string: String) -> Bool {
        for line in lines {
            if (line as NSString).contains(string) {
                return true
            }
        }
        return false
    }
    
}
