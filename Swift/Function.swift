//
//  Function.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** Function represents a function expression. */
public class Function: Expression {
    
    // MARK: Aggregation
    
    /** Create an AVG(expr) function expression that returns the average of all the number values
        in the group of the values expressed by the given expression.
        @param expression   The expression.
        @return The AVG(expr) function. */
    public static func avg(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.avg(toImpl(expression)))
    }
    
    /** Create a COUNT(expr) function expression that returns the count of all values
        in the group of the values expressed by the given expression.
        @param expression   The expression.
        @return The COUNT(expr) function. */
    public static func count(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.count(toImpl(expression)))
    }
    
    /** Create a MIN(expr) function expression that returns the minimum value
        in the group of the values expressed by the given expression.
        @param expression   The expression.
        @return The MIN(expr) function. */
    public static func min(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.min(toImpl(expression)))
    }
    
    /** Create a MAX(expr) function expression that returns the maximum value
        in the group of the values expressed by the given expression.
        @param expression   The expression.
        @return The MAX(expr) function. */
    public static func max(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.max(toImpl(expression)))
    }
    
    /** Create a SUM(expr) function expression that return the sum of all number values
        in the group of the values expressed by the given expression.
        @param expression   The expression.
        @return The SUM(expr) function. */
    public static func sum(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.sum(toImpl(expression)))
    }
    
    // MARK: Array
    
    /** Creates an ARRAY_CONTAINS(expr, value) function that checks whether the given array 
        expression contains the given value or not.
        @param expression   The expression that evluates to an array.
        @param value        The value to search for in the given array expression.
        @return The ARRAY_CONTAINS(expr, value) function. */
    public static func arrayContains(_ expression: Any, value: Any?) -> Expression {
        return Expression(CBLQueryFunction.arrayContains(
            toImpl(expression), value: toImpl(value ?? NSNull())))
    }
    
    /** Creates an ARRAY_LENGTH(expr) function that returns the length of the given array
        expression.
        @param expression   The expression that evluates to an array.
        @return The ARRAY_LENGTH(expr) function. */
    public static func arrayLength(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.arrayLength(toImpl(expression)))
    }
    
    // MARK: Math
    
    /** Creates an ABS(expr) function that returns the absolute value of the given numeric
        expression.
        @param expression   The numeric expression.
        @return The ABS(expr) function. */
    public static func abs(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.abs(toImpl(expression)))
    }
    
    /** Creates an ACOS(expr) function that returns the inverse cosine of the given numeric
        expression.
        @param expression   The numeric expression.
        @return The ACOS(expr) function. */
    public static func acos(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.acos(toImpl(expression)))
    }
    
    /** Creates an ASIN(expr) function that returns the inverse sin of the given numeric
        expression.
        @param expression   The numeric expression.
        @return The ASIN(expr) function. */
    public static func asin(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.asin(toImpl(expression)))
    }
    
    /** Creates an ATAN(expr) function that returns the inverse tangent of the numeric
        expression.
        @param expression   The numeric expression.
        @return The ATAN(expr) function. */
    public static func atan(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.atan(toImpl(expression)))
    }
    
    /** Creates an ATAN2(X, Y) function that returns the arctangent of y/x.
        @param x   The expression to evaluate as the X coordinate.
        @param y   The expression to evaluate as the Y coordinate.
        @return The ATAN2(X, Y) function. */
    public static func atan2(x: Any, y: Any) -> Expression {
        return Expression(CBLQueryFunction.atan2(toImpl(x), y: toImpl(y)))
    }
    
    /** Creates a CEIL(expr) function that returns the ceiling value of the given numeric
        expression.
        @param expression   The numeric expression.
        @return The CEIL(expr) function. */
    public static func ceil(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.ceil(toImpl(expression)))
    }
    
    /** Creates a COS(expr) function that returns the cosine of the given numeric expression.
        @param expression   The numeric expression.
        @return The COS(expr) function. */
    public static func cos(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.cos(toImpl(expression)))
    }
    
    /** Creates a DEGREES(expr) function that returns the degrees value of the given radiants
        value expression.
        @param expression   The numeric expression to evaluate as a radiants value.
        @return The DEGREES(expr) function. */
    public static func degrees(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.degrees(toImpl(expression)))
    }
    
    /** Creates a E() function that return the value of the mathemetical constant 'e'.
        @return The E() constant function. */
    public static func e() -> Expression {
        return Expression(CBLQueryFunction.e())
    }
    
    /** Creates a EXP(expr) function that returns the value of 'e' power by the given numeric
        expression.
        @param expression   The numeric expression.
        @return The EXP(expr) function. */
    public static func exp(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.exp(toImpl(expression)))
    }
    
    /** Creates a FLOOR(expr) function that returns the floor value of the given
        numeric expression.
        @param expression   The numeric expression.
        @return The FLOOR(expr) function. */
    public static func floor(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.floor(toImpl(expression)))
    }
    
    /** Creates a LN(expr) function that returns the natural log of the given numeric expression.
        @param expression   The numeric expression.
        @return The LN(expr) function. */
    public static func ln(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.ln(toImpl(expression)))
    }
    
    /** Creates a LOG(expr) function that returns the base 10 log of the given numeric expression.
        @param expression   The numeric expression.
        @return The LOG(expr) function. */
    public static func log(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.log(toImpl(expression)))
    }
    
    /** Creates a PI() function that returns the mathemetical constant Pi.
        @return The PI() constant function. */
    public static func pi() -> Expression {
        return Expression(CBLQueryFunction.pi())
    }
    
    /** Creates a POWER(base, exponent) function that returns the value of the given base
        expression power the given exponent expression.
        @param base The base expression.
        @param exponent The exponent expression.
        @return The POWER(base, exponent) function. */
    public static func power(base: Any, exponent: Any) -> Expression {
        return Expression(CBLQueryFunction.power(toImpl(base), exponent: toImpl(exponent)))
    }
    
    /** Creates a RADIANS(expr) function that returns the radians value of the given degrees
        value expression.
        @param expression   The numeric expression to evaluate as a degrees value.
        @return The RADIANS(expr) function. */
    public static func radians(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.radians(toImpl(expression)))
    }
    
    /** Creates a ROUND(expr) function that returns the rounded value of the given numeric
        expression.
        @param expression   The numeric expression.
        @return The ROUND(expr) function. */
    public static func round(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.round(toImpl(expression)))
    }
    
    /** Creates a ROUND(expr, digits) function that returns the rounded value to the given
        number of digits of the given numeric expression.
        @param expression   The numeric expression.
        @param digits   The number of digits.
        @return The ROUND(expr, digits) function. */
    public static func round(_ expression: Any, digits: Int) -> Expression {
        return Expression(CBLQueryFunction.round(toImpl(expression), digits: digits))
    }
    
    /** Creates a SIGN(expr) function that returns the sign (1: positive, -1: negative, 0: zero)
        of the given numeric expression.
        @param expression   The numeric expression.
        @return The SIGN(expr) function. */
    public static func sign(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.sign(toImpl(expression)))
    }
    
    /** Creates a SIN(expr) function that returns the sin of the given numeric expression.
        @param expression   The numeric expression.
        @return The SIN(expr) function. */
    public static func sin(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.sin(toImpl(expression)))
    }
    
    /** Creates a SQRT(expr) function that returns the square root of the given numeric expression.
        @param expression   The numeric expression.
        @return The SQRT(expr) function. */
    public static func sqrt(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.sqrt(toImpl(expression)))
    }
    
    /** Creates a TAN(expr) function that returns the tangent of the given numeric expression.
        @param expression   The numeric expression.
        @return The TAN(expr) function. */
    public static func tan(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.tan(toImpl(expression)))
    }
    
    /** Creates a TRUNC(expr) function that truncates all of the digits after the decimal place
        of the given numeric expression.
        @param expression   The numeric expression.
        @return The trunc function. */
    public static func trunc(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.trunc(toImpl(expression)))
    }
    
    /** Creates a TRUNC(expr, digits) function that truncates the number of the digits after
        the decimal place of the given numeric expression.
        @param expression   The numeric expression.
        @param digits   The number of digits to truncate.
        @return The TRUNC(expr, digits) function. */
    public static func trunc(_ expression: Any, digits: Int) -> Expression {
        return Expression(CBLQueryFunction.trunc(toImpl(expression), digits: digits))
    }
    
    // Mark: String
    
    /** Creates a CONTAINS(expr, substr) function that evaluates whether the given string
        expression conatins the given substring expression or not.
        @param expression   The string expression.
        @param substring    The substring expression.
        @return The CONTAINS(expr, substr) function. */
    public static func contains(_ expression: Any, substring: Any) -> Expression {
        return Expression(CBLQueryFunction.contains(toImpl(expression), substring: toImpl(substring)))
    }
    
    /** Creates a LENGTH(expr) function that returns the length of the given string expression.
        @param expression   The string expression.
        @return The LENGTH(expr) function. */
    public static func length(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.length(toImpl(expression)))
    }
    
    /** Creates a LOWER(expr) function that returns the lowercase string of the given string
        expression.
        @param expression   The string expression.
        @return The LOWER(expr) function. */
    public static func lower(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.lower(toImpl(expression)))
    }
    
    /** Creates a LTRIM(expr) function that removes the whitespace from the beginning of the
        given string expression.
        @param expression   The string expression.
        @return The LTRIM(expr) function. */
    public static func ltrim(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.ltrim(toImpl(expression)))
    }
    
    /** Creates a RTRIM(expr) function that removes the whitespace from the end of the
        given string expression.
        @param expression   The string expression.
        @return The RTRIM(expr) function. */
    public static func rtrim(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.rtrim(toImpl(expression)))
    }
    
    /** Creates a TRIM(expr) function that removes the whitespace from the beginning and '
        the end of the given string expression.
        @param expression   The string expression.
        @return The TRIM(expr) function. */
    public static func trim(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.trim(toImpl(expression)))
    }
    
    /** Creates a UPPER(expr) function that returns the uppercase string of the given string
        expression.
        @param expression   The string expression.
        @return The UPPER(expr) function. */
    public static func upper(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.upper(toImpl(expression)))
    }
    
    // Mark: Type
    
    /** Creates a ISARRAY(expr) function that evaluates whether the given expression
        is an array value of not.
        @param expression   The expression.
        @return The ISARRAY(expr) function. */
    public static func isArray(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.isArray(toImpl(expression)))
    }
    
    /** Creates a ISNUMBER(expr) function that evaluates whether the given expression
        is a numeric value of not.
        @param expression   The expression.
        @return The ISNUMBER(expr) function. */
    public static func isNumber(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.isNumber(toImpl(expression)))
    }
    
    /** Creates a ISDICTIONARY(expr) function that evaluates whether the given expression
        is a dictionary of not.
        @param expression   The expression.
        @return The ISDICTIONARY(expr) function. */
    public static func isDictionary(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.isDictionary(toImpl(expression)))
    }
    
    /** Creates a ISSTRING(expr) function that evaluates whether the given expression
        is a string of not.
        @param expression   The expression.
        @return The ISSTRING(expr) function. */
    public static func isString(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.isString(toImpl(expression)))
    }
}

