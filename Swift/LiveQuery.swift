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
    
    /** Adds a query change listener block.
        @param block   The block to be executed when the change is received.
        @return An opaque object to act as the listener and for removing the listener
                when calling the removeChangeListener() method. */
    @discardableResult
    public func addChangeListener(_ block: @escaping (LiveQueryChange) -> Void) -> NSObjectProtocol {
        return impl.addChangeListener { [unowned self] change in
            let rows: QueryIterator?;
            if let rowsEnum = change.rows {
                rows = QueryIterator(database: self.database, enumerator: rowsEnum)
            } else {
                rows = nil;
            }
            block(LiveQueryChange(query: self, rows: rows, error: change.error))
        }
    }
    
    /** Removes a change listener. The given change listener is the opaque object
        returned by the addChangeListener() method.
        @param listener The listener object to be removed. */
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
