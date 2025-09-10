//
//  TestCustomLogSink.swift
//  CouchbaseLite
//
//  Created by Vlad Velicu on 10/09/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

import CouchbaseLiteSwift

class TestCustomLogSink: LogSinkProtocol {
    var lines: [String] = []
    
    var level: LogLevel = .none
    
    func writeLog(level: LogLevel, domain: LogDomain, message: String) {
        lines.append(message)
    }

    func reset() {
        lines.removeAll()
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
