//
//  From.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A From component representing a FROM clause for specifying the data source of the query. */
public final class From: Query, JoinRouter, WhereRouter, GroupByRouter, OrderByRouter, LimitRouter  {
    
    /** Create and chain JOIN components for specifying the JOIN clause of the query. */
    public func join(_ joins: Join...) -> Joins {
        return Joins(query: self, impl: Join.toImpl(joins: joins))
    }
    
    /** Create and chain a WHERE component for specifying the WHERE clause of the query. */
    public func `where`(_ whereExpression: Expression) -> Where {
        return Where(query: self, impl: whereExpression.impl)
    }
    
    /** Create and chain a GROUP BY component to group the query result. */
    public func groupBy(_ expressions: Expression...) -> GroupBy {
        return GroupBy(query: self, impl: Expression.toImpl(expressions: expressions))
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
    
    /** An internal constructor. */
    init(query: Query, impl: CBLQueryDataSource, database: Database) {
        super.init()
        
        self.copy(query)
        self.fromImpl = impl
        self.database = database
    }
    
}
