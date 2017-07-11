//
//  Having.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** Having represents a HAVING clause of the query statement used for filtering the aggregated values
    from the the GROUP BY clause. */
public final class Having: Query, OrderByRouter, LimitRouter {
    
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
    
    init(query: Query, impl: CBLQueryExpression) {
        super.init()
        
        self.copy(query)
        self.havingImpl = impl
    }
    
}
