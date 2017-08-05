//
//  Database+PredicateQuery.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
