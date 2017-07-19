//
//  ResultSet.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

public struct ResultSet : Sequence, IteratorProtocol {
    public typealias Element = Result
    
    public mutating func next() -> Result? {
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
