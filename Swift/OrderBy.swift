//
//  OrderBy.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/**  An OrderBy represents a query ORDER BY clause by sepecifying properties or expressions t
 hat the result rows should be sorted by.
 A CBLQueryOrderBy can be construct as a single CBLQuerySortOrder instance with a propery name
 or an expression instance or as a chain of multiple CBLQueryOrderBy instances. */
public class OrderBy: Query {
    
    /** Create an Order By instance with a given property name. */
    public static func property(_ property: String) -> SortOrder {
        return expression(Expression.property(property))
    }
    
    /** Create an Order By instance with a given expression. */
    public static func expression(_ expression: Expression) -> SortOrder {
        let sortOrder = CBLQueryOrderBy.expression(expression.impl);
        return SortOrder(impl: sortOrder)
    }
    
    // MARK: Internal
    
    let impl: CBLQueryOrderBy
    
    init(query: Query, impl: CBLQueryOrderBy) {
        self.impl = impl
        super.init()
        
        self.copy(query)
        self.orderByImpl = impl
    }
    
    init(impl: CBLQueryOrderBy) {
        self.impl = impl
        super.init()
    }
    
}

public final class SortOrder: OrderBy {
    
    init(impl: CBLQuerySortOrder) {
        super.init(impl: impl)
    }
    
    public func ascending() -> OrderBy {
        let orderBy = self.impl as! CBLQuerySortOrder
        return OrderBy(impl: orderBy.ascending())
    }
    
    public func descending() -> OrderBy {
        let orderBy = self.impl as! CBLQuerySortOrder
        return OrderBy(impl: orderBy.descending())
    }
    
}
