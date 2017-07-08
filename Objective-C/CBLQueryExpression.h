//
//  CBLQueryExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQuery;
@class CBLQueryMeta;


NS_ASSUME_NONNULL_BEGIN


/** A CBLQueryExpression represents an expression used for constructing a query statement. */
@interface CBLQueryExpression : NSObject

#pragma mark - Property:

/** Create a property expression representing the value of the given property name.
    @param property Property name in the key path format.
    @return A property expression. */
+ (CBLQueryExpression*) property: (NSString*)property;

/** Create a property expression representing the value of the given property name.
    @param property Property name in the key path format.
    @param alias The data source alias name.
    @return A property expression. */
+ (CBLQueryExpression*) property: (NSString*)property from: (nullable NSString*)alias;

#pragma mark - Meta:

/** Get a CBLQueryMeta object, which is a factory object for creating metadata property 
    expressions.
    @return A CBLQueryMeta object. */
+ (CBLQueryMeta*) meta;

/** Get a CBLQueryMeta object for the given data source. The CBLQueryMeta object is a factory
    object for creating metadata property expressions.
    @from   The data source alias name.
    @return A CBLQueryMeta object. */
+ (CBLQueryMeta*) metaFrom: (nullable NSString*)alias;

#pragma mark - Parameter:

/** Create a parameter expression with the given parameter name. 
    @param name The parameter name
    @return A parameter expression. */
+ (CBLQueryExpression *) parameterNamed:(NSString *)name;


#pragma mark - Unary operators:

/** Create a negated expression representing the negated result of the given expression.
    @param expression   The expression to be negated.
    @return A negated expression. */
+ (CBLQueryExpression*) negated: (id)expression;

/** Create a negated expression representing the negated result of the given expression.
    @param expression   The expression to be negated.
    @return A negated expression */
+ (CBLQueryExpression*) not: (id)expression;

#pragma mark - Arithmetic Operators:

/** Create a concat expression to concatenate the current expression with the given expression. 
    @param expression   The expression to be concatenated with.
    @return A concat expression. */
- (CBLQueryExpression*) concat: (id)expression;

/** Create a multiply expression to multiply the current expression by the given expression. 
    @param expression   The expression to be multipled by.
    @return A multiply expression. */
- (CBLQueryExpression*) multiply: (id)expression;

/** Create a divide expression to divide the current expression by the given expression.
    @param expression   The expression to be devided by.
    @return A divide expression. */
- (CBLQueryExpression*) divide: (id)expression;

/** Create a modulo expression to modulo the current expression by the given expression. 
    @param expression   The expression to be moduloed by.
    @return A modulo expression. */
- (CBLQueryExpression*) modulo: (id)expression;

/** Create an add expression to add the given expression to the current expression. 
    @param expression   The expression to add to the current expression.
    @return An add expression. */
- (CBLQueryExpression*) add: (id)expression;

/** Create a subtract expression to subtract the given expression from the current expression. 
    @param expression   The expression to substract from the current expression.
    @return A subtract expression. */
- (CBLQueryExpression*) subtract: (id)expression;

#pragma mark - Comparison operators:

/** Create a less than expression that evaluates whether or not the current expression 
    is less than the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A less than expression. */
- (CBLQueryExpression*) lessThan: (id)expression;

/** Create a NOT less than expression that evaluates whether or not the current expression 
    is not less than the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A NOT less than expression. */
- (CBLQueryExpression*) notLessThan: (id)expression;

/** Create a less than or equal to expression that evaluates whether or not the current
    expression is less than or equal to the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A less than or equal to expression. */
- (CBLQueryExpression*) lessThanOrEqualTo: (id)expression;

/** Create a NOT less than or equal to expression that evaluates whether or not the current
    expression is not less than or equal to the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A NOT less than or equal to expression. */
- (CBLQueryExpression*) notLessThanOrEqualTo: (id)expression;

/** Create a greater than expression that evaluates whether or not the current expression 
    is greater than the given expression. 
    @param expression   The expression to be compared with the current expression.
    @return A greater than expression. */
- (CBLQueryExpression*) greaterThan: (id)expression;

/** Create a NOT greater than expression that evaluates whether or not the current expression 
    is not greater than the given expression. 
    @param expression   the expression to be compared with the current expression.
    @return a NOT greater than expression. */
- (CBLQueryExpression*) notGreaterThan: (id)expression;

/** Create a greater than or equal to expression that evaluates whether or not the current 
    expression is greater than or equal to the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A greater than or equal to expression. */
- (CBLQueryExpression*) greaterThanOrEqualTo: (id)expression;

/** Create a NOT greater than or equal to expression that evaluates whether or not the current 
    expression is not greater than or equal to the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A NOT greater than or equal to expression. */
- (CBLQueryExpression*) notGreaterThanOrEqualTo: (id)expression;

/** Create an equal to expression that evaluates whether or not the current expression is equal 
    to the given expression. 
    @param expression   The expression to be compared with the current expression.
    @return An equal to expression. */
- (CBLQueryExpression*) equalTo: (nullable id)expression;

/** Create a NOT equal to expression that evaluates whether or not the current expression 
    is not equal to the given expression. 
    @param expression   The expression to be compared with the current expression.
    @return A NOT equal to expression. */
- (CBLQueryExpression*) notEqualTo: (nullable id)expression;

#pragma mark - Bitwise operators:

/** Create a logical AND expression that performs logical AND operation with the current expression.
    @param expression   The expression to AND with the current expression.
    @return A logical AND expression. */
- (CBLQueryExpression*) and: (id)expression;

/** Create a logical OR expression that performs logical OR operation with the current expression.
    @param expression   The expression to OR with the current expression.
    @return A logical OR Expression. */
- (CBLQueryExpression*) or: (id)expression;

#pragma mark - Like operators:

/** Create a Like expression that evaluates whether or not the current expression is LIKE 
    the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A Like expression. */
- (CBLQueryExpression*) like: (id)expression;

/** Create a NOT Like expression that evaluates whether or not the current expression is NOT LIKE 
    the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A NOT Like expression. */
- (CBLQueryExpression*) notLike: (id)expression;

#pragma mark - Regex like operators:

/** Create a regex match expression that evaluates whether or not the current expression 
    regex matches the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A regex match expression. */
- (CBLQueryExpression*) regex: (id)expression;

/** Create a regex NOT match expression that evaluates whether or not the current expression
    regex NOT matches the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A regex NOT match expression. */
- (CBLQueryExpression*) notRegex: (id)expression;

#pragma mark - Fulltext search operators:

/** Create a full text match expression that evaluates whether or not the current expression 
    full text matches the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A full text match expression. */
- (CBLQueryExpression*) match: (id)expression;

/** Create a full text NOT match expression that evaluates whether or not the current expression
    full text NOT matches the given expression.
    @param expression   The expression to be compared with the current expression.
    @return A full text NOT match expression. */
- (CBLQueryExpression*) notMatch: (id)expression;

#pragma mark - Null check operators:

/** Create an IS NULL expression that evaluates whether or not the current expression is null.
    @return An IS NULL expression. */
- (CBLQueryExpression*) isNull;

/** Create an IS NOT NULL expression that evaluates whether or not the current expression 
    is NOT null.
    @return An IS NOT NULL expression. */
- (CBLQueryExpression*) notNull;

#pragma mark - is operations:

/** Create an IS expression that evaluates whether or not the current expression is equal to 
    the given expression.
    @param expression   The expression to be compared with the current expression.
    @return An IS expression. */
- (CBLQueryExpression*) is: (id)expression;

/** Create an IS NOT expression that evaluates whether or not the current expression is not equal to
    the given expression.
    @param expression   The expression to be compared with the current expression.
    @return An IS NOT expression. */
- (CBLQueryExpression*) isNot: (id)expression;

#pragma mark - aggregate operators:

/** Create a between expression that evaluates whether or not the current expression is 
    between the given expressions inclusively. 
    @param expression1  The inclusive lower bound expression.
    @param expression2  The inclusive upper bound expression.
    @return A between expression. */
- (CBLQueryExpression*) between: (id)expression1 and: (id)expression2;

/** Create a NOT between expression that evaluates whether or not the current expression is not
    between the given expressions inclusively.
    @param expression1  The inclusive lower bound expression.
    @param expression2  The inclusive upper bound expression.
    @return A NOT between expression. */
- (CBLQueryExpression*) notBetween: (id)expression1 and: (id)expression2;

/** Create an IN expression that evaluates whether or not the current expression is in the 
    given expressions. 
    @param  expressions The expression array to be evaluated with.
    @return An IN exprssion. */
- (CBLQueryExpression*) in: (NSArray*)expressions;

/** Create a NOT IN expression that evaluates whether or not the current expression is not in the
    given expressions.
    @param  expressions The expression array to be evaluated with.
    @return An IN exprssion. */
- (CBLQueryExpression*) notIn: (NSArray*)expressions;

// TODO: Subquery
// - (CBLQueryExpression*) inQuery: (CBLQuery*)query;
// - (CBLQueryExpression*) notInQuery: (CBLQuery*)query;
// - (CBLQueryExpression*) exists: (CBLQuery*)query;
// - (CBLQueryExpression*) notExists: (CBLQuery*)query;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
