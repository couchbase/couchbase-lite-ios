//
//  CBLQueryFunction.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLQueryFunction provides query functions.
 */
@interface CBLQueryFunction: NSObject

#pragma mark - Aggregation

/** 
 Creates an AVG(expr) function expression that returns the average of all the number values
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The AVG(expr) function.
 */
+ (CBLQueryExpression*) avg: (id)expression;

/** 
 Creates a COUNT(expr) function expression that returns the count of all values
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The COUNT(expr) function.
 */
+ (CBLQueryExpression*) count: (id)expression;

/** 
 Creates a MIN(expr) function expression that returns the minimum value
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The MIN(expr) function.
 */
+ (CBLQueryExpression*) min: (id)expression;

/** 
 Creates a MAX(expr) function expression that returns the maximum value
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The MAX(expr) function.
 */
+ (CBLQueryExpression*) max: (id)expression;

/** 
 Creates a SUM(expr) function expression that return the sum of all number values
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The SUM(expr) function.
 */
+ (CBLQueryExpression*) sum: (id)expression;

#pragma mark - Math

/** 
 Creates an ABS(expr) function that returns the absolute value of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ABS(expr) function.
 */
+ (CBLQueryExpression*) abs: (id)expression;

/** 
 Creates an ACOS(expr) function that returns the inverse cosine of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ACOS(expr) function.
 */
+ (CBLQueryExpression*) acos: (id)expression;

/** 
 Creates an ASIN(expr) function that returns the inverse sin of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ASIN(expr) function.
 */
+ (CBLQueryExpression*) asin: (id)expression;

/** 
 Creates an ATAN(expr) function that returns the inverse tangent of the numeric
 expression.
 
 @param expression The numeric expression.
 @return The ATAN(expr) function.
 */
+ (CBLQueryExpression*) atan: (id)expression;

/** 
 Creates an ATAN2(X, Y) function that returns the arctangent of y/x.
 
 @param x The expression to evaluate as the X coordinate.
 @param y The expression to evaluate as the Y coordinate.
 @return The ATAN2(X, Y) function.
 */
+ (CBLQueryExpression*) atan2: (id)x y: (id)y;

/** 
 Creates a CEIL(expr) function that returns the ceiling value of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The CEIL(expr) function.
 */
+ (CBLQueryExpression*) ceil: (id)expression;

/** 
 Creates a COS(expr) function that returns the cosine of the given numeric expression.
 
 @param expression The numeric expression.
 @return The COS(expr) function.
 */
+ (CBLQueryExpression*) cos: (id)expression;

/** 
 Creates a DEGREES(expr) function that returns the degrees value of the given radiants
 value expression.
 
 @param expression The numeric expression to evaluate as a radiants value.
 @return The DEGREES(expr) function.
 */
+ (CBLQueryExpression*) degrees: (id)expression;

/** 
 Creates a E() function that return the value of the mathemetical constant 'e'.
 
 @return The E() constant function.
 */
+ (CBLQueryExpression*) e;

/** 
 Creates a EXP(expr) function that returns the value of 'e' power by the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The EXP(expr) function.
 */
+ (CBLQueryExpression*) exp: (id)expression;

/** 
 Creates a FLOOR(expr) function that returns the floor value of the given
 numeric expression.
 
 @param expression The numeric expression.
 @return The FLOOR(expr) function.
 */
+ (CBLQueryExpression*) floor: (id)expression;

/** 
 Creates a LN(expr) function that returns the natural log of the given numeric expression.
 
 @param expression The numeric expression.
 @return The LN(expr) function.
 */
+ (CBLQueryExpression*) ln: (id)expression;

/** 
 Creates a LOG(expr) function that returns the base 10 log of the given numeric expression.
 @param expression The numeric expression.
 
 @return The LOG(expr) function.
 */
+ (CBLQueryExpression*) log: (id)expression;

/** 
 Creates a PI() function that returns the mathemetical constant Pi.
 
 @return The PI() constant function.
 */
+ (CBLQueryExpression*) pi;

/** 
 Creates a POWER(base, exponent) function that returns the value of the given base
 expression power the given exponent expression.
 
 @param base The base expression.
 @param exponent The exponent expression.
 @return The POWER(base, exponent) function.
 */
+ (CBLQueryExpression*) power: (id)base exponent: (id)exponent;

/** 
 Creates a RADIANS(expr) function that returns the radians value of the given degrees
 value expression.
 
 @param expression The numeric expression to evaluate as a degrees value.
 @return The RADIANS(expr) function.
 */
+ (CBLQueryExpression*) radians: (id)expression;

/** 
 Creates a ROUND(expr) function that returns the rounded value of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ROUND(expr) function.
 */
+ (CBLQueryExpression*) round: (id)expression;

/** 
 Creates a ROUND(expr, digits) function that returns the rounded value to the given
 number of digits of the given numeric expression.
 
 @param expression The numeric expression.
 @param digits   The number of digits.
 @return The ROUND(expr, digits) function.
 */
+ (CBLQueryExpression*) round: (id)expression digits: (NSInteger)digits;

/** 
 Creates a SIGN(expr) function that returns the sign (1: positive, -1: negative, 0: zero)
 of the given numeric expression.
 
 @param expression The numeric expression.
 @return The SIGN(expr) function.
 */
+ (CBLQueryExpression*) sign: (id)expression;

/** 
 Creates a SIN(expr) function that returns the sin of the given numeric expression.
 
 @param expression The numeric expression.
 @return The SIN(expr) function.
 */
+ (CBLQueryExpression*) sin: (id)expression;

/** 
 Creates a SQRT(expr) function that returns the square root of the given numeric expression.
 
 @param expression The numeric expression.
 @return The SQRT(expr) function.
 */
+ (CBLQueryExpression*) sqrt: (id)expression;

/** 
 Creates a TAN(expr) function that returns the tangent of the given numeric expression.
 
 @param expression The numeric expression.
 @return The TAN(expr) function.
 */
+ (CBLQueryExpression*) tan: (id)expression;

/** 
 Creates a TRUNC(expr) function that truncates all of the digits after the decimal place
 of the given numeric expression.
 
 @param expression The numeric expression.
 @return The trunc function.
 */
+ (CBLQueryExpression*) trunc: (id)expression;

/** 
 Creates a TRUNC(expr, digits) function that truncates the number of the digits after
 the decimal place of the given numeric expression.
 
 @param expression The numeric expression.
 @param digits The number of digits to truncate.
 @return The TRUNC(expr, digits) function.
 */
+ (CBLQueryExpression*) trunc: (id)expression digits: (NSInteger)digits;

#pragma mark - String

/** 
 Creates a CONTAINS(expr, substr) function that evaluates whether the given string
 expression conatins the given substring expression or not.
 
 @param expression The string expression.
 @param substring The substring expression.
 @return The CONTAINS(expr, substr) function.
 */
+ (CBLQueryExpression*) contains: (id)expression substring: (id)substring;

/** 
 Creates a LENGTH(expr) function that returns the length of the given string expression.
 
 @param expression The string expression.
 @return The LENGTH(expr) function.
 */
+ (CBLQueryExpression*) length: (id)expression;

/** 
 Creates a LOWER(expr) function that returns the lowercase string of the given string
 expression.
 
 @param expression The string expression.
 @return The LOWER(expr) function.
 */
+ (CBLQueryExpression*) lower:(id)expression;

/** 
 Creates a LTRIM(expr) function that removes the whitespace from the beginning of the
 given string expression.
 
 @param expression The string expression.
 @return The LTRIM(expr) function.
 */
+ (CBLQueryExpression*) ltrim:(id)expression;

/** 
 Creates a RTRIM(expr) function that removes the whitespace from the end of the
 given string expression.
 
 @param expression The string expression.
 @return The RTRIM(expr) function.
 */
+ (CBLQueryExpression*) rtrim:(id)expression;

/** 
 Creates a TRIM(expr) function that removes the whitespace from the beginning and '
 the end of the given string expression.
 
 @param expression The string expression.
 @return The TRIM(expr) function.
 */
+ (CBLQueryExpression*) trim:(id)expression;

/** 
 Creates a UPPER(expr) function that returns the uppercase string of the given string expression.
 
 @param expression The string expression.
 @return The UPPER(expr) function.
 */
+ (CBLQueryExpression*) upper:(id)expression;

#pragma mark - Type

/** 
 Creates a ISARRAY(expr) function that evaluates whether the given expression
 is an array value of not.
 @param expression The expression.
 @return The ISARRAY(expr) function.
 */
+ (CBLQueryExpression*) isArray:(id)expression;

/** 
 Creates a ISNUMBER(expr) function that evaluates whether the given expression
 is a numeric value of not.
 
 @param expression The expression.
 @return The ISNUMBER(expr) function.
 */
+ (CBLQueryExpression*) isNumber:(id)expression;

/**
 Creates a ISDICTIONARY(expr) function that evaluates whether the given expression
 is a dictionary of not.
 
 @param expression The expression.
 @return The ISDICTIONARY(expr) function.
 */
+ (CBLQueryExpression*) isDictionary:(id)expression;

/** 
 Creates a ISSTRING(expr) function that evaluates whether the given expression
 is a string of not.
 
 @param expression The expression.
 @return The ISSTRING(expr) function.
 */
+ (CBLQueryExpression*) isString:(id)expression;

@end

NS_ASSUME_NONNULL_END
