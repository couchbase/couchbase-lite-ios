//
//  Ordering.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/6/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// Ordering represents a single ordering component in the query ORDER BY clause.
public protocol OrderingProtocol {
    
}

/// SortOrder allows to specify the ordering direction which is ascending or
/// descending order. The default ordering is the ascending order.
public protocol SortOrder: OrderingProtocol {
    /// Specifies ascending order.
    ///
    /// - Returns: The ascending Ordering object.
    func ascending() -> OrderingProtocol
    
    /// Specifies descending order.
    ///
    /// - Returns: The descending Ordering object.
    func descending() -> OrderingProtocol
}

/// Ordering factory.
public final class Ordering {
    
    /// Create an Ordering instance with the given property name.
    ///
    /// - Parameter property: The property name.
    /// - Returns: The SortOrder object used for specifying the sort order, 
    ///            ascending or descending order.
    public static func property(_ property: String) -> SortOrder {
        return expression(Expression.property(property))
    }
    
    
    /// Create an Ordering instance with the given expression.
    ///
    /// - Parameter expression: The Expression object.
    /// - Returns: The SortOrder object used for specifying the sort order,
    ///            ascending or descending order.
    public static func expression(_ expression: ExpressionProtocol) -> SortOrder {
        let sortOrder = CBLQueryOrdering.expression(expression.toImpl())
        return QuerySortOrder(impl: sortOrder)
    }
    
}

/* internal */ class QueryOrdering : OrderingProtocol {
    
    let impl: CBLQueryOrdering
    
    init(impl: CBLQueryOrdering) {
        self.impl = impl
    }
    
    func toImpl() -> CBLQueryOrdering {
        return self.impl
    }
    
    static func toImpl(orderings: [OrderingProtocol]) -> [CBLQueryOrdering] {
        var impls: [CBLQueryOrdering] = []
        for o in orderings {
            impls.append(o.toImpl())
        }
        return impls;
    }
    
}


/* internal */ class QuerySortOrder: QueryOrdering, SortOrder {
    
    public func ascending() -> OrderingProtocol {
        let o = self.impl as! CBLQuerySortOrder
        return QueryOrdering(impl: o.ascending())
    }
    
    public func descending() -> OrderingProtocol {
        let o = self.impl as! CBLQuerySortOrder
        return QueryOrdering(impl: o.descending())
    }
    
}

extension OrderingProtocol {
    
    func toImpl() -> CBLQueryOrdering {
        if let o = self as? QueryOrdering {
            return o.toImpl()
        }
        fatalError("Unsupported ordering.")
    }
    
}
