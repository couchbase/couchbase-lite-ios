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
public class ArrayExpressionSatisfies {
    
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
    let variable: String
    let inExpression: Any
    
    init(type: QuantifiesType, variable: String, inExpression: Any) {
        self.type = type
        self.variable = variable
        self.inExpression = inExpression
    }
    
    static func toImpl(type: QuantifiesType, variable: String, inExpression: Any,
                       satisfies: Expression) -> CBLQueryExpression
    {
        let inImpl = Expression.toImpl(inExpression)
        let satisfiesImpl = satisfies.impl
        switch type {
        case .any:
            return CBLQueryArrayExpression.any(variable, in: inImpl, satisfies: satisfiesImpl)
        case .anyAndEvery:
            return CBLQueryArrayExpression.anyAndEvery(variable, in: inImpl, satisfies: satisfiesImpl)
        case .every:
            return CBLQueryArrayExpression.every(variable, in: inImpl, satisfies: satisfiesImpl)
        }
    }
    
}
