//
//  DataSource.swift
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
import CouchbaseLiteSwift_Private


/// A query data source. used for specifiying the data source for your query.
public protocol DataSourceProtocol {
    
}

/// A query data source with the aliasing function.
public protocol DataSourceAs: DataSourceProtocol {
    
    /// Create an alias data source.
    ///
    /// - Parameter alias: The alias name.
    /// - Returns: The DataSource object.
    func `as`(_ alias: String) -> DataSourceProtocol
    
}

/// A query data source factory.
/// The current data source supported is the database.
public final class DataSource {
    
    public static func collection(_ collection: Collection) -> DataSourceAs {
        return DatabaseSourceAs(impl: CBLQueryDataSource.collection(collection.impl),
                                source: collection)
    }
    
}

/* internal */ class DatabaseSource: DataSourceProtocol {
    
    private let impl: CBLQueryDataSource
    
    let dataSource: Any
    
    init(impl: CBLQueryDataSource, source: Any) {
        self.impl = impl
        self.dataSource = source
    }
    
    func toImpl() -> CBLQueryDataSource {
        return self.impl
    }
    
    func source() -> Any {
        guard let col = dataSource as? Collection else {
            fatalError("Unknown datasource type detected!")
        }
        return col
    }
    
}

/* internal */ class DatabaseSourceAs: DatabaseSource, DataSourceAs {

    public func `as`(_ alias: String) -> DataSourceProtocol {
        guard let collection = dataSource as? Collection else {
            fatalError("Unknown datasource type!")
        }
        return DatabaseSource(impl: CBLQueryDataSource.collection(collection.impl, as: alias), source: collection)
    }
}

extension DataSourceProtocol {
    
    func toImpl() -> CBLQueryDataSource {
        if let o = self as? DatabaseSource {
            return o.toImpl()
        }
        fatalError("Unsupported Data Source");
    }
    
    var database: Database {
        guard let o = self as? DatabaseSource,
              let colSource = o.source() as? Collection else {
            fatalError("Unsupported data source.")
        }
        return colSource.database
    }
}
