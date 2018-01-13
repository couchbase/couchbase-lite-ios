//
//  Where.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// Where class represents the WHERE clause of the query statement.
public final class Where: Query, GroupByRouter, OrderByRouter, LimitRouter {
    
    /// Create and chain an ORDER BY component for specifying the orderings of the query result.
    ///
    /// - Parameter orderings: The ordering objects.
    /// - Returns: The OrderBy object.
    public func orderBy(_ orderings: Ordering...) -> OrderBy {
        return OrderBy(query: self, impl: Ordering.toImpl(orderings: orderings))
    }
    
    
    /// Create and chain a GROUP BY component to group the query result.
    ///
    /// - Parameter expressions: The expression objects.
    /// - Returns: The GroupBy object.
    public func groupBy(_ expressions: Expression...) -> GroupBy {
        return GroupBy(query: self, impl: Expression.toImpl(expressions: expressions))
    }
    
    
    /// Create and chain a LIMIT component to limit the number query results.
    ///
    /// - Parameter limit: The limit Expression object or liternal value.
    /// - Returns: The Limit object.
    public func limit(_ limit: Expression) -> Limit {
        return self.limit(limit, offset: nil)
    }
    
    
    /// Create and chain a LIMIT component to skip the returned results for the given offset
    /// position and to limit the number of results to not more than the given limit value.
    ///
    /// - Parameters:
    ///   - limit: The limit Expression object or liternal value.
    ///   - offset: The offset Expression object or liternal value.
    /// - Returns: The Limit object.
    public func limit(_ limit: Expression, offset: Expression?) -> Limit {
        return Limit(query: self, limit: limit, offset: offset)
    }
    
    
    /// An internal constructor.
    init(query: Query, impl: CBLQueryExpression) {
        super.init()
        
        self.copy(query)
        self.whereImpl = impl
    }
    
}
