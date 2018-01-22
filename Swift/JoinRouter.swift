//
//  JoinRouter.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// JoinRouter for creating and chaning he JOIN components to specify a query JOIN clause.
protocol JoinRouter {
    
    /// Create and chain the JOIN components to specify a query JOIN clause.
    ///
    /// - Parameter join: The join objects.
    /// - Returns: The Joins object.
    func join(_ join: JoinProtocol...) -> Joins
    
}
