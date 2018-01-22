//
//  ArrayExpression.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// Array expression.
public final class ArrayExpression {
    /// Creates a variable expression that represents an item in the array
    /// expression (ANY/ANY AND EVERY/EVERY <variable> IN <expr> SATISFIES <expr>).
    ///
    /// - Parameter name: The variable name.
    /// - Returns: A variable expression.
    public static func variable(_ name: String) -> VariableExpressionProtocol {
        return VariableExpression(name: name)
    }
    
    
    /// Creates an ANY Quantified operator (ANY <variable name> IN <expr> SATISFIES <expr>)
    /// with the given variable name. The method returns an IN clause object that is used for
    /// specifying an array object or an expression evaluated as an array object, each item of
    /// which will be evaluated against the satisfies expression.
    /// The ANY operator returns TRUE if at least one of the items in the array satisfies the given
    /// satisfies expression.
    ///
    /// - Parameter variable: The variable expression.
    /// - Returns: An IN expression.
    public static func any(_ variable: VariableExpressionProtocol) -> ArrayExpressionIn {
        return ArrayExpressionIn(type: .any, variable: variable)
    }
    
    /// Creates an EVERY Quantified operator (EVERY <variable name> IN <expr> SATISFIES <expr>)
    /// with the given variable name. The method returns an IN clause object
    /// that is used for specifying an array object or an expression evaluated as an array object,
    /// each of which will be evaluated against the satisfies expression.
    /// The EVERY operator returns TRUE if the array is empty OR every item in the array
    /// satisfies the given satisfies expression.
    ///
    /// - Parameter variable: The variable expression.
    /// - Returns: An IN expression.
    public static func every(_ variable: VariableExpressionProtocol) -> ArrayExpressionIn {
        return ArrayExpressionIn(type: .every, variable: variable)
    }
    
    /// Creates an ANY AND EVERY Quantified operator (ANY AND EVERY <variable name> IN <expr>
    /// SATISFIES <expr>) with the given variable name. The method returns an IN clause object
    /// that is used for specifying an array object or an expression evaluated as an array object,
    /// each of which will be evaluated against the satisfies expression.
    /// The ANY AND EVERY operator returns TRUE if the array is NOT empty, and at least one of
    /// the items in the array satisfies the given satisfies expression.
    ///
    /// - Parameter variable: The variable expression.
    /// - Returns: An IN object.
    public static func anyAndEvery(_ variable: VariableExpressionProtocol) -> ArrayExpressionIn {
        return ArrayExpressionIn(type: .anyAndEvery, variable: variable)
    }
}
