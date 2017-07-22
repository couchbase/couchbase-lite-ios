//
//  ResultSet.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** ResultSet is a result returned from a query. */
public class ResultSet : Sequence, IteratorProtocol {
    public typealias Element = Result
    
    /** Advances to and return the next result row.
        @return A Result object. */
    public func next() -> Result? {
        if let row = impl.nextObject() as? CBLQueryResult {
            return Result(impl: row)
        } else {
            return nil
        }
    }
    
    private let impl: CBLQueryResultSet
    
    init(impl: CBLQueryResultSet) {
        self.impl = impl
    }
}
