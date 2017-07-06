//
//  Select.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A Select component represents the returning properties in each query result row. */
public final class Select: Query, FromRouter {
    
    /** Create and chain a FROM clause component to specify a data source of the query. */
    public func from(_ dataSource: DataSource) -> From {
        return From(query: self, impl: dataSource.impl, database: dataSource.database);
    }
    
    /** An internal constructor. */
    init(impl: [CBLQuerySelectResult], distict: Bool) {
        super.init()
        
        self.selectImpl = impl
        self.distinct = distinct
    }
    
}
