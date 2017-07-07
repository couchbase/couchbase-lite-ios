//
//  Joins.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/6/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A Joins component represents a collection of the joins clauses of the query statement.  */
public class Joins: Query, WhereRouter, OrderByRouter {
    
    /** Create and chain a WHERE component for specifying the WHERE clause of the query. */
    public func `where`(_ whereExpression: Expression) -> Where {
        return Where(query: self, impl: whereExpression.impl)
    }
    
    /** Create and chain an ORDER BY component for specifying the orderings of the query result. */
    public func orderBy(_ orderings: Ordering...) -> OrderBy {
        return OrderBy(query: self, impl: Ordering.toImpl(orderings: orderings))
    }
    
    // MARK: Internal
    
    init(query: Query, impl: [CBLQueryJoin]) {
        super.init()
        self.copy(query)
        self.joinsImpl = impl
    }
    
}
