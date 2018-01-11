//
//  ArrayFunction.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 11/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// Function provies array functions.
public final class ArrayFunction {
    
    /// Creates an ARRAY_CONTAINS(expr, value) function that checks whether the given array
    /// expression contains the given value or not.
    ///
    /// - Parameters:
    ///   - expression: The expression that evluates to an array.
    ///   - value: The value to search for in the given array expression.
    /// - Returns: The ARRAY_CONTAINS(expr, value) function.
    public static func contains(_ expression: Any, value: Any?) -> Expression {
        return Expression(CBLQueryArrayFunction.contains(
            Expression.toImpl(expression), value: Expression.toImpl(value ?? NSNull())))
    }
    
    
    /// Creates an ARRAY_LENGTH(expr) function that returns the length of the given array
    /// expression.
    ///
    /// - Parameter expression: The expression that evluates to an array.
    /// - Returns: The ARRAY_LENGTH(expr) function.
    public static func length(_ expression: Any) -> Expression {
        return Expression(CBLQueryArrayFunction.length(Expression.toImpl(expression)))
    }
    
}
