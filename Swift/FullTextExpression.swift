//
//  FullTextExpression.swift
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

/// Full-text expression.
public protocol FullTextExpressionProtocol {
    /// Creates a Full-text match expression with the given search text.
    ///
    /// - Parameter text: The query string.
    /// - Returns: The full-text match expression.
    func match(_ query: String) -> ExpressionProtocol
}

/// Full-text expression factory.
public final class FullTextExpression {
    
    /// Creates a Full-text expression with the given full-text index name.
    ///
    /// - Parameter name: The full-text index name.
    /// - Returns: The FullTextExpression.
    public static func index(_ name: String) -> FullTextExpressionProtocol {
        return FullTextQueryExpression(withName: name)
    }
    
}

/* Internal */ class FullTextQueryExpression: FullTextExpressionProtocol {
    
    public func match(_ query: String) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFullTextExpression.index(withName: self.name).match(query))
    }
    
    // MARK: Internal
    
    let name: String
    
    init(withName name: String) {
        self.name = name
    }
    
}
