//
//  CBLQueryFunction.h
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
+ (CBLQueryExpression*) avg: (CBLQueryExpression*)expression;

/** 
 Creates a COUNT(expr) function expression that returns the count of all values
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The COUNT(expr) function.
 */
+ (CBLQueryExpression*) count: (CBLQueryExpression*)expression;

/** 
 Creates a MIN(expr) function expression that returns the minimum value
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The MIN(expr) function.
 */
+ (CBLQueryExpression*) min: (CBLQueryExpression*)expression;

/** 
 Creates a MAX(expr) function expression that returns the maximum value
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The MAX(expr) function.
 */
+ (CBLQueryExpression*) max: (CBLQueryExpression*)expression;

/** 
 Creates a SUM(expr) function expression that return the sum of all number values
 in the group of the values expressed by the given expression.
 
 @param expression The expression.
 @return The SUM(expr) function.
 */
+ (CBLQueryExpression*) sum: (CBLQueryExpression*)expression;

#pragma mark - Math

/** 
 Creates an ABS(expr) function that returns the absolute value of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ABS(expr) function.
 */
+ (CBLQueryExpression*) abs: (CBLQueryExpression*)expression;

/** 
 Creates an ACOS(expr) function that returns the inverse cosine of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ACOS(expr) function.
 */
+ (CBLQueryExpression*) acos: (CBLQueryExpression*)expression;

/** 
 Creates an ASIN(expr) function that returns the inverse sin of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ASIN(expr) function.
 */
+ (CBLQueryExpression*) asin: (CBLQueryExpression*)expression;

/** 
 Creates an ATAN(expr) function that returns the inverse tangent of the numeric
 expression.
 
 @param expression The numeric expression.
 @return The ATAN(expr) function.
 */
+ (CBLQueryExpression*) atan: (CBLQueryExpression*)expression;

/** 
 Creates an ATAN2(X, Y) function that returns the arctangent of y/x.
 
 @param x The expression to evaluate as the X coordinate.
 @param y The expression to evaluate as the Y coordinate.
 @return The ATAN2(X, Y) function.
 */
+ (CBLQueryExpression*) atan2: (CBLQueryExpression*)x y: (CBLQueryExpression*)y;

/** 
 Creates a CEIL(expr) function that returns the ceiling value of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The CEIL(expr) function.
 */
+ (CBLQueryExpression*) ceil: (CBLQueryExpression*)expression;

/** 
 Creates a COS(expr) function that returns the cosine of the given numeric expression.
 
 @param expression The numeric expression.
 @return The COS(expr) function.
 */
+ (CBLQueryExpression*) cos: (CBLQueryExpression*)expression;

/** 
 Creates a DEGREES(expr) function that returns the degrees value of the given radiants
 value expression.
 
 @param expression The numeric expression to evaluate as a radiants value.
 @return The DEGREES(expr) function.
 */
+ (CBLQueryExpression*) degrees: (CBLQueryExpression*)expression;

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
+ (CBLQueryExpression*) exp: (CBLQueryExpression*)expression;

/** 
 Creates a FLOOR(expr) function that returns the floor value of the given
 numeric expression.
 
 @param expression The numeric expression.
 @return The FLOOR(expr) function.
 */
+ (CBLQueryExpression*) floor: (CBLQueryExpression*)expression;

/** 
 Creates a LN(expr) function that returns the natural log of the given numeric expression.
 
 @param expression The numeric expression.
 @return The LN(expr) function.
 */
+ (CBLQueryExpression*) ln: (CBLQueryExpression*)expression;

/** 
 Creates a LOG(expr) function that returns the base 10 log of the given numeric expression.
 @param expression The numeric expression.
 
 @return The LOG(expr) function.
 */
+ (CBLQueryExpression*) log: (CBLQueryExpression*)expression;

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
+ (CBLQueryExpression*) power: (CBLQueryExpression*)base exponent: (CBLQueryExpression*)exponent;

/** 
 Creates a RADIANS(expr) function that returns the radians value of the given degrees
 value expression.
 
 @param expression The numeric expression to evaluate as a degrees value.
 @return The RADIANS(expr) function.
 */
+ (CBLQueryExpression*) radians: (CBLQueryExpression*)expression;

/** 
 Creates a ROUND(expr) function that returns the rounded value of the given numeric
 expression.
 
 @param expression The numeric expression.
 @return The ROUND(expr) function.
 */
+ (CBLQueryExpression*) round: (CBLQueryExpression*)expression;

/** 
 Creates a ROUND(expr, digits) function that returns the rounded value to the given
 number of digits of the given numeric expression.
 
 @param expression The numeric expression.
 @param digits   The number of digits.
 @return The ROUND(expr, digits) function.
 */
+ (CBLQueryExpression*) round: (CBLQueryExpression*)expression digits: (CBLQueryExpression*)digits;

/** 
 Creates a SIGN(expr) function that returns the sign (1: positive, -1: negative, 0: zero)
 of the given numeric expression.
 
 @param expression The numeric expression.
 @return The SIGN(expr) function.
 */
+ (CBLQueryExpression*) sign: (CBLQueryExpression*)expression;

/** 
 Creates a SIN(expr) function that returns the sin of the given numeric expression.
 
 @param expression The numeric expression.
 @return The SIN(expr) function.
 */
+ (CBLQueryExpression*) sin: (CBLQueryExpression*)expression;

/** 
 Creates a SQRT(expr) function that returns the square root of the given numeric expression.
 
 @param expression The numeric expression.
 @return The SQRT(expr) function.
 */
+ (CBLQueryExpression*) sqrt: (CBLQueryExpression*)expression;

/** 
 Creates a TAN(expr) function that returns the tangent of the given numeric expression.
 
 @param expression The numeric expression.
 @return The TAN(expr) function.
 */
+ (CBLQueryExpression*) tan: (CBLQueryExpression*)expression;

/** 
 Creates a TRUNC(expr) function that truncates all of the digits after the decimal place
 of the given numeric expression.
 
 @param expression The numeric expression.
 @return The trunc function.
 */
+ (CBLQueryExpression*) trunc: (CBLQueryExpression*)expression;

/** 
 Creates a TRUNC(expr, digits) function that truncates the number of the digits after
 the decimal place of the given numeric expression.
 
 @param expression The numeric expression.
 @param digits The number of digits.
 @return The TRUNC(expr, digits) function.
 */
+ (CBLQueryExpression*) trunc: (CBLQueryExpression*)expression digits: (CBLQueryExpression*)digits;

#pragma mark - String

/** 
 Creates a CONTAINS(expr, substr) function that evaluates whether the given string
 expression conatins the given substring expression or not.
 
 @param expression The string expression.
 @param substring The substring expression.
 @return The CONTAINS(expr, substr) function.
 */
+ (CBLQueryExpression*) contains: (CBLQueryExpression*)expression substring: (CBLQueryExpression*)substring;

/** 
 Creates a LENGTH(expr) function that returns the length of the given string expression.
 
 @param expression The string expression.
 @return The LENGTH(expr) function.
 */
+ (CBLQueryExpression*) length: (CBLQueryExpression*)expression;

/** 
 Creates a LOWER(expr) function that returns the lowercase string of the given string
 expression.
 
 @param expression The string expression.
 @return The LOWER(expr) function.
 */
+ (CBLQueryExpression*) lower:(CBLQueryExpression*)expression;

/** 
 Creates a LTRIM(expr) function that removes the whitespace from the beginning of the
 given string expression.
 
 @param expression The string expression.
 @return The LTRIM(expr) function.
 */
+ (CBLQueryExpression*) ltrim:(CBLQueryExpression*)expression;

/** 
 Creates a RTRIM(expr) function that removes the whitespace from the end of the
 given string expression.
 
 @param expression The string expression.
 @return The RTRIM(expr) function.
 */
+ (CBLQueryExpression*) rtrim:(CBLQueryExpression*)expression;

/** 
 Creates a TRIM(expr) function that removes the whitespace from the beginning and '
 the end of the given string expression.
 
 @param expression The string expression.
 @return The TRIM(expr) function.
 */
+ (CBLQueryExpression*) trim:(CBLQueryExpression*)expression;

/** 
 Creates a UPPER(expr) function that returns the uppercase string of the given string expression.
 
 @param expression The string expression.
 @return The UPPER(expr) function.
 */
+ (CBLQueryExpression*) upper:(CBLQueryExpression*)expression;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
