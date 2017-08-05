//
//  Limit.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A Limit component represents the LIMIT clause of the query statement.
public class Limit: Query  {
    
    // MARK: Internal
    
    init(query: Query, impl: CBLQueryLimit) {
        super.init()
        
        self.copy(query)
        self.limitImpl = impl
    }
    
    static func toImpl(limit: Any, offset: Any?) -> CBLQueryLimit {
        return CBLQueryLimit( Expression.toImpl(limit),
                              offset: offset != nil ? Expression.toImpl(offset!) : nil)
    }

}
