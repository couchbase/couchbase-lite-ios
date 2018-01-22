//
//  DataSource.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


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
    
    /// Create a database data source.
    ///
    /// - Parameter database: The database object.
    /// - Returns: The database data source.
    public static func database(_ database: Database) -> DataSourceAs {
        return DatabaseSourceAs(impl: CBLQueryDataSource.database(database._impl),
                                database: database)
    }
}

/* internal */ class DatabaseSource: DataSourceProtocol {
    
    private let impl: CBLQueryDataSource
    
    let database: Database
    
    init(impl: CBLQueryDataSource, database: Database) {
        self.impl = impl
        self.database = database
    }
    
    func toImpl() -> CBLQueryDataSource {
        return self.impl
    }
    
    func source() -> Any {
        return self.database
    }
    
}

/* internal */ class DatabaseSourceAs: DatabaseSource, DataSourceAs {

    public func `as`(_ alias: String) -> DataSourceProtocol {
        return DatabaseSource(impl: CBLQueryDataSource.database(self.database._impl, as: alias),
                              database: self.database)
    }
    
}

extension DataSourceProtocol {
    
    func toImpl() -> CBLQueryDataSource {
        if let o = self as? DatabaseSource {
            return o.toImpl()
        }
        fatalError("Unsupported Data Source");
    }
    
    func source() -> Any {
        if let o = self as? DatabaseSource {
            return o.source()
        }
        fatalError("Unsupported data source.");
    }
    
}
