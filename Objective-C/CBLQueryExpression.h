//
//  CBLQueryExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLXQuery;


NS_ASSUME_NONNULL_BEGIN


/** A CBLQueryExpression represents an expression used for constructing a query statement. */
@interface CBLQueryExpression : NSObject

#pragma mark - Property:

/** Construct a property keypath expression. */
+ (CBLQueryExpression*) property: (NSString*)property;


#pragma mark - Unary operators:

/** Construct a negated expression. */
+ (CBLQueryExpression*) negated: (id)expression;

/** Construct a negated expression. */
+ (CBLQueryExpression*) not: (id)expression;

#pragma mark - Arithmetic Operators:

/** Construct a string concatinate expression. */
- (CBLQueryExpression*) concat: (id)expression;

/** Construct a multiply operation expression. */
- (CBLQueryExpression*) multiply: (id)expression;

/** Construct a divide operation expression. */
- (CBLQueryExpression*) divide: (id)expression;

/** Construct a modulus operation expression. */
- (CBLQueryExpression*) modulo: (id)expression;

/** Construct an add operation expression. */
- (CBLQueryExpression*) add: (id)expression;

/** Construct an subtract operation expression. */
- (CBLQueryExpression*) subtract: (id)expression;

#pragma mark - Comparison operators:

/** Construct a less than comparison expression. */
- (CBLQueryExpression*) lessThan: (id)expression;

/** Construct a NOT less than comparison expression. */
- (CBLQueryExpression*) notLessThan: (id)expression;

/** Construct a less than or equal to comparison expression. */
- (CBLQueryExpression*) lessThanOrEqualTo: (id)expression;

/** Construct a NOT less than or equal to comparison expression. */
- (CBLQueryExpression*) notLessThanOrEqualTo: (id)expression;

/** Construct a greater then comparison expression. */
- (CBLQueryExpression*) greaterThan: (id)expression;

/** Construct a NOT greater then comparison expression. */
- (CBLQueryExpression*) notGreaterThan: (id)expression;

/** Construct a greather than or equal to comparison expression. */
- (CBLQueryExpression*) greaterThanOrEqualTo: (id)expression;

/** Construct a NOT greather than or equal comparison expression. */
- (CBLQueryExpression*) notGreaterThanOrEqualTo: (id)expression;

/** Construct an equal to comparison expression. */
- (CBLQueryExpression*) equalTo: (nullable id)expression;

/** Construct a NOT equal to comparison expression. */
- (CBLQueryExpression*) notEqualTo: (nullable id)expression;

#pragma mark - Bitwise operators:

/** Construct an AND operation expression. */
- (CBLQueryExpression*) and: (id)expression;

/** Construct an OR operation expression. */
- (CBLQueryExpression*) or: (id)expression;

#pragma mark - Like operators:

/** Construct a LIKE comparison expression. */
- (CBLQueryExpression*) like: (id)expression;

/** Construct a NOT LIKE comparison expression. */
- (CBLQueryExpression*) notLike: (id)expression;

#pragma mark - Regex like operators:

/** Construct a REGEX_LIKE comparison expression. */
- (CBLQueryExpression*) regex: (id)expression;

/** Construct a NOT REGEX_LIKE comparison expression. */
- (CBLQueryExpression*) notRegex: (id)expression;

#pragma mark - Fulltext search operators:

/** Construct a fulltext search matching expression. */
- (CBLQueryExpression*) match: (id)expression;

/** Construct a fulltext search NOT matching expression. */
- (CBLQueryExpression*) notMatch: (id)expression;

#pragma mark - Null check operators:

/** Construct a null check expression. */
- (CBLQueryExpression*) isNull;

/** Construct a NOT null check expression. */
- (CBLQueryExpression*) notNull;

#pragma mark - is operations:

/** Construct an is comparsion expression. The is comparison is the same as an equal to comparison. */
- (CBLQueryExpression*) is: (id)expression;

/** Construct an is NOT comparsion expression. */
- (CBLQueryExpression*) isNot: (id)expression;

#pragma mark - aggregate operators:

/** Construct a between expression. */
- (CBLQueryExpression*) between: (id)expression1 and: (id)expression2;

/** Construct a NOT between expression. */
- (CBLQueryExpression*) notBetween: (id)expression1 and: (id)expression2;

/** Construct a IN expression. */
- (CBLQueryExpression*) inExpressions: (NSArray*)expressions;

/** Construct a NOT IN expression. */
- (CBLQueryExpression*) notInExpressions: (NSArray*)expressions;

// TODO: Subquery
// - (CBLQueryExpression*) inQuery: (CBLXQuery*)query;
// - (CBLQueryExpression*) notInQuery: (CBLXQuery*)query;
// - (CBLQueryExpression*) exists: (CBLXQuery*)query;
// - (CBLQueryExpression*) notExists: (CBLXQuery*)query;

@end


NS_ASSUME_NONNULL_END
