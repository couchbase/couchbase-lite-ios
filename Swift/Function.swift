//
//  Function.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// Function provies query functions.
public class Function {
    
    // MARK: Aggregation
    
    
    /// Create an AVG(expr) function expression that returns the average of all the number values
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The AVG(expr) function.
    public static func avg(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.avg(Expression.toImpl(expression)))
    }
    
    
    /// Create a COUNT(expr) function expression that returns the count of all values
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The COUNT(expr) function.
    public static func count(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.count(Expression.toImpl(expression)))
    }
    
    
    /// Create a MIN(expr) function expression that returns the minimum value
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The MIN(expr) function.
    public static func min(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.min(Expression.toImpl(expression)))
    }
    
    
    /// Create a MAX(expr) function expression that returns the maximum value
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The MAX(expr) function.
    public static func max(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.max(Expression.toImpl(expression)))
    }
    
    
    /// Create a SUM(expr) function expression that return the sum of all number values
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The SUM(expr) function.
    public static func sum(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.sum(Expression.toImpl(expression)))
    }
    
    
    // MARK: Mathematics
    
    
    /// Creates an ABS(expr) function that returns the absolute value of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ABS(expr) function.
    public static func abs(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.abs(Expression.toImpl(expression)))
    }
    
    
    /// Creates an ACOS(expr) function that returns the inverse cosine of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ACOS(expr) function.
    public static func acos(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.acos(Expression.toImpl(expression)))
    }
    
    
    /// Creates an ASIN(expr) function that returns the inverse sin of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ASIN(expr) function.
    public static func asin(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.asin(Expression.toImpl(expression)))
    }
    
    
    /// Creates an ATAN(expr) function that returns the inverse tangent of the numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ATAN(expr) function.
    public static func atan(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.atan(Expression.toImpl(expression)))
    }
    
    
    /// Creates an ATAN2(X, Y) function that returns the arctangent of y/x.
    ///
    /// - Parameters:
    ///   - x: The expression to evaluate as the X coordinate.
    ///   - y: The expression to evaluate as the Y coordinate.
    /// - Returns: The ATAN2(X, Y) function.
    public static func atan2(x: Any, y: Any) -> Expression {
        return Expression(CBLQueryFunction.atan2(Expression.toImpl(x), y: Expression.toImpl(y)))
    }
    
    
    /// Creates a CEIL(expr) function that returns the ceiling value of the given numeric
    /// expression
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The CEIL(expr) function.
    public static func ceil(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.ceil(Expression.toImpl(expression)))
    }
    

    /// Creates a COS(expr) function that returns the cosine of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The COS(expr) function.
    public static func cos(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.cos(Expression.toImpl(expression)))
    }
    
    
    /// Creates a DEGREES(expr) function that returns the degrees value of the given radiants
    /// value expression.
    ///
    /// - Parameter expression: The numeric expression to evaluate as a radiants value.
    /// - Returns: The DEGREES(expr) function.
    public static func degrees(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.degrees(Expression.toImpl(expression)))
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
    public static func exp(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.exp(Expression.toImpl(expression)))
    }
    
    
    /// Creates a FLOOR(expr) function that returns the floor value of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The FLOOR(expr) function.
    public static func floor(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.floor(Expression.toImpl(expression)))
    }
    
    
    /// Creates a LN(expr) function that returns the natural log of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The LN(expr) function.
    public static func ln(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.ln(Expression.toImpl(expression)))
    }
    
    
    /// Creates a LOG(expr) function that returns the base 10 log of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The LOG(expr) function.
    public static func log(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.log(Expression.toImpl(expression)))
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
    public static func power(base: Any, exponent: Any) -> Expression {
        return Expression(CBLQueryFunction.power(
            Expression.toImpl(base), exponent: Expression.toImpl(exponent)))
    }
    
    
    /// Creates a RADIANS(expr) function that returns the radians value of the given degrees
    /// value expression.
    ///
    /// - Parameter expression: The numeric expression to evaluate as a degrees value.
    /// - Returns: The RADIANS(expr) function.
    public static func radians(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.radians(Expression.toImpl(expression)))
    }
    
    
    /// Creates a ROUND(expr) function that returns the rounded value of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ROUND(expr) function.
    public static func round(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.round(Expression.toImpl(expression)))
    }

    
    /// Creates a ROUND(expr, digits) function that returns the rounded value to the given
    /// number of digits of the given numeric expression.
    ///
    /// - Parameters:
    ///   - expression: The numeric expression.
    ///   - digits: The number of digits.
    /// - Returns: The ROUND(expr, digits) function.
    public static func round(_ expression: Any, digits: Int) -> Expression {
        return Expression(CBLQueryFunction.round(Expression.toImpl(expression), digits: digits))
    }
    
    
    /// Creates a SIGN(expr) function that returns the sign (1: positive, -1: negative, 0: zero)
    /// of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The SIGN(expr) function.
    public static func sign(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.sign(Expression.toImpl(expression)))
    }
    
    
    /// Creates a SIN(expr) function that returns the sin of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The SIN(expr) function.
    public static func sin(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.sin(Expression.toImpl(expression)))
    }
    
    
    /// Creates a SQRT(expr) function that returns the square root of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The SQRT(expr) function.
    public static func sqrt(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.sqrt(Expression.toImpl(expression)))
    }

    
    /// Creates a TAN(expr) function that returns the tangent of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns:  The TAN(expr) function.
    public static func tan(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.tan(Expression.toImpl(expression)))
    }
    
    
    /// Creates a TRUNC(expr) function that truncates all of the digits after the decimal place
    /// of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The trunc function.
    public static func trunc(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.trunc(Expression.toImpl(expression)))
    }
    
    
    /// Creates a TRUNC(expr, digits) function that truncates the number of the digits after
    /// the decimal place of the given numeric expression.
    ///
    /// - Parameters:
    ///   - expression: The numeric expression.
    ///   - digits: The number of digits to truncate.
    /// - Returns: The TRUNC(expr, digits) function.
    public static func trunc(_ expression: Any, digits: Int) -> Expression {
        return Expression(CBLQueryFunction.trunc(Expression.toImpl(expression), digits: digits))
    }
    
    
    // Mark: String
    
    
    /// Creates a CONTAINS(expr, substr) function that evaluates whether the given string
    /// expression conatins the given substring expression or not.
    ///
    /// - Parameters:
    ///   - expression: The string expression.
    ///   - substring: The substring expression.
    /// - Returns: The CONTAINS(expr, substr) function.
    public static func contains(_ expression: Any, substring: Any) -> Expression {
        return Expression(CBLQueryFunction.contains(Expression.toImpl(expression),
                                                    substring: Expression.toImpl(substring)))
    }
    
    
    /// Creates a LENGTH(expr) function that returns the length of the given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The LENGTH(expr) function.
    public static func length(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.length(Expression.toImpl(expression)))
    }
    
    
    /// Creates a LOWER(expr) function that returns the lowercase string of the given string
    /// expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The LOWER(expr) function.
    public static func lower(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.lower(Expression.toImpl(expression)))
    }
    
    
    /// Creates a LTRIM(expr) function that removes the whitespace from the beginning of the
    /// given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The LTRIM(expr) function.
    public static func ltrim(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.ltrim(Expression.toImpl(expression)))
    }
    
    
    /// Creates a RTRIM(expr) function that removes the whitespace from the end of the
    /// given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The RTRIM(expr) function.
    public static func rtrim(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.rtrim(Expression.toImpl(expression)))
    }
    
    
    /// Creates a TRIM(expr) function that removes the whitespace from the beginning and '
    /// the end of the given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The TRIM(expr) function.
    public static func trim(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.trim(Expression.toImpl(expression)))
    }
    
    
    /// Creates a UPPER(expr) function that returns the uppercase string of the given string
    /// expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The UPPER(expr) function.
    public static func upper(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.upper(Expression.toImpl(expression)))
    }
    
    
    // Mark: Type
    
    
    /// Creates a ISARRAY(expr) function that evaluates whether the given expression
    /// is an array value of not.
    ///
    /// - Parameter expression: The expression
    /// - Returns: The ISARRAY(expr) function.
    public static func isArray(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.isArray(Expression.toImpl(expression)))
    }
    
    
    /// Creates a ISNUMBER(expr) function that evaluates whether the given expression
    /// is a numeric value of not.
    ///
    /// - Parameter expression: The expression
    /// - Returns: The ISNUMBER(expr) function.
    public static func isNumber(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.isNumber(Expression.toImpl(expression)))
    }
    
    
    /// Creates a ISDICTIONARY(expr) function that evaluates whether the given expression
    /// is a dictionary of not.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The ISDICTIONARY(expr) function.
    public static func isDictionary(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.isDictionary(Expression.toImpl(expression)))
    }
    
    
    /// Creates a ISSTRING(expr) function that evaluates whether the given expression
    /// is a string of not.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The ISSTRING(expr) function.
    public static func isString(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.isString(Expression.toImpl(expression)))
    }
    
}
