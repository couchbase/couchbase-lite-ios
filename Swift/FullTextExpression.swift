//
//  FullTextExpression.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 11/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// Full-text expression.
public final class FullTextExpression {
    
    /// Creates a Full-text expression with the given full-text index name.
    ///
    /// - Parameter name: The full-text index name.
    /// - Returns: The FullTextExpression.
    public static func index(_ name: String) -> FullTextExpression {
        return FullTextExpression(withName: name)
    }
    
    
    /// Creates a Full-text match expression with the given search text.
    ///
    /// - Parameter text: The query string.
    /// - Returns: The full-text match expression.
    public func match(_ query: String) -> Expression {
        return Expression(CBLQueryFullTextExpression.index(withName: self.name).match(query))
    }
    
    
    // MARK: Internal
    
    
    let name: String
    
    init(withName name: String) {
        self.name = name
    }
    
}
