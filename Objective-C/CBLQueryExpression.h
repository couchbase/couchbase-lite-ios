//
//  CBLQueryExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQuery;


NS_ASSUME_NONNULL_BEGIN


/** A CBLQueryExpression represents an expression used for constructing a query statement. */
@interface CBLQueryExpression : NSObject

#pragma mark - Property:

/** Create a property expression representing the value of the given property name.
    @param property property name in the key path format.
    @return a property expression. */
+ (CBLQueryExpression*) property: (NSString*)property;


#pragma mark - Unary operators:

/** Create a negated expression representing the negated result of the given expression.
    @param expression   the expression to be negated.
    @return a negated expression. */
+ (CBLQueryExpression*) negated: (id)expression;

/** Create a negated expression representing the negated result of the given expression.
    @param expression   the expression to be negated.
    @return a negated expression */
+ (CBLQueryExpression*) not: (id)expression;

#pragma mark - Arithmetic Operators:

/** Create a concat expression to concatenate the current expression with the given expression. 
    @param expression   the expression to be concatenated with.
    @return a concat expression. */
- (CBLQueryExpression*) concat: (id)expression;

/** Create a multiply expression to multiply the current expression by the given expression. 
    @param expression   the expression to be multipled by.
    @return a multiply expression. */
- (CBLQueryExpression*) multiply: (id)expression;

/** Create a divide expression to divide the current expression by the given expression.
    @param expression   the expression to be devided by.
    @return a divide expression. */
- (CBLQueryExpression*) divide: (id)expression;

/** Create a modulo expression to modulo the current expression by the given expression. 
    @param expression   the expression to be moduloed by.
    @return a modulo expression. */
- (CBLQueryExpression*) modulo: (id)expression;

/** Create an add expression to add the given expression to the current expression. 
    @param expression   the expression to add to the current expression.
    @return an add expression. */
- (CBLQueryExpression*) add: (id)expression;

/** Create a subtract expression to subtract the given expression from the current expression. 
    @param expression   the expression to substract from the current expression.
    @return a subtract expression. */
- (CBLQueryExpression*) subtract: (id)expression;

#pragma mark - Comparison operators:

/** Create a less than expression that evaluates whether or not the current expression 
    is less than the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a less than expression. */
- (CBLQueryExpression*) lessThan: (id)expression;

/** Create a NOT less than expression that evaluates whether or not the current expression 
    is not less than the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a NOT less than expression. */
- (CBLQueryExpression*) notLessThan: (id)expression;

/** Create a less than or equal to expression that evaluates whether or not the current
    expression is less than or equal to the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a less than or equal to expression. */
- (CBLQueryExpression*) lessThanOrEqualTo: (id)expression;

/** Create a NOT less than or equal to expression that evaluates whether or not the current
    expression is not less than or equal to the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a NOT less than or equal to expression. */
- (CBLQueryExpression*) notLessThanOrEqualTo: (id)expression;

/** Create a greater than expression that evaluates whether or not the current expression 
    is greater than the given expression. 
    @param expression   the expression to be compared with the current expression.
    @return a greater than expression. */
- (CBLQueryExpression*) greaterThan: (id)expression;

/** Create a NOT greater than expression that evaluates whether or not the current expression 
    is not greater than the given expression. 
    @param expression   the expression to be compared with the current expression.
    @return a NOT greater than expression. */
- (CBLQueryExpression*) notGreaterThan: (id)expression;

/** Create a greater than or equal to expression that evaluates whether or not the current 
    expression is greater than or equal to the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a greater than or equal to expression. */
- (CBLQueryExpression*) greaterThanOrEqualTo: (id)expression;

/** Create a NOT greater than or equal to expression that evaluates whether or not the current 
    expression is not greater than or equal to the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a NOT greater than or equal to expression. */
- (CBLQueryExpression*) notGreaterThanOrEqualTo: (id)expression;

/** Create an equal to expression that evaluates whether or not the current expression is equal 
    to the given expression. 
    @param expression   the expression to be compared with the current expression.
    @return an equal to expression. */
- (CBLQueryExpression*) equalTo: (nullable id)expression;

/** Create a NOT equal to expression that evaluates whether or not the current expression 
    is not equal to the given expression. 
    @param expression   the expression to be compared with the current expression.
    @return a NOT equal to expression. */
- (CBLQueryExpression*) notEqualTo: (nullable id)expression;

#pragma mark - Bitwise operators:

/** Create a logical AND expression that performs logical AND operation with the current expression.
    @param expression   the expression to AND with the current expression.
    @return a logical AND expression. */
- (CBLQueryExpression*) and: (id)expression;

/** Create a logical OR expression that performs logical OR operation with the current expression.
    @param expression   the expression to OR with the current expression.
    @return a logical OR Expression. */
- (CBLQueryExpression*) or: (id)expression;

#pragma mark - Like operators:

/** Create a Like expression that evaluates whether or not the current expression is LIKE 
    the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a Like expression. */
- (CBLQueryExpression*) like: (id)expression;

/** Create a NOT Like expression that evaluates whether or not the current expression is NOT LIKE 
    the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a NOT Like expression. */
- (CBLQueryExpression*) notLike: (id)expression;

#pragma mark - Regex like operators:

/** Create a regex match expression that evaluates whether or not the current expression 
    regex matches the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a regex match expression. */
- (CBLQueryExpression*) regex: (id)expression;

/** Create a regex NOT match expression that evaluates whether or not the current expression
    regex NOT matches the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a regex NOT match expression. */
- (CBLQueryExpression*) notRegex: (id)expression;

#pragma mark - Fulltext search operators:

/** Create a full text match expression that evaluates whether or not the current expression 
    full text matches the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a full text match expression. */
- (CBLQueryExpression*) match: (id)expression;

/** Create a full text NOT match expression that evaluates whether or not the current expression
    full text NOT matches the given expression.
    @param expression   the expression to be compared with the current expression.
    @return a full text NOT match expression. */
- (CBLQueryExpression*) notMatch: (id)expression;

#pragma mark - Null check operators:

/** Create an IS NULL expression that evaluates whether or not the current expression is null.
    @return an IS NULL expression. */
- (CBLQueryExpression*) isNull;

/** Create an IS NOT NULL expression that evaluates whether or not the current expression 
    is NOT null.
    @return an IS NOT NULL expression. */
- (CBLQueryExpression*) notNull;

#pragma mark - is operations:

/** Create an IS expression that evaluates whether or not the current expression is equal to 
    the given expression.
    @param expression   the expression to be compared with the current expression.
    @return an IS expression. */
- (CBLQueryExpression*) is: (id)expression;

/** Create an IS NOT expression that evaluates whether or not the current expression is not equal to
    the given expression.
    @param expression   the expression to be compared with the current expression.
    @return an IS NOT expression. */
- (CBLQueryExpression*) isNot: (id)expression;

#pragma mark - aggregate operators:

/** Create a between expression that evaluates whether or not the current expression is 
    between the given expressions inclusively. 
    @param expression1  the inclusive lower bound expression.
    @param expression2  the inclusive upper bound expression.
    @return a between expression. */
- (CBLQueryExpression*) between: (id)expression1 and: (id)expression2;

/** Create a NOT between expression that evaluates whether or not the current expression is not
    between the given expressions inclusively.
    @param expression1  the inclusive lower bound expression.
    @param expression2  the inclusive upper bound expression.
    @return a NOT between expression. */
- (CBLQueryExpression*) notBetween: (id)expression1 and: (id)expression2;

/** Create an IN expression that evaluates whether or not the current expression is in the 
    given expressions. 
    @param  expressions the expression array to be evaluated with.
    @return an IN exprssion. */
- (CBLQueryExpression*) in: (NSArray*)expressions;

/** Create a NOT IN expression that evaluates whether or not the current expression is not in the
    given expressions.
    @param  expressions the expression array to be evaluated with.
    @return an IN exprssion. */
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
