//
//  OrderBy.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/** An OrderBy represents an ORDER BY clause of the query statement. */
public class OrderBy: Query, LimitRouter {
    
    /** Create and chain a LIMIT component to limit the number query results. */
    public func limit(_ limit: Any) -> Limit {
        return self.limit(limit, offset: nil)
    }
    
    /** Create and chain a LIMIT component to skip the returned results for the given offset 
        position and to limit the number of results to not more than the given limit value. */
    public func limit(_ limit: Any, offset: Any?) -> Limit {
        return Limit(query: self, impl: Limit.toImpl(limit: limit, offset: offset))
    }
    
    // MARK: Internal
    
    init(query: Query, impl: [CBLQueryOrdering]) {
        super.init()
        self.copy(query)
        self.orderingsImpl = impl
    }
    
}
