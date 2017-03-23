//
//  From.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A From component represent a FROM statment for specifying a query data source. */
public final class From: Query, WhereRouter, OrderByRouter  {
    
    /** Create and chain a WHERE clause component to specify a query WHERE clause
     used for filtering the query result. */
    public func `where`(_ whereExpression: Expression) -> Where {
        return Where(query: self, impl: whereExpression.impl)
    }
    
    /** Create and chain an ORDER BY clause component to specify the order of the query result. */
    public func orderBy(_ orders: OrderBy...) -> OrderBy {
        let implOrders = orders.map { (o) -> CBLQueryOrderBy in
            return o.impl
        }
        return OrderBy(query: self, impl: CBLQueryOrderBy(array: implOrders))
    }
    
    /** An internal constructor. */
    init(query: Query, impl: CBLQueryDataSource, database: Database?) {
        super.init()
        
        self.copy(query)
        self.fromImpl = impl
        self.database = database
    }
    
}
