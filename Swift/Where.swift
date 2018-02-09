//
//  Where.swift
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

/// Where class represents the WHERE clause of the query statement.
public final class Where: Query, GroupByRouter, OrderByRouter, LimitRouter {
    
    /// Create and chain an ORDER BY component for specifying the orderings of the query result.
    ///
    /// - Parameter orderings: The ordering objects.
    /// - Returns: The OrderBy object.
    public func orderBy(_ orderings: OrderingProtocol...) -> OrderBy {
        return OrderBy(query: self, impl: QueryOrdering.toImpl(orderings: orderings))
    }
    
    
    /// Create and chain a GROUP BY component to group the query result.
    ///
    /// - Parameter expressions: The expression objects.
    /// - Returns: The GroupBy object.
    public func groupBy(_ expressions: ExpressionProtocol...) -> GroupBy {
        return GroupBy(query: self, impl: QueryExpression.toImpl(expressions: expressions))
    }
    
    
    /// Create and chain a LIMIT component to limit the number query results.
    ///
    /// - Parameter limit: The limit Expression object or liternal value.
    /// - Returns: The Limit object.
    public func limit(_ limit: ExpressionProtocol) -> Limit {
        return self.limit(limit, offset: nil)
    }
    
    
    /// Create and chain a LIMIT component to skip the returned results for the given offset
    /// position and to limit the number of results to not more than the given limit value.
    ///
    /// - Parameters:
    ///   - limit: The limit Expression object or liternal value.
    ///   - offset: The offset Expression object or liternal value.
    /// - Returns: The Limit object.
    public func limit(_ limit: ExpressionProtocol, offset: ExpressionProtocol?) -> Limit {
        return Limit(query: self, limit: limit, offset: offset)
    }
    
    
    /// An internal constructor.
    init(query: Query, impl: CBLQueryExpression) {
        super.init()
        
        self.copy(query)
        self.whereImpl = impl
    }
    
}
