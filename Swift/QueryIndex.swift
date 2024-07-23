//
//  QueryIndex.swift
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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

/// QueryIndex object representing an existing index in the collection.
public class QueryIndex {
    
    /// The collection.
    public let collection: Collection
    
    /// The index name.
    public var name: String { impl.name }

#if COUCHBASE_ENTERPRISE
    
    /// ENTERPRISE EDITION ONLY
    ///
    /// For updating lazy vector indexes only.
    /// Finds new or updated documents for which vectors need to be (re)computed and
    /// return an IndexUpdater object used for setting the computed vectors for updating the index.
    /// The limit parameter is for setting the max number of vectors to be computed.
    /// - Parameter limit: The limit per update.
    /// - Returns: IndexUpdater object if there are updates to be done, or nil if the index is up-to-date.
    public func beginUpdate(limit: UInt64) throws -> IndexUpdater? {
        var error: NSError?
        let updater = impl.beginUpdate(withLimit: limit, error: &error)
        if let err = error {
            throw err
        }
        
        guard let updaterImpl = updater else {
            return nil
        }
        
        return IndexUpdater(updaterImpl)
    }
#endif
    
    // MARK: Internal
    
    private let impl: CBLQueryIndex
    
    init(_ impl: CBLQueryIndex, collection: Collection) {
        self.impl = impl
        self.collection = collection
    }
    
}
