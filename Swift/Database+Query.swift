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


extension Database {
    
    /// All index names.
    public var indexes: Array<String> { return _impl.indexes }
    
    
    /// Creates an index which could be a value index or a full-text search index with the given
    /// name. The name can be used for deleting the index. Creating a new different index with an
    /// existing index name will replace the old index; creating the same index with the same name
    /// will be no-ops.
    ///
    /// - Parameters:
    ///   - index: The index.
    ///   - name: The index name.
    /// - Throws: An error on a failure.
    public func createIndex(_ index: Index, withName name: String) throws {
        try _impl.createIndex(index.toImpl(), withName: name)
    }
    
    
    /// Deletes the index of the given index name.
    ///
    /// - Parameter name: The index name.
    /// - Throws: An error on a failure.
    public func deleteIndex(forName name: String) throws {
        try _impl.deleteIndex(forName: name)
    }
    
}
