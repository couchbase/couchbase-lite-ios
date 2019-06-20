//
//  ConflictResolver.swift
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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

/// Conflict Resolver protocol
public protocol ConflictResolverProtocol {
    
    /// The callback resolve method, if conflict occurs.
    func resolve(conflict: Conflict) -> Document?
    
}


/// ConflictResolver provides access to the default conflict resolver used by the replicator
public final class ConflictResolver {
    
    /// The default conflict resolver used by the replicator.
    public static var `default`: ConflictResolverProtocol {
        return DefaultResolver.shared
    }
    
}

/* internal */ class DefaultResolver: ConflictResolverProtocol {
    
    let resolver: CBLConflictResolverProtocol
    
    static let shared: DefaultResolver = DefaultResolver()
    
    private init() {
        resolver = CBLConflictResolver.default()
    }
    
    func resolve(conflict: Conflict) -> Document? {
        guard let doc = resolver.resolve(conflict.impl) else {
            return nil
        }
        
        return Document(doc)
    }
    
}
