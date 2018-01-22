//
//  Select.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A Select component represents the returning properties in each query result row.
public final class Select: Query, FromRouter {
    
    /// Create and chain a FROM clause component to specify a data source of the query.
    ///
    /// - Parameter dataSource: The DataSource object.
    /// - Returns: The From object that represent the FROM clause of the query.
    public func from(_ dataSource: DataSourceProtocol) -> From {
        return From(query: self,
                    impl: dataSource.toImpl(),
                    database: dataSource.source() as! Database);
    }
    
    // MARK: Internal
    
    init(impl: [CBLQuerySelectResult], distinct: Bool) {
        super.init()
        
        self.selectImpl = impl
        self.distinct = distinct
    }
    
}
