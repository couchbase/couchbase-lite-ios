//
//  OrderBy.swift
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


/// An OrderBy represents an ORDER BY clause of the query statement.
public final class OrderBy: Query, LimitRouter {
    
    /// Creates and chains a Limit object to limit the number query results.
    ///
    /// - Parameter limit: The limit expression.
    /// - Returns: The Limit object that represents the LIMIT clause of the query.
    public func limit(_ limit: ExpressionProtocol) -> Limit {
        return self.limit(limit, offset: nil)
    }
    
    
    ///  Creates and chains a Limit object to skip the returned results for the given offset
    ///  position and to limit the number of results to not more than the given limit value.
    ///
    /// - Parameters:
    ///   - limit: The limit expression.
    ///   - offset: The offset expression.
    /// - Returns: The Limit object that represents the LIMIT clause of the query.
    public func limit(_ limit: ExpressionProtocol, offset: ExpressionProtocol?) -> Limit {
        return Limit(query: self, limit: limit, offset: offset)
    }
    
    // MARK: Internal
    
    init(query: Query, impl: [CBLQueryOrdering]) {
        super.init()
        self.copy(query)
        self.orderingsImpl = impl
    }
    
}
