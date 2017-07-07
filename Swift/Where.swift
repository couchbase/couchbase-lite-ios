//
//  Where.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

public final class Where: Query, GroupByRouter, OrderByRouter {
    
    /** Create and chain an ORDER BY component for specifying the orderings of the query result. */
    public func orderBy(_ orderings: Ordering...) -> OrderBy {
        return OrderBy(query: self, impl: Ordering.toImpl(orderings: orderings))
    }
    
    /** Create and chain a GROUP BY component to group the query result. */
    public func groupBy(_ expressions: Expression...) -> GroupBy {
        return GroupBy(query: self, impl: Expression.toImpl(expressions: expressions))
    }
    
    /** An internal constructor. */
    init(query: Query, impl: CBLQueryExpression) {
        super.init()
        
        self.copy(query)
        self.whereImpl = impl
    }
    
}
