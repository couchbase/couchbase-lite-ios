//
//  WhereRouter.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// WhereRouter for creating and chaning a query WHERE clause.
protocol WhereRouter {
    
    /// Create and chain a WHERE clause component to specify a query WHERE clause
    /// used for filtering the query result.
    ///
    /// - Parameter where: The where expression.
    /// - Returns: The Where object.
    func `where`(_ expression: Expression) -> Where
    
}
