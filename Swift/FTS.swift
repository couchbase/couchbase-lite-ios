//
//  FTS.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// FTS is a factory class for creating the full-text search related expressions.
public class FTS {
    
    /// Creates a full text search ranking value expression with the given property name.
    ///
    /// - Parameter property: The property name in the key path format.
    /// - Returns: The ranking value expression.
    public func rank(_ property: String) -> RankExpression {
        return RankExpression(property: property)
    }
}


/// FTS ranking value expression that indicates how well the current query result
/// matches the full-text query.
public class RankExpression: Expression {
    /// Specifies an alias name of the data source to query the data from.
    ///
    /// - Parameter alias: The alias name of the data source.
    /// - Returns: The FTS rank expression with the given data source alias name.
    public func from(_ alias: String) -> Expression {
        return Expression(CBLQueryExpression.property(property, from: alias))
    }
    
    // Internal
    
    let property: String
    
    init(property: String) {
        self.property = property
        super.init(CBLQueryExpression.property(property))
    }
}
