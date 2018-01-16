//
//  LiveQueryChange.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// QueryChange contains the information about the query result changes reported
/// by a query object.
public struct QueryChange {
    
    /// The source live query object.
    public let query: Query
    
    /// The new query result.
    public let results: ResultSet?
    
    /// The error occurred when running the query.
    public let error: Error?
    
}
