//
//  DataSource.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A query data source. used for specifiying the data source for your query.
 The current data source supported is the database. */
public class DataSource {
    
    /** Create a database data source. */
    public static func database(_ database: Database) -> DatabaseSource {
        return DatabaseSource(impl: CBLQueryDataSource.database(database._impl), database: database)
    }
    
    // MARK: Internal
    
    let impl: CBLQueryDataSource
    
    let database: Database
    
    init(impl: CBLQueryDataSource, database: Database) {
        self.impl = impl
        self.database = database
    }
    
}

/** A database data source. You could also create an alias data source by calling the as(alias) 
 method with a given alias name. */
public class DatabaseSource: DataSource {
    
    /** Create an alias data source. */
    public func `as`(_ alias: String) -> DataSource {
        return self
    }
    
}
