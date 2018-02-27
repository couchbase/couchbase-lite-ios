//
//  CBLQueryExpression.h
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
@class CBLQueryCollation;
@class CBLVariableExpression;

NS_ASSUME_NONNULL_BEGIN


/** 
 A CBLQueryExpression represents an expression used for constructing a query statement.
 */
@interface CBLQueryExpression : NSObject

#pragma mark - Property:

/** 
 Creates a property expression representing the value of the given property name.
 
 @param property The property name in the key path format.
 @return The property expression.
 */
+ (CBLQueryExpression*) property: (NSString*)property;

/** 
 Creates a property expression representing the value of the given property name.
 
 @param property Property name in the key path format.
 @param alias The data source alias name.
 @return The property expression.
 */
+ (CBLQueryExpression*) property: (NSString*)property from: (nullable NSString*)alias;

/**
 Creates a * expression to express all properties.

 @return The star expression.
 */
+ (CBLQueryExpression*) all;

/**
 Creates a * expression to express all properties of the given datasource.

 @param alias The data source alias name.
 @return The star expression.
 */
+ (CBLQueryExpression*) allFrom: (nullable NSString*)alias;

#pragma mark - Value:

/**
 Creates a value expresion. The supported value types are NSString,
 NSNumber, NSInteger, long long, float, double, boolean, NSDate and
 null.

 @param value The value.
 @return The value expression.
 */
+ (CBLQueryExpression*) value: (nullable id)value;

/**
 Creates a string expression.

 @param value The string value.
 @return The string expression.
 */
+ (CBLQueryExpression*) string: (nullable NSString*)value;

/**
 Creates a number expression.

 @param value The number value.
 @return The number expression.
 */
+ (CBLQueryExpression*) number: (nullable NSNumber*)value;

/**
 Creates an integer expression.

 @param value The integer value.
 @return The integer expression.
 */
+ (CBLQueryExpression*) integer: (NSInteger)value;

/**
 Creates a long long expression.

 @param value The long long value.
 @return The long long expression.
 */
+ (CBLQueryExpression*) longLong: (long long)value;

/**
 Creates a float expression.

 @param value The float value.
 @return The float expression.
 */
+ (CBLQueryExpression*) float: (float)value;

/**
 Creates a double expression.

 @param value The double value.
 @return The double expression.
 */
+ (CBLQueryExpression*) double: (double)value;

/**
 Creates a boolean expression.

 @param value The boolean value.
 @return The boolean expression.
 */
+ (CBLQueryExpression*) boolean: (BOOL)value;

/**
 Creates a date expression.

 @param value The date value.
 @return The date expression.
 */
+ (CBLQueryExpression*) date: (nullable NSDate*)value;

#pragma mark - Parameter:

/** 
 Creates a parameter expression with the given parameter name.
 
 @param name The parameter name
 @return The parameter expression.
 */
+ (CBLQueryExpression*) parameterNamed: (NSString*)name;

#pragma mark - Unary operators:

/** 
 Creates a negated expression representing the negated result of the given expression.
 
 @param expression The expression to be negated.
 @return The negated expression.
 */
+ (CBLQueryExpression*) negated: (CBLQueryExpression*)expression;

/**
 Creates a negated expression representing the negated result of the given expression.
 
 @param expression The expression to be negated.
 @return The negated expression. 
 */
+ (CBLQueryExpression*) not: (CBLQueryExpression*)expression;

#pragma mark - Arithmetic Operators:

/** 
 Creates a multiply expression to multiply the current expression by the given expression.
 
 @param expression The expression to be multipled by.
 @return The multiply expression.
 */
- (CBLQueryExpression*) multiply: (CBLQueryExpression*)expression;

/** 
 Creates a divide expression to divide the current expression by the given expression.
 
 @param expression The expression to be devided by.
 @return The divide expression.
 */
- (CBLQueryExpression*) divide: (CBLQueryExpression*)expression;

/** 
 Creates a modulo expression to modulo the current expression by the given expression.
 
 @param expression The expression to be moduloed by.
 @return The modulo expression.
 */
- (CBLQueryExpression*) modulo: (CBLQueryExpression*)expression;

/** 
 Creates an add expression to add the given expression to the current expression
 .
 @param expression The expression to add to the current expression.
 @return  The add expression.
 */
- (CBLQueryExpression*) add: (CBLQueryExpression*)expression;

/** 
 Creates a subtract expression to subtract the given expression from the current expression.
 
 @param expression The expression to substract from the current expression.
 @return The subtract expression.
 */
- (CBLQueryExpression*) subtract: (CBLQueryExpression*)expression;

#pragma mark - Comparison operators:

/** 
 Creates a less than expression that evaluates whether or not the current expression
 is less than the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The less than expression.
 */
- (CBLQueryExpression*) lessThan: (CBLQueryExpression*)expression;

/** 
 Creates a less than or equal to expression that evaluates whether or not the current
 expression is less than or equal to the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The less than or equal to expression.
 */
- (CBLQueryExpression*) lessThanOrEqualTo: (CBLQueryExpression*)expression;

/** 
 Creates a greater than expression that evaluates whether or not the current expression
 is greater than the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The greater than expression.
 */
- (CBLQueryExpression*) greaterThan: (CBLQueryExpression*)expression;

/** 
 Creates a greater than or equal to expression that evaluates whether or not the current
 expression is greater than or equal to the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The greater than or equal to expression.
 */
- (CBLQueryExpression*) greaterThanOrEqualTo: (CBLQueryExpression*)expression;

/** 
 Creates an equal to expression that evaluates whether or not the current expression is equal
 to the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return  The equal to expression.
 */
- (CBLQueryExpression*) equalTo: (CBLQueryExpression*)expression;

/** 
 Creates a NOT equal to expression that evaluates whether or not the current expression
 is not equal to the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The NOT equal to expression.
 */
- (CBLQueryExpression*) notEqualTo: (CBLQueryExpression*)expression;

#pragma mark - Like operators:

/** 
 Creates a Like expression that evaluates whether or not the current expression is LIKE
 the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The Like expression.
 */
- (CBLQueryExpression*) like: (CBLQueryExpression*)expression;

#pragma mark - Regex operators:

/** 
 Creates a regex match expression that evaluates whether or not the current expression
 regex matches the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The regex match expression.
 */
- (CBLQueryExpression*) regex: (CBLQueryExpression*)expression;

#pragma mark - IS operators:

/**
 Creates an IS expression that evaluates whether or not the current expression is equal to
 the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The IS expression.
 */
- (CBLQueryExpression*) is: (CBLQueryExpression*)expression;

/**
 Creates an IS NOT expression that evaluates whether or not the current expression is not equal to
 the given expression.
 @param expression The expression to be compared with the current expression.
 @return The IS NOT expression.
 */
- (CBLQueryExpression*) isNot: (CBLQueryExpression*)expression;

#pragma mark - NULL or MISSING check operators:

/** 
 Creates an IS NULL OR MISSING expression that evaluates whether or not the current expression
 is null or missing.
 
 @return The IS NULL OR MISSING expression.
 */
- (CBLQueryExpression*) isNullOrMissing;

/** 
 Creates an IS NOT NULL OR MISSING expression that evaluates whether or not the current expression
 is NOT null or missing.
 
 @return The IS NOT NULL OR MISSING expression.
 */
- (CBLQueryExpression*) notNullOrMissing;

#pragma mark - Bitwise operators:

/**
 Creates a logical AND expression that performs logical AND operation with the current expression.
 
 @param expression The expression to AND with the current expression.
 @return The logical AND expression.
 */
- (CBLQueryExpression*) andExpression: (CBLQueryExpression*)expression;

/**
 Creates a logical OR expression that performs logical OR operation with the current expression.
 
 @param expression The expression to OR with the current expression.
 @return The logical OR Expression.
 */
- (CBLQueryExpression*) orExpression: (CBLQueryExpression*)expression;

#pragma mark - Aggregate operators:

/** 
 Creates a between expression that evaluates whether or not the current expression is
 between the given expressions inclusively.
 
 @param expression1 The inclusive lower bound expression.
 @param expression2 The inclusive upper bound expression.
 @return The between expression.
 */
- (CBLQueryExpression*) between: (CBLQueryExpression*)expression1 and: (CBLQueryExpression*)expression2;

#pragma mark - Collection operators:

/** 
 Creates an IN expression that evaluates whether or not the current expression is in the
 given expressions.
 
 @param expressions The expression array to be evaluated with.
 @return The IN exprssion.
 */
- (CBLQueryExpression*) in: (NSArray<CBLQueryExpression*>*)expressions;

#pragma mark - Collation:

/**
 Creates a collate expression with the given Collation specification. Commonly
 the collate expression is used in the Order BY clause or the string comparison
 expression (e.g. equalTo or lessThan) to specify how the two strings are
 compared.
 
 @param collation The Collation object.
 @return The collate expression.
 */
- (CBLQueryExpression*) collate: (CBLQueryCollation*)collation;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end



NS_ASSUME_NONNULL_END
