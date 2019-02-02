//
//  Function.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation


/// Function factory.
public final class Function {
    
    // MARK: Aggregation
    
    
    /// Create an AVG(expr) function expression that returns the average of all the number values
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The AVG(expr) function.
    public static func avg(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.avg(expression.toImpl()))
    }
    
    
    /// Create a COUNT(expr) function expression that returns the count of all values
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The COUNT(expr) function.
    public static func count(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.count(expression.toImpl()))
    }
    
    
    /// Create a MIN(expr) function expression that returns the minimum value
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The MIN(expr) function.
    public static func min(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.min(expression.toImpl()))
    }
    
    
    /// Create a MAX(expr) function expression that returns the maximum value
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The MAX(expr) function.
    public static func max(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.max(expression.toImpl()))
    }
    
    
    /// Create a SUM(expr) function expression that return the sum of all number values
    /// in the group of the values expressed by the given expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The SUM(expr) function.
    public static func sum(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.sum(expression.toImpl()))
    }
    
    
    // MARK: Mathematics
    
    
    /// Creates an ABS(expr) function that returns the absolute value of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ABS(expr) function.
    public static func abs(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.abs(expression.toImpl()))
    }
    
    
    /// Creates an ACOS(expr) function that returns the inverse cosine of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ACOS(expr) function.
    public static func acos(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.acos(expression.toImpl()))
    }
    
    
    /// Creates an ASIN(expr) function that returns the inverse sin of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ASIN(expr) function.
    public static func asin(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.asin(expression.toImpl()))
    }
    
    
    /// Creates an ATAN(expr) function that returns the inverse tangent of the numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ATAN(expr) function.
    public static func atan(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.atan(expression.toImpl()))
    }
    
    
    /// Creates an ATAN2(X, Y) function that returns the arctangent of y/x.
    ///
    /// - Parameters:
    ///   - x: The expression to evaluate as the X coordinate.
    ///   - y: The expression to evaluate as the Y coordinate.
    /// - Returns: The ATAN2(X, Y) function.
    public static func atan2(x: ExpressionProtocol, y: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.atan2(x.toImpl(), y: y.toImpl()))
    }
    
    
    /// Creates a CEIL(expr) function that returns the ceiling value of the given numeric
    /// expression
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The CEIL(expr) function.
    public static func ceil(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.ceil(expression.toImpl()))
    }
    

    /// Creates a COS(expr) function that returns the cosine of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The COS(expr) function.
    public static func cos(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.cos(expression.toImpl()))
    }
    
    
    /// Creates a DEGREES(expr) function that returns the degrees value of the given radiants
    /// value expression.
    ///
    /// - Parameter expression: The numeric expression to evaluate as a radiants value.
    /// - Returns: The DEGREES(expr) function.
    public static func degrees(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.degrees(expression.toImpl()))
    }

    
    /// Creates a E() function that return the value of the mathemetical constant 'e'.
    ///
    /// - Returns: The E() constant function.
    public static func e() -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.e())
    }
    
    
    /// Creates a EXP(expr) function that returns the value of 'e' power by the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The EXP(expr) function.
    public static func exp(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.exp(expression.toImpl()))
    }
    
    
    /// Creates a FLOOR(expr) function that returns the floor value of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The FLOOR(expr) function.
    public static func floor(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.floor(expression.toImpl()))
    }
    
    
    /// Creates a LN(expr) function that returns the natural log of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The LN(expr) function.
    public static func ln(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.ln(expression.toImpl()))
    }
    
    
    /// Creates a LOG(expr) function that returns the base 10 log of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The LOG(expr) function.
    public static func log(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.log(expression.toImpl()))
    }

    
    /// Creates a PI() function that returns the mathemetical constant Pi.
    ///
    /// - Returns: The PI() constant function.
    public static func pi() -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.pi())
    }

    
    /// Creates a POWER(base, exponent) function that returns the value of the given base
    /// expression power the given exponent expression.
    ///
    /// - Parameters:
    ///   - base: The base expression.
    ///   - exponent: The exponent expression.
    /// - Returns: The POWER(base, exponent) function.
    public static func power(base: ExpressionProtocol, exponent: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.power(base.toImpl(), exponent: exponent.toImpl()))
    }
    
    
    /// Creates a RADIANS(expr) function that returns the radians value of the given degrees
    /// value expression.
    ///
    /// - Parameter expression: The numeric expression to evaluate as a degrees value.
    /// - Returns: The RADIANS(expr) function.
    public static func radians(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.radians(expression.toImpl()))
    }
    
    
    /// Creates a ROUND(expr) function that returns the rounded value of the given numeric
    /// expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The ROUND(expr) function.
    public static func round(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.round(expression.toImpl()))
    }

    
    /// Creates a ROUND(expr, digits) function that returns the rounded value to the given
    /// number of digits of the given numeric expression.
    ///
    /// - Parameters:
    ///   - expression: The numeric expression.
    ///   - digits: The number of digits.
    /// - Returns: The ROUND(expr, digits) function.
    public static func round(_ expression: ExpressionProtocol, digits: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.round(expression.toImpl(), digits: digits.toImpl()))
    }
    
    
    /// Creates a SIGN(expr) function that returns the sign (1: positive, -1: negative, 0: zero)
    /// of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The SIGN(expr) function.
    public static func sign(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.sign(expression.toImpl()))
    }
    
    
    /// Creates a SIN(expr) function that returns the sin of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The SIN(expr) function.
    public static func sin(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.sin(expression.toImpl()))
    }
    
    
    /// Creates a SQRT(expr) function that returns the square root of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The SQRT(expr) function.
    public static func sqrt(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.sqrt(expression.toImpl()))
    }

    
    /// Creates a TAN(expr) function that returns the tangent of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns:  The TAN(expr) function.
    public static func tan(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.tan(expression.toImpl()))
    }
    
    
    /// Creates a TRUNC(expr) function that truncates all of the digits after the decimal place
    /// of the given numeric expression.
    ///
    /// - Parameter expression: The numeric expression.
    /// - Returns: The trunc function.
    public static func trunc(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.trunc(expression.toImpl()))
    }
    
    
    /// Creates a TRUNC(expr, digits) function that truncates the number of the digits after
    /// the decimal place of the given numeric expression.
    ///
    /// - Parameters:
    ///   - expression: The numeric expression.
    ///   - digits: The number of digits to truncate.
    /// - Returns: The TRUNC(expr, digits) function.
    public static func trunc(_ expression: ExpressionProtocol, digits: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.trunc(expression.toImpl(), digits: digits.toImpl()))
    }
    
    
    // Mark: String
    
    
    /// Creates a CONTAINS(expr, substr) function that evaluates whether the given string
    /// expression conatins the given substring expression or not.
    ///
    /// - Parameters:
    ///   - expression: The string expression.
    ///   - substring: The substring expression.
    /// - Returns: The CONTAINS(expr, substr) function.
    public static func contains(_ expression: ExpressionProtocol, substring: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.contains(expression.toImpl(), substring: substring.toImpl()))
    }
    
    
    /// Creates a LENGTH(expr) function that returns the length of the given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The LENGTH(expr) function.
    public static func length(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.length(expression.toImpl()))
    }
    
    
    /// Creates a LOWER(expr) function that returns the lowercase string of the given string
    /// expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The LOWER(expr) function.
    public static func lower(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.lower(expression.toImpl()))
    }
    
    
    /// Creates a LTRIM(expr) function that removes the whitespace from the beginning of the
    /// given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The LTRIM(expr) function.
    public static func ltrim(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.ltrim(expression.toImpl()))
    }
    
    
    /// Creates a RTRIM(expr) function that removes the whitespace from the end of the
    /// given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The RTRIM(expr) function.
    public static func rtrim(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.rtrim(expression.toImpl()))
    }
    
    
    /// Creates a TRIM(expr) function that removes the whitespace from the beginning and '
    /// the end of the given string expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The TRIM(expr) function.
    public static func trim(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.trim(expression.toImpl()))
    }
    
    
    /// Creates a UPPER(expr) function that returns the uppercase string of the given string
    /// expression.
    ///
    /// - Parameter expression: The string expression.
    /// - Returns: The UPPER(expr) function.
    public static func upper(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.upper(expression.toImpl()))
    }
    
    
    /// Creates a STR_TO_MILLIS(expr) function that returns the number of milliseconds since
    /// the unix epoch of the given ISO 8601 date string expression.
    ///
    /// - Parameter expression: The validly formatted ISO 8601 date time string expression.
    /// - Returns: The STR_TO_MILLIS(expr) function.
    /// - Note: Valid date strings must start with a date in the form YYYY-MM-DD (time only strings
    /// are not supported).
    ///
    /// Times can be of the form HH:MM, HH:MM:SS, or HH:MM:SS.FFF. Leading zero is not
    /// optional (i.e. 02 is ok, 2 is not). Hours are in 24-hour format. FFF represents
    /// milliseconds, and *trailing* zeros are optional (i.e. 5 == 500).
    ///
    /// Time zones can be in one of three forms:
    /// (+/-)HH:MM
    /// (+/-)HHMM
    /// Z (which represents UTC)
    ///
    /// No time zone present will default to the device local time zone.
    public static func stringToMillis(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.string(toMillis: expression.toImpl()))
    }
    
    
    /// Creates a STR_TO_UTC(expr) function that returns the ISO 8601 UTC datetime string
    /// of the given ISO 8601 date string expression.
    ///
    /// - Parameter expression: The validly formatted ISO 8601 date time string expression.
    /// - Returns: The STR_TO_UTC(expr) function.
    /// - Note: Valid date strings must start with a date in the form YYYY-MM-DD (time only strings
    /// are not supported).
    ///
    /// Times can be of the form HH:MM, HH:MM:SS, or HH:MM:SS.FFF. Leading zero is not
    /// optional (i.e. 02 is ok, 2 is not). Hours are in 24-hour format. FFF represents
    /// milliseconds, and *trailing* zeros are optional (i.e. 5 == 500).
    ///
    /// Time zones can be in one of three forms:
    /// (+/-)HH:MM
    /// (+/-)HHMM
    /// Z (which represents UTC)
    ///
    /// No time zone present will default to the device local time zone.
    public static func stringToUTC(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.string(toUTC: expression.toImpl()))
    }
    
    
    /// Creates a MILLIS_TO_STR(expr) function that returns a ISO 8601 date time string in device
    /// local timezone of the given number of milliseconds since the unix epoch expression.
    ///
    /// - Parameter expression: The numeric value representing milliseconds since the unix epoch.
    /// - Returns: The MILLIS_TO_STR(expr) function.
    /// - Note: If the input expression is not numeric, then the result will be null.
    public static func millisToString(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.millis(toString: expression.toImpl()))
    }
    
    
    /// Creates a MILLIS_TO_UTC(expr) function that returns the UTC ISO 8601 date time string
    /// of the given number of milliseconds since the unix epoch expression.
    ///
    /// - Parameter expression: The numeric value representing milliseconds since the unix epoch.
    /// - Returns: The MILLIS_TO_UTC(expr) function.
    /// - Note: If the input expression is not numeric, then the result will be null.
    public static func millisToUTC(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryFunction.millis(toUTC: expression.toImpl()))
    }
}
