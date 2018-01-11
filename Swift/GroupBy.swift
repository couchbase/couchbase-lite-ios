//
//  GroupBy.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A GroupBy represents the GROUP BY clause to group the query result.
/// The GROUP BY clause is normally used with aggregate functions (AVG, COUNT, MAX, MIN, SUM)
/// to aggregate the group of the values.
public final class GroupBy: Query, HavingRouter, OrderByRouter, LimitRouter {
    
    /// Creates and chain a Having object for filtering the aggregated values
    /// from the the GROUP BY clause.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The Having object that represents the HAVING clause of the query.
    public func having(_ expression: Expression) -> Having {
        return Having(query: self, impl: expression.impl)
    }
    
    
    /// Creates and chains an OrderBy object for specifying the orderings of the query result.
    ///
    /// - Parameter orderings: The Ordering objects.
    /// - Returns: The OrderBy object that represents the ORDER BY clause of the query.
    public func orderBy(_ orderings: Ordering...) -> OrderBy {
        return OrderBy(query: self, impl: Ordering.toImpl(orderings: orderings))
    }
    
    
    /// Creates and chains a Limit object to limit the number query results.
    ///
    /// - Parameter limit: The limit expression.
    /// - Returns: The Limit object that represents the LIMIT clause of the query.
    public func limit(_ limit: Any) -> Limit {
        return self.limit(limit, offset: nil)
    }
    
    
    ///  Creates and chains a Limit object to skip the returned results for the given offset
    ///  position and to limit the number of results to not more than the given limit value.
    ///
    /// - Parameters:
    ///   - limit: The limit expression.
    ///   - offset: The offset expression.
    /// - Returns: The Limit object that represents the LIMIT clause of the query.
    public func limit(_ limit: Any, offset: Any?) -> Limit {
        return Limit(query: self, impl: Limit.toImpl(limit: limit, offset: offset))
    }
    
    
    // MARK: Internal
    
    
    init(query: Query, impl: [CBLQueryExpression]) {
        super.init()
        self.copy(query)
        self.groupByImpl = impl
    }
    
}
