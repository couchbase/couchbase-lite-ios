//
//  Ordering.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/6/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** An Ordering represents a single ordering component in the query ORDER BY clause. */
public class Ordering {
    
    /** Create an Ordering instance with the given property name. */
    public static func property(_ property: String) -> SortOrder {
        return expression(Expression.property(property))
    }
    
    /** Create an Ordering instance with the given expression. */
    public static func expression(_ expression: Expression) -> SortOrder {
        let sortOrder = CBLQueryOrdering.expression(expression.impl)
        return SortOrder(impl: sortOrder)
    }
    
    // MARK: Internal
    
    let impl: CBLQueryOrdering
    
    init(impl: CBLQueryOrdering) {
        self.impl = impl
    }
    
    static func toImpl(orderings: [Ordering]) -> [CBLQueryOrdering] {
        var impls: [CBLQueryOrdering] = []
        for o in orderings {
            impls.append(o.impl)
        }
        return impls;
    }
    
}

/** SortOrder allows to specify the ordering direction which is an ascending or
    a descending order */
public final class SortOrder: Ordering {
    
    public func ascending() -> Ordering {
        let o = self.impl as! CBLQuerySortOrder
        return Ordering(impl: o.ascending())
    }
    
    public func descending() -> Ordering {
        let o = self.impl as! CBLQuerySortOrder
        return Ordering(impl: o.descending())
    }
    
}
