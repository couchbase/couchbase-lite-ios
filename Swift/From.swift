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
    public func join(_ joins: JoinProtocol...) -> Joins {
        return Joins(query: self, impl: QueryJoin.toImpl(joins: joins))
    }
    
    
    /// Creates and chains a Where object for specifying the WHERE clause of the query.
    ///
    /// - Parameter expression: The where expression.
    /// - Returns: The Where object that represents the WHERE clause of the query.
    public func `where`(_ expression: ExpressionProtocol) -> Where {
        return Where(query: self, impl: expression.toImpl())
    }
    
    
    /// Creates and chains a GroupBy object to group the query result.
    ///
    /// - Parameter expressions: The group by expression.
    /// - Returns: The GroupBy object that represents the GROUP BY clause of the query.
    public func groupBy(_ expressions: ExpressionProtocol...) -> GroupBy {
        return GroupBy(query: self, impl: QueryExpression.toImpl(expressions: expressions))
    }
    
    
    /// Creates and chains an OrderBy object for specifying the orderings of the query result.
    ///
    /// - Parameter orderings: The Ordering objects.
    /// - Returns: The OrderBy object that represents the ORDER BY clause of the query.
    public func orderBy(_ orderings: OrderingProtocol...) -> OrderBy {
        return OrderBy(query: self, impl: QueryOrdering.toImpl(orderings: orderings))
    }
    
    
    /// Creates and chains a Limit object to limit the number query results.
    ///
    /// - Parameter limit: The limit expression.
    /// - Returns: The Limit object that represents the LIMIT clause of the query.
    public func limit(_ limit: ExpressionProtocol) -> Limit {
        return self.limit(limit, offset: nil)
    }
    
    
    ///  Creates and chains a Limit object to skip the returned results for the given offset
    ///  position and to limit the number of results to not more than the given limit value.
    ///
    /// - Parameters:
    ///   - limit: The limit expression.
    ///   - offset: The offset expression.
    /// - Returns: The Limit object that represents the LIMIT clause of the query.
    public func limit(_ limit: ExpressionProtocol, offset: ExpressionProtocol?) -> Limit {
        return Limit(query: self, limit: limit, offset: offset)
    }
    
    /** An internal constructor. */
    init(query: Query, impl: CBLQueryDataSource, database: Database) {
        super.init()
        
        self.copy(query)
        self.fromImpl = impl
        self.database = database
    }
    
}
