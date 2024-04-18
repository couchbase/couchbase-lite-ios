//
//  FullTextFunction.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import CouchbaseLiteSwift_Private

/// Full-text function factory.
public final class FullTextFunction {
    
    /// Creates a full-text rank function with the given full-text index name.
    /// The rank function indicates how well the current query result matches
    /// the full-text query when performing the match comparison.
    ///
    /// - Parameter indexName: The index name.
    /// - Returns: The full-text rank function.
    @available(*, deprecated, message: "Use FullTextFunction.rank(withIndex:) instead.")
    public static func rank(_ indexName: String) -> ExpressionProtocol {
        return rank(Expression.fullTextIndex(indexName))
    }
    
    /// Creates a full-text match expression with the given full-text index name and the query text
    ///
    /// - Parameter indexName: The index name.
    /// - Parameter query: The query string.
    /// - Returns: The full-text match function expression.
    @available(*, deprecated, message: "Use FullTextFunction.match(withIndex:query) instead.")
    public static func match(indexName: String, query: String) -> ExpressionProtocol {
        return match(Expression.fullTextIndex(indexName), query: query)
    }
    
    /// Creates a full-text rank() function with the given full-text index expression.
    ///
    /// The rank function indicates how well the current query result matches
    /// the full-text query when performing the match comparison.
    ///
    /// - Parameter index: The full-text index expression.
    /// - Returns: The full-text rank function.
    public static func rank(_ index: IndexExpressionProtocol) -> ExpressionProtocol {
        guard let i = index as? FullTextIndexExpression else {
            fatalError("This scenario shouldn't happen! IndexExpProtocol only implemented on FullTextIndexExpression")
        }
        
        return QueryExpression(CBLQueryFullTextFunction.rank(withIndex: i.toImpl()))
    }
    
    ///  Creates a full-text match() function  with the given full-text index expression and the query text
    ///
    /// - Parameter index: The full-text index expression.
    /// - Parameter query: The query string.
    /// - Returns: The full-text match() function expression.
    public static func match(_ index: IndexExpressionProtocol, query: String) -> ExpressionProtocol {
        guard let i = index as? FullTextIndexExpression else {
            fatalError("This scenario shouldn't happen! IndexExpProtocol only implemented on FullTextIndexExpression")
        }
        
        return QueryExpression(CBLQueryFullTextFunction.match(withIndex: i.toImpl(), query: query))
    }
}
