//
//  SelectResult.swift
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

/// SelectResult represents a signle return value of the query statement.
public protocol SelectResultProtocol {
    
}

/// SelectResult with the aliasing function. The alias name can be used as
/// the key for accessing the result value from the query Result object.
public protocol SelectResultAs: SelectResultProtocol {
    /// Specifies the alias name to the SelectResult object.
    ///
    /// - Parameter alias: The alias name.
    /// - Returns: The SelectResult object with the alias name specified.
    func `as`(_ alias: String?) -> SelectResultProtocol
}

/// SelectResult with the from function that you can specify the data source
/// alias name.
public protocol SelectResultFrom: SelectResultProtocol {
    /// Species the data source alias name to the SelectResult object.
    ///
    /// - Parameter alias: The data source alias name.
    /// - Returns: The SelectResult object with the data source alias name specified.
    func from(_ alias: String?) -> SelectResultProtocol
}

/// SelectResult factory.
public final class SelectResult {
    
    /// Creates a SelectResult object with the given property name.
    ///
    /// - Parameter property: The property name.
    /// - Returns: The SelectResult.As object that you can give the alias name to
    ///            the returned value.
    public static func property(_ property: String) -> SelectResultAs {
        return expression(Expression.property(property))
    }
    
    /// Creates a SelectResult object with the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The SelectResult.As object that you can give the alias name to
    ///            the returned value.
    public static func expression(_ expression: ExpressionProtocol) -> SelectResultAs {
        return QuerySelectResultAs(expression: expression, alias: nil)
    }
    
    
    /// Creates a SelectResult object that returns all properties data. The query returned result
    /// will be grouped into a single CBLMutableDictionary object under the key of the data source name.
    ///
    /// - Returns: The SelectResult.From object that you can specify the data source alias name.
    public static func all() -> SelectResultFrom {
        return QuerySelectResultFrom(expression: Expression.all(), alias: nil)

    }
    
}

/* internal */ class QuerySelectResult: SelectResultProtocol {
    let expression: ExpressionProtocol
    
    let alias: String?
    
    init(expression: ExpressionProtocol, alias: String?) {
        self.expression = expression
        self.alias = alias
    }
    
    func toImpl() -> CBLQuerySelectResult {
        return CBLQuerySelectResult.expression(expression.toImpl(), as: alias)
    }
    
    static func toImpl(results: [SelectResultProtocol]) -> [CBLQuerySelectResult] {
        var impls: [CBLQuerySelectResult] = []
        for r in results {
            impls.append(r.toImpl())
        }
        return impls;
    }
}

/* Internal */ class QuerySelectResultAs: QuerySelectResult, SelectResultAs {
    
    public func `as`(_ alias: String?) -> SelectResultProtocol {
        return QuerySelectResult(expression: self.expression, alias: alias)
    }
    
}

/* Internal */ class QuerySelectResultFrom: QuerySelectResult, SelectResultFrom {
    
    public func from(_ alias: String?) -> SelectResultProtocol {
        return QuerySelectResult(expression: Expression.all().from(alias), alias: alias)
    }
    
}

extension SelectResultProtocol {
    
    func toImpl() -> CBLQuerySelectResult {
        if let o = self as? QuerySelectResult {
            return o.toImpl()
        }
        fatalError("Unsupported select result.")
    }
    
}
