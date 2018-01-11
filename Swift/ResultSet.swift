//
//  ResultSet.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// ResultSet is a result returned from a query.
public final class ResultSet : Sequence, IteratorProtocol {
    
    /// The Element.
    public typealias Element = Result
    
    /// Advances to the next result row and returns the advanced result row.
    ///
    /// - Returns: The advanced Result object.
    public func next() -> Result? {
        if let r = impl.nextObject() as? CBLQueryResult {
            return Result(impl: r)
        } else {
            return nil
        }
    }
    
    // MARK: Internal
    
    private let impl: CBLQueryResultSet
    
    init(impl: CBLQueryResultSet) {
        self.impl = impl
    }
    
}
