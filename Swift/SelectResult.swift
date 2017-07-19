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
    
    /** Create a SelectResult object with the given expression. 
        @param expression   The expression.
        @return A SelectResult object. */
    public static func expression(_ expression: Expression) -> As {
        return As(expression: expression, alias: nil)
    }
    
    public class As: SelectResult {
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
