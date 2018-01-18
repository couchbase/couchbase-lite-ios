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
    
    /// The URL.
    public let url: URL
    
    /// Initializes with the given URL. The supported URL schemes are ws and wss
    /// for transferring data over a secure connection.
    ///
    /// - Parameter url: The URL object.
    public init(withURL url: URL) {
        impl = CBLURLEndpoint(url: url)
        self.url = url
    }
    
    // MARK: Internal
    
    private let impl: CBLURLEndpoint
    
    func toImpl() -> CBLEndpoint {
        return impl
    }
    
}
