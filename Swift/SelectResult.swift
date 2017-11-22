//
//  SelectResult.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// SelectResult represents a signle return value of the query statement.
public class SelectResult {
    
    /// Creates a SelectResult object with the given property name.
    ///
    /// - Parameter property: The property name.
    /// - Returns: The SelectResult.As object that you can give the alias name to
    ///            the returned value.
    public static func property(_ property: String) -> As {
        return As(expression: Expression.property(property), alias: nil, from: nil)
    }
    
    /// Creates a SelectResult object with the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The SelectResult.As object that you can give the alias name to
    ///            the returned value.
    public static func expression(_ expression: Expression) -> As {
        return As(expression: expression, alias: nil, from: nil)
    }
    
    
    /// Creates a SelectResult object that returns all properties data. The query returned result
    /// will be grouped into a single CBLMutableDictionary object under the key of the data source name.
    ///
    /// - Returns: The SelectResult.From object that you can specify the data source alias name.
    public static func all() -> From {
        return From(expression: nil, alias: nil, from: nil)

    }
    
    
    /// SelectResult.As is a SelectResult that you can specify an alias name to it. The
    /// alias name can be used as the key for accessing the result value from the query Result
    /// object.
    public final class As: SelectResult {
        
        /// Specifies the alias name to the SelectResult object.
        ///
        /// - Parameter alias: The alias name.
        /// - Returns: The SelectResult object with the alias name specified.
        public func `as`(_ alias: String) -> SelectResult {
            return SelectResult(expression: self.expression, alias: alias, from: nil)
        }
        
    }
    
    
    /// SelectResult.From is a SelectResult that you can specify the data source alias name.
    public final class From: SelectResult {
        
        /// Species the data source alias name to the SelectResult object.
        ///
        /// - Parameter alias: The data source alias name.
        /// - Returns: The SelectResult object with the data source alias name specified.
        public func from(_ alias: String) -> SelectResult {
            return SelectResult(expression: nil, alias: nil, from: alias)
        }
        
    }
    
    // MARK: Internal
    
    let expression: Expression?
    
    let alias: String?
    
    let from: String?
    
    var impl: CBLQuerySelectResult {
        if let expr = expression {
            return CBLQuerySelectResult.expression(expr.impl, as: alias)
        } else {
            // expression == nil means SELECT *
            return CBLQuerySelectResult.all(from: from)
        }
    }
    
    init(expression: Expression?, alias: String?, from: String?) {
        self.expression = expression
        self.alias = alias
        self.from = from
    }
    
    static func toImpl(results: [SelectResult]) -> [CBLQuerySelectResult] {
        var impls: [CBLQuerySelectResult] = []
        for r in results {
            impls.append(r.impl)
        }
        return impls;
    }
    
}
