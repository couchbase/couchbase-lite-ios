//
//  CBLQueryExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryCollation;


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

#pragma mark - Parameter:

/** 
 Creates a parameter expression with the given parameter name.
 
 @param name The parameter name
 @return The parameter expression.
 */
+ (CBLQueryExpression*) parameterNamed: (NSString*)name;

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


#pragma mark - Unary operators:

/** 
 Creates a negated expression representing the negated result of the given expression.
 
 @param expression The expression to be negated.
 @return The negated expression.
 */
+ (CBLQueryExpression*) negated: (id)expression;

/**
 Creates a negated expression representing the negated result of the given expression.
 
 @param expression The expression to be negated.
 @return The negated expression. 
 */
+ (CBLQueryExpression*) not: (id)expression;

#pragma mark - Arithmetic Operators:

/** 
 Creates a concat expression to concatenate the current expression with the given expression.
 
 @param expression The expression to be concatenated with.
 @return The concat expression.
 */
- (CBLQueryExpression*) concat: (id)expression;

/** 
 Creates a multiply expression to multiply the current expression by the given expression.
 
 @param expression The expression to be multipled by.
 @return The multiply expression.
 */
- (CBLQueryExpression*) multiply: (id)expression;

/** 
 Creates a divide expression to divide the current expression by the given expression.
 
 @param expression The expression to be devided by.
 @return The divide expression.
 */
- (CBLQueryExpression*) divide: (id)expression;

/** 
 Creates a modulo expression to modulo the current expression by the given expression.
 
 @param expression The expression to be moduloed by.
 @return The modulo expression.
 */
- (CBLQueryExpression*) modulo: (id)expression;

/** 
 Creates an add expression to add the given expression to the current expression
 .
 @param expression The expression to add to the current expression.
 @return  The add expression.
 */
- (CBLQueryExpression*) add: (id)expression;

/** 
 Creates a subtract expression to subtract the given expression from the current expression.
 
 @param expression The expression to substract from the current expression.
 @return The subtract expression.
 */
- (CBLQueryExpression*) subtract: (id)expression;

#pragma mark - Comparison operators:

/** 
 Creates a less than expression that evaluates whether or not the current expression
 is less than the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The less than expression.
 */
- (CBLQueryExpression*) lessThan: (id)expression;

/** 
 Creates a less than or equal to expression that evaluates whether or not the current
 expression is less than or equal to the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The less than or equal to expression.
 */
- (CBLQueryExpression*) lessThanOrEqualTo: (id)expression;

/** 
 Creates a greater than expression that evaluates whether or not the current expression
 is greater than the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The greater than expression.
 */
- (CBLQueryExpression*) greaterThan: (id)expression;

/** 
 Creates a greater than or equal to expression that evaluates whether or not the current
 expression is greater than or equal to the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The greater than or equal to expression.
 */
- (CBLQueryExpression*) greaterThanOrEqualTo: (id)expression;

/** 
 Creates an equal to expression that evaluates whether or not the current expression is equal
 to the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return  The equal to expression.
 */
- (CBLQueryExpression*) equalTo: (nullable id)expression;

/** 
 Creates a NOT equal to expression that evaluates whether or not the current expression
 is not equal to the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The NOT equal to expression.
 */
- (CBLQueryExpression*) notEqualTo: (nullable id)expression;

#pragma mark - Bitwise operators:

/** 
 Creates a logical AND expression that performs logical AND operation with the current expression.
 
 @param expression The expression to AND with the current expression.
 @return The logical AND expression.
 */
- (CBLQueryExpression*) andExpression: (id)expression;

/** 
 Creates a logical OR expression that performs logical OR operation with the current expression.
 
 @param expression The expression to OR with the current expression.
 @return The logical OR Expression.
 */
- (CBLQueryExpression*) orExpression: (id)expression;

#pragma mark - Like operators:

/** 
 Creates a Like expression that evaluates whether or not the current expression is LIKE
 the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The Like expression.
 */
- (CBLQueryExpression*) like: (id)expression;

#pragma mark - Regex operators:

/** 
 Creates a regex match expression that evaluates whether or not the current expression
 regex matches the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The regex match expression.
 */
- (CBLQueryExpression*) regex: (id)expression;

#pragma mark - NULL check operators:

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

#pragma mark - IS operators:

/**
 Creates an IS expression that evaluates whether or not the current expression is equal to
 the given expression.
 
 @param expression The expression to be compared with the current expression.
 @return The IS expression.
 */
- (CBLQueryExpression*) is: (id)expression;

/**
 Creates an IS NOT expression that evaluates whether or not the current expression is not equal to
 the given expression.
 @param expression The expression to be compared with the current expression.
 @return The IS NOT expression.
 */
- (CBLQueryExpression*) isNot: (id)expression;

#pragma mark - Aggregate operators:

/** 
 Creates a between expression that evaluates whether or not the current expression is
 between the given expressions inclusively.
 
 @param expression1 The inclusive lower bound expression.
 @param expression2 The inclusive upper bound expression.
 @return The between expression.
 */
- (CBLQueryExpression*) between: (id)expression1 and: (id)expression2;

#pragma mark - Collection operators:

/** 
 Creates an IN expression that evaluates whether or not the current expression is in the
 given expressions.
 
 @param expressions The expression array to be evaluated with.
 @return The IN exprssion.
 */
- (CBLQueryExpression*) in: (NSArray*)expressions;

/** 
 Creates a NOT IN expression that evaluates whether or not the current expression is not in the
 given expressions.
 
 @param expressions The expression array to be evaluated with.
 @return The IN exprssion.
 */
- (CBLQueryExpression*) notIn: (NSArray*)expressions;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
