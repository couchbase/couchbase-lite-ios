//
//  LiveQuery.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A LiveQuery automatically observes database changes and re-run the query that the LiveQuery
/// object is created from. If there is a new query result or an error occurred, the LiveQuery object
/// will report the changed result via the added listener blocks.
public class LiveQuery {
    
    /// Returns the Parameters object used for setting values to the query parameters defined
    /// in the query. All parameters defined in the query must be given values
    /// before running the query, or the query will fail.
    public var parameters: Parameters {
        if params == nil {
            params = Parameters(params: nil)
        }
        return params!
    }

    
    ///  Starts observing database changes and reports changes in the query result.
    public func start() {
        applyParameters()
        impl.start()
    }
    
    
    /// Stops observing database changes.
    public func stop() {
        impl.stop()
    }
    
    
    /// Returns a string describing the implementation of the compiled query.
    /// This is intended to be read by a developer for purposes of optimizing the query, especially
    /// to add database indexes. It's not machine-readable and its format may change.
    ///
    /// - Returns: The implementation detail of the compiled query.
    /// - Throws: An error if the query is invalid.
    public func explain() throws -> String {
        return try impl.explain()
    }
    
    
    /// Adds a query change listener block.
    ///
    /// - Parameter block: The block to be executed when the change is received.
    /// - Returns: An opaque object to act as the listener and for removing the listener
    ///            when calling the removeChangeListener() method.
    @discardableResult
    public func addChangeListener(_ block: @escaping (LiveQueryChange) -> Void) -> NSObjectProtocol {
        return impl.addChangeListener { [unowned self] change in
            let rows: ResultSet?;
            if let rs = change.rows {
                rows = ResultSet(impl: rs)
            } else {
                rows = nil;
            }
            block(LiveQueryChange(query: self, rows: rows, error: change.error))
        }
    }
    
    
    /// Removes a change listener. The given change listener is the opaque object
    /// returned by the addChangeListener() method.
    ///
    /// - Parameter listener: The listener object to be removed.
    public func removeChangeListener(_ listener: NSObjectProtocol) {
        impl.removeChangeListener(listener)
    }
    
    
    // MARK: Internal
    
    
    let impl: CBLLiveQuery
    
    let database: Database
    
    var params: Parameters?
    
    init(database: Database, impl: CBLLiveQuery, params: Parameters?) {
        self.impl = impl
        self.database = database
        self.params = params?.copy()
    }
    
    func applyParameters() {
        if let p = self.params, let paramDict = p.params {
            for (name, value) in paramDict {
                impl.parameters.setObject(value, forName: name)
            }
        }
    }
}


extension LiveQuery: CustomStringConvertible {
    
    public var description: String {
        return "\(type(of: self))[\(self.impl.description)]"
    }
    
}
