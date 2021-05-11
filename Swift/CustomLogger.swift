//
//  CustomLogger.swift
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 4/26/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

import Foundation

public class CustomLogger {
    
    /// The minimum log level of the log messages to be logged. The default log level for
    /// console logger is warning.
    private(set) var level: LogLevel = .warning
    
    /// The set of log domains of the log messages to be logged. By default, the log
    /// messages of all domains will be logged.
    private(set) var domains: LogDomains = .all
    
    public init(level: LogLevel, domains: LogDomains) {
        self.level = level
        self.domains = domains
    }
    
    public convenience init(level: LogLevel) {
        self.init(level: level, domains: .all)
    }
    
    // MARK: Internal
    
    init() { }
    
    func toImpl() -> CBLCustomLogger {
        return CBLCustomLogger(level: CBLLogLevel(rawValue: UInt(level.rawValue))!,
                               domains: CBLLogDomain(rawValue: UInt(domains.rawValue)))
    }
    
}
