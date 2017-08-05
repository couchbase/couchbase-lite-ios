//
//  CBLQueryFunction.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLQueryFunction represents a function expression. 
 */
@interface CBLQueryFunction : CBLQueryExpression

#pragma mark - Aggregation

/** 
 Creates an AVG(expr) function expression that returns the average of all the number values
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The AVG(expr) function.
 */
+ (instancetype) avg: (id)expression;

/** 
 Creates a COUNT(expr) function expression that returns the count of all values
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The COUNT(expr) function.
 */
+ (instancetype) count: (id)expression;

/** 
 Creates a MIN(expr) function expression that returns the minimum value
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The MIN(expr) function.
 */
+ (instancetype) min: (id)expression;

/** 
 Creates a MAX(expr) function expression that returns the maximum value
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The MAX(expr) function.
 */
+ (instancetype) max: (id)expression;

/** 
 Creates a SUM(expr) function expression that return the sum of all number values
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The SUM(expr) function.
 */
+ (instancetype) sum: (id)expression;

#pragma mark - Array

/** 
 Creates an ARRAY_CONTAINS(expr, value) function that checks whether the given array
 expression contains the given value or not.
 
 @param expression The expression that evluates to an array.
 @param value The value to search for in the given array expression.
 @return The ARRAY_CONTAINS(expr, value) function.
 */
+ (instancetype) arrayContains: (id)expression value: (nullable id)value;

/** 
 Creates an ARRAY_LENGTH(expr) function that returns the length of the given array
 expression.
 
 @param expression The expression that evluates to an array.
 @return The ARRAY_LENGTH(expr) function.
 */
+ (instancetype) arrayLength: (id)expression;

#pragma mark - Math

/** 
 Creates an ABS(expr) function that returns the absolute value of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ABS(expr) function.
 */
+ (instancetype) abs: (id)expression;

/** 
 Creates an ACOS(expr) function that returns the inverse cosine of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ACOS(expr) function.
 */
+ (instancetype) acos: (id)expression;

/** 
 Creates an ASIN(expr) function that returns the inverse sin of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ASIN(expr) function.
 */
+ (instancetype) asin: (id)expression;

/** 
 Creates an ATAN(expr) function that returns the inverse tangent of the numeric
 expression.
 
 @param expression The numeric expression.
 @return The ATAN(expr) function.
 */
+ (instancetype) atan: (id)expression;

/** 
 Creates an ATAN2(X, Y) function that returns the arctangent of y/x.
 
 @param x The expression to evaluate as the X coordinate.
 @param y The expression to evaluate as the Y coordinate.
 @return The ATAN2(X, Y) function.
 */
+ (instancetype) atan2: (id)x y: (id)y;

/** 
 Creates a CEIL(expr) function that returns the ceiling value of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The CEIL(expr) function.
 */
+ (instancetype) ceil: (id)expression;

/** 
 Creates a COS(expr) function that returns the cosine of the given numeric expression.
 
 @param expression The numeric expression.
 @return The COS(expr) function.
 */
+ (instancetype) cos: (id)expression;

/** 
 Creates a DEGREES(expr) function that returns the degrees value of the given radiants
 value expression.
 
 @param expression The numeric expression to evaluate as a radiants value.
 @return The DEGREES(expr) function.
 */
+ (instancetype) degrees: (id)expression;

/** 
 Creates a E() function that return the value of the mathemetical constant 'e'.
 
 @return The E() constant function.
 */
+ (instancetype) e;

/** 
 Creates a EXP(expr) function that returns the value of 'e' power by the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The EXP(expr) function.
 */
+ (instancetype) exp: (id)expression;

/** 
 Creates a FLOOR(expr) function that returns the floor value of the given
 numeric expression.
 
 @param expression The numeric expression.
 @return The FLOOR(expr) function.
 */
+ (instancetype) floor: (id)expression;

/** 
 Creates a LN(expr) function that returns the natural log of the given numeric expression.
 
 @param expression The numeric expression.
 @return The LN(expr) function.
 */
+ (instancetype) ln: (id)expression;

/** 
 Creates a LOG(expr) function that returns the base 10 log of the given numeric expression.
 @param expression The numeric expression.
 
 @return The LOG(expr) function.
 */
+ (instancetype) log: (id)expression;

/** 
 Creates a PI() function that returns the mathemetical constant Pi.
 
 @return The PI() constant function.
 */
+ (instancetype) pi;

/** 
 Creates a POWER(base, exponent) function that returns the value of the given base
 expression power the given exponent expression.
 
 @param base The base expression.
 @param exponent The exponent expression.
 @return The POWER(base, exponent) function.
 */
+ (instancetype) power: (id)base exponent: (id)exponent;

/** 
 Creates a RADIANS(expr) function that returns the radians value of the given degrees
 value expression.
 
 @param expression The numeric expression to evaluate as a degrees value.
 @return The RADIANS(expr) function.
 */
+ (instancetype) radians: (id)expression;

/** 
 Creates a ROUND(expr) function that returns the rounded value of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ROUND(expr) function.
 */
+ (instancetype) round: (id)expression;

/** 
 Creates a ROUND(expr, digits) function that returns the rounded value to the given
 number of digits of the given numeric expression.
 
 @param expression The numeric expression.
 @param digits   The number of digits.
 @return The ROUND(expr, digits) function.
 */
+ (instancetype) round: (id)expression digits: (NSInteger)digits;

/** 
 Creates a SIGN(expr) function that returns the sign (1: positive, -1: negative, 0: zero)
 of the given numeric expression.
 
 @param expression The numeric expression.
 @return The SIGN(expr) function.
 */
+ (instancetype) sign: (id)expression;

/** 
 Creates a SIN(expr) function that returns the sin of the given numeric expression.
 
 @param expression The numeric expression.
 @return The SIN(expr) function.
 */
+ (instancetype) sin: (id)expression;

/** 
 Creates a SQRT(expr) function that returns the square root of the given numeric expression.
 
 @param expression The numeric expression.
 @return The SQRT(expr) function.
 */
+ (instancetype) sqrt: (id)expression;

/** 
 Creates a TAN(expr) function that returns the tangent of the given numeric expression.
 
 @param expression The numeric expression.
 @return The TAN(expr) function.
 */
+ (instancetype) tan: (id)expression;

/** 
 Creates a TRUNC(expr) function that truncates all of the digits after the decimal place
 of the given numeric expression.
 
 @param expression The numeric expression.
 @return The trunc function.
 */
+ (instancetype) trunc: (id)expression;

/** 
 Creates a TRUNC(expr, digits) function that truncates the number of the digits after
 the decimal place of the given numeric expression.
 
 @param expression The numeric expression.
 @param digits The number of digits to truncate.
 @return The TRUNC(expr, digits) function.
 */
+ (instancetype) trunc: (id)expression digits: (NSInteger)digits;

#pragma mark - String

/** 
 Creates a CONTAINS(expr, substr) function that evaluates whether the given string
 expression conatins the given substring expression or not.
 
 @param expression The string expression.
 @param substring The substring expression.
 @return The CONTAINS(expr, substr) function.
 */
+ (instancetype) contains: (id)expression substring: (id)substring;

/** 
 Creates a LENGTH(expr) function that returns the length of the given string expression.
 
 @param expression The string expression.
 @return The LENGTH(expr) function.
 */
+ (instancetype) length: (id)expression;

/** 
 Creates a LOWER(expr) function that returns the lowercase string of the given string
 expression.
 
 @param expression The string expression.
 @return The LOWER(expr) function.
 */
+ (instancetype) lower:(id)expression;

/** 
 Creates a LTRIM(expr) function that removes the whitespace from the beginning of the
 given string expression.
 
 @param expression The string expression.
 @return The LTRIM(expr) function.
 */
+ (instancetype) ltrim:(id)expression;

/** 
 Creates a RTRIM(expr) function that removes the whitespace from the end of the
 given string expression.
 
 @param expression The string expression.
 @return The RTRIM(expr) function.
 */
+ (instancetype) rtrim:(id)expression;

/** 
 Creates a TRIM(expr) function that removes the whitespace from the beginning and '
 the end of the given string expression.
 
 @param expression The string expression.
 @return The TRIM(expr) function.
 */
+ (instancetype) trim:(id)expression;

/** 
 Creates a UPPER(expr) function that returns the uppercase string of the given string expression.
 
 @param expression The string expression.
 @return The UPPER(expr) function.
 */
+ (instancetype) upper:(id)expression;

#pragma mark - Type

/** 
 Creates a ISARRAY(expr) function that evaluates whether the given expression
 is an array value of not.
 @param expression The expression.
 @return The ISARRAY(expr) function.
 */
+ (instancetype) isArray:(id)expression;

/** 
 Creates a ISNUMBER(expr) function that evaluates whether the given expression
 is a numeric value of not.
 
 @param expression The expression.
 @return The ISNUMBER(expr) function.
 */
+ (instancetype) isNumber:(id)expression;

/**
 Creates a ISDICTIONARY(expr) function that evaluates whether the given expression
 is a dictionary of not.
 
 @param expression The expression.
 @return The ISDICTIONARY(expr) function.
 */
+ (instancetype) isDictionary:(id)expression;

/** 
 Creates a ISSTRING(expr) function that evaluates whether the given expression
 is a string of not.
 
 @param expression The expression.
 @return The ISSTRING(expr) function.
 */
+ (instancetype) isString:(id)expression;

@end

NS_ASSUME_NONNULL_END
