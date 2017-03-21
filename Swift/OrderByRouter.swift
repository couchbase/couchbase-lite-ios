//
//  OrderByRouter.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** WhereRouter for creating and chaning a query ORDER BY clause. */
protocol OrderByRouter {
    /** Create and chain an ORDER BY clause component to specify the order of the query result. */
    func orderBy(_ orderBy: OrderBy...) -> OrderBy
}
