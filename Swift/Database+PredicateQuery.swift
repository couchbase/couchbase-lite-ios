//
//  Database+PredicateQuery.swift
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
    
    /// An iterator over all documents in the database, ordered by document ID.
    public var allDocuments: DocumentIterator {
        return DocumentIterator(database: self, enumerator: _impl.allDocuments())
    }
    
    
    /// Compiles a database query, from any of several input formats.
    /// Once compiled, the query can be run many times with different parameter values.
    ///
    /// - Parameters:
    ///   - wherePredicate: The where predicate.
    ///   - groupBy: The group by expressions.
    ///   - having: The having predicate.
    ///   - returning: The returning values.
    ///   - distinct: The distict flag.
    ///   - orderBy: The order by as an array of the SortDescriptor object.
    /// - Returns: The Predicate Query.
    public func createQuery(where wherePredicate: Predicate? = nil,
                            groupBy: [PredicateExpression]? = nil,
                            having: Predicate? = nil,
                            returning: [PredicateExpression]? = nil,
                            distinct: Bool = false,
                            orderBy: [SortDescriptor]? = nil) -> PredicateQuery
    {
        return PredicateQuery(from: self, where: wherePredicate, groupBy: groupBy, having: having,
                              returning: returning, distinct: distinct, orderBy: orderBy)
    }
}
