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
    public func satisfies(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        let impl = ArrayExpressionSatisfies.toImpl(
            type: self.type,
            variable: self.variable,
            inExpression: self.inExpression,
            satisfies: expression)
        return QueryExpression(impl)
    }
    
    // MARK: Internal
    
    let type: QuantifiesType
    
    let variable: VariableExpressionProtocol
    
    let inExpression: ExpressionProtocol
    
    init(type: QuantifiesType, variable: VariableExpressionProtocol, inExpression: ExpressionProtocol) {
        self.type = type
        self.variable = variable
        self.inExpression = inExpression
    }
    
    static func toImpl(type: QuantifiesType,
                       variable: VariableExpressionProtocol,
                       inExpression: ExpressionProtocol,
                       satisfies: ExpressionProtocol) -> CBLQueryExpression
    {
        let v = variable.toImpl() as! CBLQueryVariableExpression
        let i = inExpression.toImpl()
        let s = satisfies.toImpl()
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
