//
//  FullTextFunction.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 11/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// Full-text function factory.
public final class FullTextFunction {
    
    /// Creates a full-text rank function with the given full-text index name.
    /// The rank function indicates how well the current query result matches
    /// the full-text query when performing the match comparison.
    ///
    /// - Parameter indexName: The index name.
    /// - Returns: The full-text rank function.
    public static func rank(_ indexName: String) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFullTextFunction.rank(indexName))
    }
    
}
