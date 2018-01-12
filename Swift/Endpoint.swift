//
//  Endpoint.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 1/9/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

import Foundation


/// Replication target endpoint.
public protocol Endpoint {
    // Opaque
}

/* internal */ protocol InternalEndpoint: Endpoint {
    func toImpl() -> CBLEndpoint;
}

/// Database based replication target endpoint.
public struct DatabaseEndpoint: InternalEndpoint {
    
    /// The database object.
    public let database: Database
    
    /// Initializes the DatabaseEndpoint with the database object.
    ///
    /// - Parameter database: The database object.
    public init(withDatabase database: Database) {
        self.database = database
    }
    
    // MARK: Internal
    
    func toImpl() -> CBLEndpoint {
        return CBLDatabaseEndpoint(database: self.database._impl)
    }
    
}

/// URL based replication target endpoint.
public struct URLEndpoint: InternalEndpoint {
    
    /// The URL host
    public let host: String
    
    /// The URL port
    public let port: UInt?
    
    /// The URL path
    public let path: String?
    
    /// A boolean value indicates whether the replication data will be sent over
    /// secure channels.
    public let isSecure: Bool
    
    /// Initializes with the host, and the secure flag.
    ///
    /// - Parameters:
    ///   - host: The URL host.
    ///   - secure: The secure flag indicating whether the replication data will
    ///             be sent over secure channels.
    public init(withHost host: String, secure: Bool) {
        self.init(withHost: host, port: nil, path: nil, secure: secure)
    }
    
    /// Initializes with the host, the path, and the secure flag.
    ///
    /// - Parameters:
    ///   - host: The URL host.
    ///   - path: The URL path.
    ///   - secure: The secure flag indicating whether the replication data will
    ///             be sent over secure channels.
    public init(withHost host: String, path: String?, secure: Bool) {
        self.init(withHost: host, port: nil, path: path, secure: secure)
    }
    
    
    /// Initializes with the host, the port, the path, and the secure flag.
    ///
    /// - Parameters:
    ///   - host: The URL host.
    ///   - port: The URL port number. If the port is not present,
    ///           set the value to nil.
    ///   - path: The URL path.
    ///   - secure: The secure flag indicating whether the replication data will
    ///             be sent over secure channels.
    public init(withHost host: String, port: UInt?, path: String?, secure: Bool) {
        self.host = host
        self.port = port
        self.path = path
        self.isSecure = secure
    }
    
    // MARK: Internal
    
    func toImpl() -> CBLEndpoint {
        let port = self.port != nil ? Int(self.port!) : -1
        return CBLURLEndpoint.init(host: self.host, port: port,
                                   path: self.path, secure: self.isSecure)
    }
    
}
