//
//  Database+PredicateQuery.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


extension Database {
    /** An iterator over all documents in the database, ordered by document ID. */
    public var allDocuments: DocumentIterator {
        return DocumentIterator(database: self, enumerator: _impl.allDocuments())
    }
    
    
    /** Compiles a database query, from any of several input formats.
     Once compiled, the query can be run many times with different parameter values.*/
    public func createQuery(where wher: Predicate? = nil,
                            groupBy: [PredicateExpression]? = nil,
                            having: Predicate? = nil,
                            returning: [PredicateExpression]? = nil,
                            distinct: Bool = false,
                            orderBy: [SortDescriptor]? = nil) -> PredicateQuery
    {
        return PredicateQuery(from: self, where: wher, groupBy: groupBy, having: having,
                              returning: returning, distinct: distinct, orderBy: orderBy)
    }
}
