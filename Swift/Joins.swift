//
//  Joins.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/6/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A Joins component represents a collection of the joins clauses of the query statement.  */
public class Joins: Query, WhereRouter, OrderByRouter, LimitRouter {
    
    /** Create and chain a WHERE component for specifying the WHERE clause of the query. */
    public func `where`(_ whereExpression: Expression) -> Where {
        return Where(query: self, impl: whereExpression.impl)
    }
    
    /** Create and chain an ORDER BY component for specifying the orderings of the query result. */
    public func orderBy(_ orderings: Ordering...) -> OrderBy {
        return OrderBy(query: self, impl: Ordering.toImpl(orderings: orderings))
    }
    
    /** Create and chain a LIMIT component to limit the number query results. */
    public func limit(_ limit: Any) -> Limit {
        return self.limit(limit, offset: nil)
    }
    
    /** Create and chain a LIMIT component to skip the returned results for the given offset 
        position and to limit the number of results to not more than the given limit value. */
    public func limit(_ limit: Any, offset: Any?) -> Limit {
        return Limit(query: self, impl: Limit.toImpl(limit: limit, offset: offset))
    }
    
    // MARK: Internal
    
    init(query: Query, impl: [CBLQueryJoin]) {
        super.init()
        self.copy(query)
        self.joinsImpl = impl
    }
    
}
