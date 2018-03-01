//
//  Endpoint.swift
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


/// Replication target endpoint.
public protocol Endpoint {
    // Opaque
}

/* internal */ protocol IEndpoint: Endpoint {
    func toImpl() -> CBLEndpoint;
}

#if COUCHBASE_ENTERPRISE
/// Database based replication target endpoint.
public struct DatabaseEndpoint: IEndpoint {
    
    /// The database object.
    public let database: Database
    
    /// Initializes the DatabaseEndpoint with the database object.
    ///
    /// - Parameter database: The database object.
    public init(database: Database) {
        self.database = database
    }
    
    // MARK: Internal
    
    func toImpl() -> CBLEndpoint {
        return CBLDatabaseEndpoint(database: self.database._impl)
    }
}    
#endif

/// URL based replication target endpoint.
public struct URLEndpoint: IEndpoint {
    
    /// The URL.
    public let url: URL
    
    /// Initializes with the given URL. The supported URL schemes are ws and wss
    /// for transferring data over a secure connection.
    ///
    /// - Parameter url: The URL object.
    public init(url: URL) {
        impl = CBLURLEndpoint(url: url)
        self.url = url
    }
    
    // MARK: Internal
    
    private let impl: CBLURLEndpoint
    
    func toImpl() -> CBLEndpoint {
        return impl
    }
    
}
