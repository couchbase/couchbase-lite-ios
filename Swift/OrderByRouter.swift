//
//  OrderByRouter.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** OrderByRouter for creating and chaning a query ORDER BY clause. */
protocol OrderByRouter {
    /** Create and chain an ORDER BY component for specifying the orderings of the query result. */
    func orderBy(_ orderings: Ordering...) -> OrderBy
}
