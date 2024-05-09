//
//  Scope.swift
//  CouchbaseLite
//
//  Copyright (c) 2024-present Couchbase, Inc All rights reserved.
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
import CouchbaseLiteSwift_Private

/// A Scope represents a scope or namespace of the collections.
///
/// The scope implicitly exists when there is at least one collection created under the scope.
/// The default scope is exceptional in that it will always exists even there are no collections
/// under it.
///
/// `Scope` Lifespan
/// A `Scope` object remain valid until either the database is closed or
/// the scope itself is invalidated as all collections in the scope have been deleted. 
public final class Scope {
    
    /// The default scope name constant
    public static let defaultScopeName: String = kCBLDefaultScopeName
    
    /// Scope's name
    public var name: String {
        return impl.name
    }
    
    /// Collection's database
    public let database: Database
    
    // MARK: Collections
    
    /// Get all collections in the scope.
    public func collections() throws -> [Collection] {
        return try self.database.collections(scope: impl.name)
    }
    
    /// Get a collection in the scope by name. If the collection doesn't exist, a nil value will be returned.
    /// - Parameter name: Collection name as String.
    /// - Returns: Collection object or nil if it doesn't exist.
    /// - Throws: An error on when database object is not available.
    public func collection(name: String) throws -> Collection? {
        return try self.database.collection(name: name, scope: impl.name)
    }
    
    init(_ scope: CBLScope, db: Database) {
        self.impl = scope
        self.database = db
    }
    
    let impl: CBLScope
}
