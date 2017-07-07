//
//  GroupBy.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A GroupBy represents a query GROUP BY statement to group the query result.
    The GROUP BY statement is normally used with aggregate functions (AVG, COUNT, MAX, MIN, SUM)
    to aggregate the group of the values. */
public class GroupBy: Query, HavingRouter, OrderByRouter {
    
    /** Create and chain a HAVING component for filtering the aggregated values 
        from the the GROUP BY clause. */
    public func having(_ expression: Expression) -> Having {
        return Having(query: self, impl: expression.impl)
    }
    
    /** Create and chain an ORDER BY component for specifying the orderings of the query result. */
    public func orderBy(_ orderings: Ordering...) -> OrderBy {
        return OrderBy(query: self, impl: Ordering.toImpl(orderings: orderings))
    }
    
    // MARK: Internal
    
    init(query: Query, impl: [CBLQueryExpression]) {
        super.init()
        self.copy(query)
        self.groupByImpl = impl
    }
    
}
