//
//  HavingRouter.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// HavingRouter for creating and chaning a query HAVING clause.
protocol HavingRouter {
    
    /// Creates and chain a Having object for filtering the aggregated values
    /// from the the GROUP BY clause.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The Having object that represents the HAVING clause of the query.
    func having(_ expression: Expression) -> Having
    
}
