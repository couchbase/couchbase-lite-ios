//
//  LiveQuery.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A LiveQuery automatically observes database changes and re-run the query that the LiveQuery
 object is created from. If there is a new query result or an error occurred, the LiveQuery object
 will report the changed result via the added listener blocks. */
public class LiveQuery {
    
    /** Starts observing database changes and reports changes in the query result. */
    public func run() {
        impl.run()
    }
    
    /** Stops observing database changes. */
    public func stop() {
        impl.stop()
    }
    
    /** Adds a query result change listener block.
     @param block    a change listener block
     @return the opaque listener object used for removing the added change listener block. */
    public func addChangeListener(_ block: @escaping (LiveQueryChange) -> Void) -> NSObjectProtocol {
        return impl.addChangeListener { (c) in
            let rows: QueryIterator?;
            if let rowsEnum = c.rows {
                rows = QueryIterator(database: self.database, enumerator: rowsEnum)
            } else {
                rows = nil;
            }
            block(LiveQueryChange(query: self, rows: rows, error: c.error))
        }
    }
    
    /** Removed a change listener.
     @param listener  a listener object received when adding the change listener block. */
    public func removeChangeListener(_ listener: NSObjectProtocol) {
        impl.removeChangeListener(listener)
    }
    
    // MARK: Internal
    
    let impl: CBLLiveQuery
    
    let database: Database
    
    init(database: Database, impl: CBLLiveQuery) {
        self.impl = impl
        self.database = database
    }
}
