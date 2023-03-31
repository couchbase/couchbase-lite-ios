//
//  Database+Query.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

extension Database : QueryFactory {
    
    /// Creates a Query object from the given query string.
    ///
    /// - Parameters:
    ///     - query Query string
    /// - Returns: A query created by the given query string.
    /// - Throws: An error on when the given query string is invalid.
    public func createQuery(_ query: String) throws -> Query {
        return try Query(database: self, expressions: query)
    }
    
    /// All index names.
    @available(*, deprecated, message: "Use database.defaultCollection().indexes() instead.")
    public var indexes: Array<String> { return impl.indexes }
    
    /// Creates an index wih the given name in the default collection. The index could be a value index or a full-text index.
    /// The index name can be used later for deleting the index. Creating a new different index with an existing index name will
    /// replace the old index. Creating the same index with the same name will be no-ops.
    ///
    /// - Parameters:
    ///   - index: The index.
    ///   - name: The index name.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().createIndex(:name:) instead.")
    public func createIndex(_ index: Index, withName name: String) throws {
        try impl.createIndex(index.toImpl(), withName: name)
    }
    
    /// Creates an index in the default collection with the index config and the index name. The index config could be a value index or a full-text
    /// index config. The index name can be used later for deleting the index.  Creating a new different index with an existing index name
    /// will replace the old index. Creating the same index with the same name will be no-ops.
    ///
    /// - Parameters:
    ///     - config: The index configuration
    ///     - name: The index name.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().createIndex(:name:) instead.")
    public func createIndex(_ config: IndexConfiguration, name: String) throws {
        try impl.createIndex(withConfig: config.toImpl(), name: name)
    }
    
    /// Deletes the index from the default collection by name.
    ///
    /// - Parameter name: The index name.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().deleteIndex(forName:) instead.")
    public func deleteIndex(forName name: String) throws {
        try impl.deleteIndex(forName: name)
    }
    
}
