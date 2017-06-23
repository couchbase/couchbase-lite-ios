//
//  LiveQueryChange.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** LiveQueryChange contains the information about the query result changes reported
 by a live query object. */
public struct LiveQueryChange {
    /** The source live query object. */
    public let query: LiveQuery
    
    /** The new query result. */
    public let rows: QueryIterator?
    
    /** The error occurred when running the query. */
    public let error: Error?
}
