//
//  ResultSet.swift
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
import CouchbaseLiteSwift_Private

/// ResultSet is a result returned from a query.
public final class ResultSet : Sequence, IteratorProtocol {
    
    /// The Element.
    public typealias Element = Result
    
    /// Advances to the next result row and returns the advanced result row.
    ///
    /// - Returns: The advanced Result object.
    public func next() -> Result? {
        if let r = impl.nextObject() as? CBLQueryResult {
            return Result(impl: r)
        } else {
            return nil
        }
    }
    
    /// All unenumerated results.
    ///
    /// - Returns: An array of all unenumerated Result objects.
    public func allResults() -> [Result] {
        return impl.allResults().map { Result(impl: $0) }
    }
    
    /// Get all query results as an array of the decodable model objects.
    ///
    /// @warning This function may take a long time and consume a large amount of memory
    /// depending on the data size and the number of results.
    public func data<T: Decodable>(as type: T.Type, dataKey: String? = nil) throws -> Array<T> {
        let decoder = QueryResultSetDecoder(resultSet: self, dataKey: dataKey)
        return try Array<T>.init(from: decoder)
    }
    
    // MARK: Internal
    
    private let impl: CBLQueryResultSet
    
    init(impl: CBLQueryResultSet) {
        self.impl = impl
    }
    
}
