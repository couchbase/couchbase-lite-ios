//
//  GroupByRouter.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** GroupByRouter for creating and chaning a query GROUP BY clause. */
protocol GroupByRouter {
    /** Create and chain a GROUP BY component. */
    func groupBy(_ groupBy: GroupBy...) -> GroupBy
}
