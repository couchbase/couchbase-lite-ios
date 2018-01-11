//
//  Joins.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/6/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A Joins component represents a collection of the joins clauses of the query statement.
public final class Joins: Query, WhereRouter, OrderByRouter, LimitRouter {
    
    /// Creates and chains a Where object for specifying the WHERE clause of the query.
    ///
    /// - Parameter expression: The where expression.
    /// - Returns: The Where object that represents the WHERE clause of the query.
    public func `where`(_ expression: Expression) -> Where {
        return Where(query: self, impl: expression.impl)
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
    
    
    init(query: Query, impl: [CBLQueryJoin]) {
        super.init()
        self.copy(query)
        self.joinsImpl = impl
    }
    
}
