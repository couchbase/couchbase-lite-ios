//
//  From.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A From component representing a FROM clause for specifying the data source of the query. */
public final class From: Query, JoinRouter, WhereRouter, GroupByRouter, OrderByRouter  {
    
    /** Create and chain a WHERE component for specifying the WHERE clause of the query. */
    public func `where`(_ whereExpression: Expression) -> Where {
        return Where(query: self, impl: whereExpression.impl)
    }
    
    /** Create and chain a GROUP BY component to group the query result. */
    public func groupBy(_ groupBy: GroupBy...) -> GroupBy {
        return GroupBy(query: self, impl: GroupBy.toImpl(groupBies: groupBy))
    }
    
    /** Create and chain ORDER BY components for specifying the order of the query result. */
    public func orderBy(_ orders: OrderBy...) -> OrderBy {
        return OrderBy(query: self, impl: OrderBy.toImpl(orders: orders))
    }
    
    /** Create and chain JOIN components for specifying the JOIN clause of the query. */
    public func join(_ joins: Join...) -> Join {
        return Join(query: self, impl: Join.toImpl(joins: joins))
    }
    
    /** An internal constructor. */
    init(query: Query, impl: CBLQueryDataSource, database: Database) {
        super.init()
        
        self.copy(query)
        self.fromImpl = impl
        self.database = database
    }
    
}
