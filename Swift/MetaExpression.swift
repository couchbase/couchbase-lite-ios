//
//  MetaExpression.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A meta property expression. */
public class MetaExpression: Expression {
    
    /** Specifies an alias name of the data source to query the data from. */
    public func from(_ alias: String) -> Expression {
        return Expression(CBLQueryExpression.property(property, from: alias))
    }
    
    // MARK: Internal
    
    let property: String
    
    init(property: String) {
        self.property = property
        super.init(CBLQueryExpression.property(property))
    }
    
}
