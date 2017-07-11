//
//  LimitRouter.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** LimitRouter for creating and chaning a query LIMIT clause to constraint 
    the number of results returned by a query. */
protocol LimitRouter {
    /** Create and chain a LIMIT component to limit the number of results to not more than 
        the given limit value. */
    func limit(_ limit: Any) -> Limit
    
    /** Create and chain a LIMIT component to skip the returned results for the given offset position 
        and to limit the number of results to not more than the given limit value. */
    func limit(_ limit: Any, offset: Any?) -> Limit
}
