//
//  In.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// The In class represents the IN clause object in a quantified operator (ANY/ANY AND EVERY/EVERY
/// <variable name> IN <expr> SATISFIES <expr>). The IN clause is used for specifying an array
/// object or an expression evaluated as an array object, each item of which will be evaluated
/// against the satisfies expression.
public class In {
    
    /// Creates a Satisfies clause object with the given IN clause expression that could be an
    /// array object or an expression evaluated as an array object.
    ///
    /// - Parameter expression: The array object or the expression evaluated as an array object.
    /// - Returns: A Satisfies object.
    public func `in`(_ expression: Any) -> Satisfies {
        return Satisfies(type: self.type, variable: self.variable, inExpression: expression)
    }
    
    
    // MARK: Internal
    
    
    let type: QuantifiesType
    let variable: String
    
    init(type: QuantifiesType, variable: String) {
        self.type = type
        self.variable = variable
    }

}
