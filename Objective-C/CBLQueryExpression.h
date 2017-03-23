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

/** Create a property keypath expression. */
+ (CBLQueryExpression*) property: (NSString*)property;


#pragma mark - Unary operators:

/** Create a negated expression. */
+ (CBLQueryExpression*) negated: (id)expression;

/** Create a negated expression. */
+ (CBLQueryExpression*) not: (id)expression;

#pragma mark - Arithmetic Operators:

/** Create a string concatinate expression. */
- (CBLQueryExpression*) concat: (id)expression;

/** Create a multiply operation expression. */
- (CBLQueryExpression*) multiply: (id)expression;

/** Create a divide operation expression. */
- (CBLQueryExpression*) divide: (id)expression;

/** Create a modulus operation expression. */
- (CBLQueryExpression*) modulo: (id)expression;

/** Create an add operation expression. */
- (CBLQueryExpression*) add: (id)expression;

/** Create an subtract operation expression. */
- (CBLQueryExpression*) subtract: (id)expression;

#pragma mark - Comparison operators:

/** Create a less than comparison expression. */
- (CBLQueryExpression*) lessThan: (id)expression;

/** Create a NOT less than comparison expression. */
- (CBLQueryExpression*) notLessThan: (id)expression;

/** Create a less than or equal to comparison expression. */
- (CBLQueryExpression*) lessThanOrEqualTo: (id)expression;

/** Create a NOT less than or equal to comparison expression. */
- (CBLQueryExpression*) notLessThanOrEqualTo: (id)expression;

/** Create a greater then comparison expression. */
- (CBLQueryExpression*) greaterThan: (id)expression;

/** Create a NOT greater then comparison expression. */
- (CBLQueryExpression*) notGreaterThan: (id)expression;

/** Create a greather than or equal to comparison expression. */
- (CBLQueryExpression*) greaterThanOrEqualTo: (id)expression;

/** Create a NOT greather than or equal comparison expression. */
- (CBLQueryExpression*) notGreaterThanOrEqualTo: (id)expression;

/** Create an equal to comparison expression. */
- (CBLQueryExpression*) equalTo: (nullable id)expression;

/** Create a NOT equal to comparison expression. */
- (CBLQueryExpression*) notEqualTo: (nullable id)expression;

#pragma mark - Bitwise operators:

/** Create an AND operation expression. */
- (CBLQueryExpression*) and: (id)expression;

/** Create an OR operation expression. */
- (CBLQueryExpression*) or: (id)expression;

#pragma mark - Like operators:

/** Create a LIKE comparison expression. */
- (CBLQueryExpression*) like: (id)expression;

/** Create a NOT LIKE comparison expression. */
- (CBLQueryExpression*) notLike: (id)expression;

#pragma mark - Regex like operators:

/** Create a REGEX_LIKE comparison expression. */
- (CBLQueryExpression*) regex: (id)expression;

/** Create a NOT REGEX_LIKE comparison expression. */
- (CBLQueryExpression*) notRegex: (id)expression;

#pragma mark - Fulltext search operators:

/** Create a fulltext search matching expression. */
- (CBLQueryExpression*) match: (id)expression;

/** Create a fulltext search NOT matching expression. */
- (CBLQueryExpression*) notMatch: (id)expression;

#pragma mark - Null check operators:

/** Create a null check expression. */
- (CBLQueryExpression*) isNull;

/** Create a NOT null check expression. */
- (CBLQueryExpression*) notNull;

#pragma mark - is operations:

/** Create an is comparsion expression. The is comparison is the same as an equal to comparison. */
- (CBLQueryExpression*) is: (id)expression;

/** Create an is NOT comparsion expression. */
- (CBLQueryExpression*) isNot: (id)expression;

#pragma mark - aggregate operators:

/** Create a between expression. */
- (CBLQueryExpression*) between: (id)expression1 and: (id)expression2;

/** Create a NOT between expression. */
- (CBLQueryExpression*) notBetween: (id)expression1 and: (id)expression2;

/** Create a IN expression. */
- (CBLQueryExpression*) in: (NSArray*)expressions;

/** Create a NOT IN expression. */
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
