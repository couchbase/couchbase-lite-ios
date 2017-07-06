//
//  HavingRouter.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** HavingRouter for creating and chaning a query HAVING clause. */
protocol HavingRouter {
    /** Create and chain a HAVING component. */
    func having(_ expression: Expression) -> Having
}
