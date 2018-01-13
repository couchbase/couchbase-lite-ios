//
//  Limit.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A Limit component represents the LIMIT clause of the query statement.
public final class Limit: Query  {
    
    // MARK: Internal
    
    init(query: Query, limit: Expression, offset: Expression?) {
        super.init()
        
        self.copy(query)
        self.limitImpl = CBLQueryLimit(limit.impl, offset: offset != nil ? offset!.impl : nil)
    }
    
}
