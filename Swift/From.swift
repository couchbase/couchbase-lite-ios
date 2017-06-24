//
//  From.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A From component representing a FROM clause for specifying the data source of the query. */
public final class From: Query, WhereRouter, OrderByRouter  {
    
    /** Create and chain a WHERE component for specifying the WHERE clause of the query. */
    public func `where`(_ whereExpression: Expression) -> Where {
        return Where(query: self, impl: whereExpression.impl)
    }
    
    /** Create and chain an ORDER BY component for specifying the order of the query result. */
    public func orderBy(_ orders: OrderBy...) -> OrderBy {
        let implOrders = orders.map { (o) -> CBLQueryOrderBy in
            return o.impl
        }
        return OrderBy(query: self, impl: CBLQueryOrderBy(implOrders))
    }
    
    /** An internal constructor. */
    init(query: Query, impl: CBLQueryDataSource, database: Database) {
        super.init()
        
        self.copy(query)
        self.fromImpl = impl
        self.database = database
    }
    
}
