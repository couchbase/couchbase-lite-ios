//
//  From.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A From component representing a FROM clause for specifying the data source of the query.
public final class From: Query, JoinRouter, WhereRouter, GroupByRouter, OrderByRouter, LimitRouter  {
    
    /// Creates and chains a Joins object for specifying the JOIN clause of the query.
    ///
    /// - Parameter joins: The Join objects.
    /// - Returns: The Joins object that represents the JOIN clause of the query.
    public func join(_ joins: Join...) -> Joins {
        return Joins(query: self, impl: Join.toImpl(joins: joins))
    }
    
    
    /// Creates and chains a Where object for specifying the WHERE clause of the query.
    ///
    /// - Parameter whereExpression: The where expression.
    /// - Returns: The Where object that represents the WHERE clause of the query.
    public func `where`(_ whereExpression: Expression) -> Where {
        return Where(query: self, impl: whereExpression.impl)
    }
    
    
    /// Creates and chains a GroupBy object to group the query result.
    ///
    /// - Parameter expressions: The group by expression.
    /// - Returns: The GroupBy object that represents the GROUP BY clause of the query.
    public func groupBy(_ expressions: Expression...) -> GroupBy {
        return GroupBy(query: self, impl: Expression.toImpl(expressions: expressions))
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
    
    /** An internal constructor. */
    init(query: Query, impl: CBLQueryDataSource, database: Database) {
        super.init()
        
        self.copy(query)
        self.fromImpl = impl
        self.database = database
    }
    
}
