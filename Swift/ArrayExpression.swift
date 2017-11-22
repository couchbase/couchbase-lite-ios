//
//  ArrayExpression.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// Array expression.
public class ArrayExpression {
    /// Creates a variable expression. The variable are used to represent each item in an array
    /// in the quantified operators (ANY/ANY AND EVERY/EVERY <variable name> IN <expr> SATISFIES <expr>)
    /// to evaluate expressions over an array.
    ///
    /// - Parameter name: The variable name.
    /// - Returns: A variable expression.
    public static func variable(_ name: String) -> Expression {
        return Expression.init(CBLQueryArrayExpression.variableNamed(name))
    }
    
    
    /// Creates an ANY Quantified operator (ANY <variable name> IN <expr> SATISFIES <expr>)
    /// with the given variable name. The method returns an IN clause object that is used for
    /// specifying an array object or an expression evaluated as an array object, each item of
    /// which will be evaluated against the satisfies expression.
    /// The ANY operator returns TRUE if at least one of the items in the array satisfies the given
    /// satisfies expression.
    ///
    /// - Parameter variable: The variable name.
    /// - Returns: An In object.
    public static func any(_ variable: String) -> ArrayExpressionIn {
        return ArrayExpressionIn(type: .any, variable: variable)
    }
    
    
    /// Creates an ANY AND EVERY Quantified operator (ANY AND EVERY <variable name> IN <expr>
    /// SATISFIES <expr>) with the given variable name. The method returns an IN clause object
    /// that is used for specifying an array object or an expression evaluated as an array object,
    /// each of which will be evaluated against the satisfies expression.
    /// The ANY AND EVERY operator returns TRUE if the array is NOT empty, and at least one of
    /// the items in the array satisfies the given satisfies expression.
    ///
    /// - Parameter variable: The variable name.
    /// - Returns: An In object.
    public static func anyAndEvery(_ variable: String) -> ArrayExpressionIn {
        return ArrayExpressionIn(type: .anyAndEvery, variable: variable)
    }
    
    
    /// Creates an EVERY Quantified operator (EVERY <variable name> IN <expr> SATISFIES <expr>)
    /// with the given variable name. The method returns an IN clause object
    /// that is used for specifying an array object or an expression evaluated as an array object,
    /// each of which will be evaluated against the satisfies expression.
    /// The EVERY operator returns TRUE if the array is empty OR every item in the array
    /// satisfies the given satisfies expression.
    ///
    /// - Parameter variable: The variable name.
    /// - Returns: An In object.
    public static func every(_ variable: String) -> ArrayExpressionIn {
        return ArrayExpressionIn(type: .every, variable: variable)
    }
}
