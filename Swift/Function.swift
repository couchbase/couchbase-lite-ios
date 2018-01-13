//
//  Function.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// Function provies query functions.
public final class Function {
    
    // MARK: Aggregation
    
    
    /// Create an AVG(expr) function expression that returns the average of all the number values
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The AVG(expr) function.
    public static func avg(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.avg(expression.impl))
    }
    
    
    /// Create a COUNT(expr) function expression that returns the count of all values
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The COUNT(expr) function.
    public static func count(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.count(expression.impl))
    }
    
    
    /// Create a MIN(expr) function expression that returns the minimum value
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The MIN(expr) function.
    public static func min(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.min(expression.impl))
    }
    
    
    /// Create a MAX(expr) function expression that returns the maximum value
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The MAX(expr) function.
    public static func max(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.max(expression.impl))
    }
    
    
    /// Create a SUM(expr) function expression that return the sum of all number values
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The SUM(expr) function.
    public static func sum(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.sum(expression.impl))
    }
    
    
    // MARK: Mathematics
    
    
    /// Creates an ABS(expr) function that returns the absolute value of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ABS(expr) function.
    public static func abs(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.abs(expression.impl))
    }
    
    
    /// Creates an ACOS(expr) function that returns the inverse cosine of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ACOS(expr) function.
    public static func acos(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.acos(expression.impl))
    }
    
    
    /// Creates an ASIN(expr) function that returns the inverse sin of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ASIN(expr) function.
    public static func asin(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.asin(expression.impl))
    }
    
    
    /// Creates an ATAN(expr) function that returns the inverse tangent of the numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ATAN(expr) function.
    public static func atan(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.atan(expression.impl))
    }
    
    
    /// Creates an ATAN2(X, Y) function that returns the arctangent of y/x.
    ///
    /// - Parameters:
    ///   - x: The expression to evaluate as the X coordinate.
    ///   - y: The expression to evaluate as the Y coordinate.
    /// - Returns: The ATAN2(X, Y) function.
    public static func atan2(x: Expression, y: Expression) -> Expression {
        return Expression(CBLQueryFunction.atan2(x.impl, y: y.impl))
    }
    
    
    /// Creates a CEIL(expr) function that returns the ceiling value of the given numeric
    /// expression
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The CEIL(expr) function.
    public static func ceil(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.ceil(expression.impl))
    }
    

    /// Creates a COS(expr) function that returns the cosine of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The COS(expr) function.
    public static func cos(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.cos(expression.impl))
    }
    
    
    /// Creates a DEGREES(expr) function that returns the degrees value of the given radiants
    /// value expression.
    ///
    /// - Parameter expression: The numeric expression to evaluate as a radiants value.
    /// - Returns: The DEGREES(expr) function.
    public static func degrees(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.degrees(expression.impl))
    }

    
    /// Creates a E() function that return the value of the mathemetical constant 'e'.
    ///
    /// - Returns: The E() constant function.
    public static func e() -> Expression {
        return Expression(CBLQueryFunction.e())
    }
    
    
    /// Creates a EXP(expr) function that returns the value of 'e' power by the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The EXP(expr) function.
    public static func exp(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.exp(expression.impl))
    }
    
    
    /// Creates a FLOOR(expr) function that returns the floor value of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The FLOOR(expr) function.
    public static func floor(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.floor(expression.impl))
    }
    
    
    /// Creates a LN(expr) function that returns the natural log of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The LN(expr) function.
    public static func ln(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.ln(expression.impl))
    }
    
    
    /// Creates a LOG(expr) function that returns the base 10 log of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The LOG(expr) function.
    public static func log(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.log(expression.impl))
    }

    
    /// Creates a PI() function that returns the mathemetical constant Pi.
    ///
    /// - Returns: The PI() constant function.
    public static func pi() -> Expression {
        return Expression(CBLQueryFunction.pi())
    }

    
    /// Creates a POWER(base, exponent) function that returns the value of the given base
    /// expression power the given exponent expression.
    ///
    /// - Parameters:
    ///   - base: The base expression.
    ///   - exponent: The exponent expression.
    /// - Returns: The POWER(base, exponent) function.
    public static func power(base: Expression, exponent: Expression) -> Expression {
        return Expression(CBLQueryFunction.power(base.impl, exponent: exponent.impl))
    }
    
    
    /// Creates a RADIANS(expr) function that returns the radians value of the given degrees
    /// value expression.
    ///
    /// - Parameter expression: The numeric expression to evaluate as a degrees value.
    /// - Returns: The RADIANS(expr) function.
    public static func radians(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.radians(expression.impl))
    }
    
    
    /// Creates a ROUND(expr) function that returns the rounded value of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ROUND(expr) function.
    public static func round(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.round(expression.impl))
    }

    
    /// Creates a ROUND(expr, digits) function that returns the rounded value to the given
    /// number of digits of the given numeric expression.
    ///
    /// - Parameters:
    ///   - expression: The numeric expression.
    ///   - digits: The number of digits.
    /// - Returns: The ROUND(expr, digits) function.
    public static func round(_ expression: Expression, digits: Expression) -> Expression {
        return Expression(CBLQueryFunction.round(expression.impl, digits: digits.impl))
    }
    
    
    /// Creates a SIGN(expr) function that returns the sign (1: positive, -1: negative, 0: zero)
    /// of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The SIGN(expr) function.
    public static func sign(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.sign(expression.impl))
    }
    
    
    /// Creates a SIN(expr) function that returns the sin of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The SIN(expr) function.
    public static func sin(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.sin(expression.impl))
    }
    
    
    /// Creates a SQRT(expr) function that returns the square root of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The SQRT(expr) function.
    public static func sqrt(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.sqrt(expression.impl))
    }

    
    /// Creates a TAN(expr) function that returns the tangent of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns:  The TAN(expr) function.
    public static func tan(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.tan(expression.impl))
    }
    
    
    /// Creates a TRUNC(expr) function that truncates all of the digits after the decimal place
    /// of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The trunc function.
    public static func trunc(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.trunc(expression.impl))
    }
    
    
    /// Creates a TRUNC(expr, digits) function that truncates the number of the digits after
    /// the decimal place of the given numeric expression.
    ///
    /// - Parameters:
    ///   - expression: The numeric expression.
    ///   - digits: The number of digits to truncate.
    /// - Returns: The TRUNC(expr, digits) function.
    public static func trunc(_ expression: Expression, digits: Expression) -> Expression {
        return Expression(CBLQueryFunction.trunc(expression.impl, digits: digits.impl))
    }
    
    
    // Mark: String
    
    
    /// Creates a CONTAINS(expr, substr) function that evaluates whether the given string
    /// expression conatins the given substring expression or not.
    ///
    /// - Parameters:
    ///   - expression: The string expression.
    ///   - substring: The substring expression.
    /// - Returns: The CONTAINS(expr, substr) function.
    public static func contains(_ expression: Expression, substring: Expression) -> Expression {
        return Expression(CBLQueryFunction.contains(expression.impl, substring: substring.impl))
    }
    
    
    /// Creates a LENGTH(expr) function that returns the length of the given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The LENGTH(expr) function.
    public static func length(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.length(expression.impl))
    }
    
    
    /// Creates a LOWER(expr) function that returns the lowercase string of the given string
    /// expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The LOWER(expr) function.
    public static func lower(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.lower(expression.impl))
    }
    
    
    /// Creates a LTRIM(expr) function that removes the whitespace from the beginning of the
    /// given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The LTRIM(expr) function.
    public static func ltrim(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.ltrim(expression.impl))
    }
    
    
    /// Creates a RTRIM(expr) function that removes the whitespace from the end of the
    /// given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The RTRIM(expr) function.
    public static func rtrim(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.rtrim(expression.impl))
    }
    
    
    /// Creates a TRIM(expr) function that removes the whitespace from the beginning and '
    /// the end of the given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The TRIM(expr) function.
    public static func trim(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.trim(expression.impl))
    }
    
    
    /// Creates a UPPER(expr) function that returns the uppercase string of the given string
    /// expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The UPPER(expr) function.
    public static func upper(_ expression: Expression) -> Expression {
        return Expression(CBLQueryFunction.upper(expression.impl))
    }
    
}
