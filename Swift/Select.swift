//
//  Select.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
