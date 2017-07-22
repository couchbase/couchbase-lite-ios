//
//  SelectResult.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** SelectResult represents a signle return value of the query statement. */
public class SelectResult {
    
    /** Creates a SelectResult.As object with the given expression.
        @param expression   The expression.
        @return A SelectResult.As object. */
    public static func expression(_ expression: Expression) -> As {
        return As(expression: expression, alias: nil)
    }
    
    /** SelectResult.As is a SelectResult that you can specified an alias name to it. The
        alias name can be used as the key for accessing the result value from the query Result
        object. */
    public class As: SelectResult {
        /** Specifies the alias name to the SelectResult object. 
            @param alias   The alias name.
            @return A SelectResult object with the alias name specified. */
        public func `as`(_ alias: String) -> SelectResult {
            return SelectResult(expression: self.expression, alias: alias)
        }
    }
    
    // MARK: Internal
    
    let expression: Expression
    
    var alias: String?
    
    var impl: CBLQuerySelectResult {
        return CBLQuerySelectResult.expression(expression.impl, as: alias)
    }
    
    init(expression: Expression, alias: String?) {
        self.expression = expression
        self.alias = alias
    }
    
    static func toImpl(results: [SelectResult]) -> [CBLQuerySelectResult] {
        var impls: [CBLQuerySelectResult] = []
        for r in results {
            impls.append(r.impl)
        }
        return impls;
    }
    
}
