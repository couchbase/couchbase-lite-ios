//
//  Satisfies.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/* internal */ enum QuantifiesType {
    case any, anyAndEvery, every
}


/// The Satisfies class represents the SATISFIES clause object in a quantified operator
/// (ANY/ANY AND EVERY/EVERY <variable name> IN <expr> SATISFIES <expr>). The SATISFIES clause 
/// is used for specifying an expression that will be used to evaluate each item in the array.
public final class ArrayExpressionSatisfies {
    
    /// Creates a complete quantified operator with the given satisfies expression.
    ///
    /// - Parameter expression: The satisfies expression used for evaluating each item in the array.
    /// - Returns: The quantified expression.
    public func satisfies(_ expression: Expression) -> Expression {
        let impl = ArrayExpressionSatisfies.toImpl(
            type: self.type,
            variable: self.variable,
            inExpression: self.inExpression,
            satisfies: expression)
        return Expression(impl)
    }
    
    // MARK: Internal
    
    let type: QuantifiesType
    let variable: VariableExpression
    let inExpression: Expression
    
    init(type: QuantifiesType, variable: VariableExpression, inExpression: Expression) {
        self.type = type
        self.variable = variable
        self.inExpression = inExpression
    }
    
    static func toImpl(type: QuantifiesType,
                       variable: VariableExpression,
                       inExpression: Expression,
                       satisfies: Expression) -> CBLQueryExpression
    {
        let v = variable.impl as! CBLQueryVariableExpression
        let i = inExpression.impl
        let s = satisfies.impl
        switch type {
        case .any:
            return CBLQueryArrayExpression.any(v, in: i, satisfies: s)
        case .anyAndEvery:
            return CBLQueryArrayExpression.anyAndEvery(v, in: i, satisfies: s)
        case .every:
            return CBLQueryArrayExpression.every(v, in: i, satisfies: s)
        }
    }
    
}
