//
//  Scope.swift
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

/// A CBLScope represents a scope or namespace of the collections.
///
/// The scope implicitly exists when there is at least one collection created under the scope.
/// The default scope is exceptional in that it will always exists even there are no collections
/// under it.
///
/// `CBLScope` Lifespan
/// A `CBLScope` object remain valid until either the database is closed or
/// the scope itself is invalidated as all collections in the scope have been deleted. 
public final class Scope {
    
    /// The default scope name constant
    public static let defaultScopeName: String = "_default"
    
    /// Scope name
    public var name: String {
        return _impl.name
    }
    
    // MARK: Collections
    
    /// Get all collections in the scope.
    public func collections() throws -> [Collection] {
        var collections = [Collection]()
        for c in try _impl.collections() {
            collections.append(Collection(impl: c))
        }
        
        return collections
    }
    
    /// Get a collection in the scope by name. If the collection doesn't exist, a nil value will be returned.
    public func collection(name: String) throws -> Collection? {
        let c = try _impl.collection(withName: name)
        return Collection(impl: c)
    }
    
    init(_ scope: CBLScope) {
        _impl = scope
    }
    
    let _impl: CBLScope
}
