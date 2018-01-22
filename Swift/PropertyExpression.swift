//
//  PropertyExpression.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// Property expression.
public protocol PropertyExpressionProtocol: ExpressionProtocol {
    
    /// Specifies an alias name of the data source to query the data from.
    ///
    /// - Parameter alias: The alias name of the data source.
    /// - Returns: The property expression with the given data source alias name.
    func from(_ alias: String?) -> ExpressionProtocol
    
}

/* internal */ class PropertyExpression: QueryExpression, PropertyExpressionProtocol {

    public func from(_ alias: String?) -> ExpressionProtocol {
        if let prop = self.property {
            return QueryExpression(CBLQueryExpression.property(prop, from: alias))
        } else {
            return QueryExpression(CBLQueryExpression.all(from: alias))
        }
    }
    
    // Internal
    
    let property: String?
    
    init(property: String?) {
        self.property = property
        if let prop = property {
            super.init(CBLQueryExpression.property(prop))
        } else {
            super.init(CBLQueryExpression.all())
        }
    }
    
}
