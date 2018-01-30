//
//  Query.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
