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
    public static func expression(_ expression: Expression) -> SelectResult {
        let result = CBLQuerySelectResult.expression(expression.impl)
        return SelectResult(impl: result)
    }
    
    // MARK: Internal
    
    let impl: CBLQuerySelectResult
    
    init(impl: CBLQuerySelectResult) {
        self.impl = impl
    }
    
    static func toImpl(results: [SelectResult]) -> [CBLQuerySelectResult] {
        var impls: [CBLQuerySelectResult] = []
        for r in results {
            impls.append(r.impl)
        }
        return impls;
    }
    
}

// TODO:
// * Support Alias
// * Support From Alias
