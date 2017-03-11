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

@interface CBLQueryExpression : NSObject

+ (CBLQueryExpression*) property: (NSString*)property;
+ (CBLQueryExpression*) group: (CBLQueryExpression*)expression;

// Unary operators:
+ (CBLQueryExpression*) negated: (id)expression;
+ (CBLQueryExpression*) not: (id)expression;

// Arithmetic Operators:
- (CBLQueryExpression*) concat: (id)expression;
- (CBLQueryExpression*) multiply: (id)expression;
- (CBLQueryExpression*) divide: (id)expression;
- (CBLQueryExpression*) modulo: (id)expression;
- (CBLQueryExpression*) add: (id)expression;
- (CBLQueryExpression*) subtract: (id)expression;

// Comparison operators:
- (CBLQueryExpression*) lessThan: (id)expression;
- (CBLQueryExpression*) notLessThan: (id)expression;
- (CBLQueryExpression*) lessThanOrEqualTo: (id)expression;
- (CBLQueryExpression*) notLessThanOrEqualTo: (id)expression;
- (CBLQueryExpression*) greaterThan: (id)expression;
- (CBLQueryExpression*) notGreaterThan: (id)expression;
- (CBLQueryExpression*) greaterThanOrEqualTo: (id)expression;
- (CBLQueryExpression*) notGreaterThanOrEqualTo: (id)expression;
- (CBLQueryExpression*) equalTo: (nullable id)expression;
- (CBLQueryExpression*) notEqualTo: (nullable id)expression;

// Bitwise operators:
- (CBLQueryExpression*) and: (id)expression;
- (CBLQueryExpression*) or: (id)expression;

// Like operators:
- (CBLQueryExpression*) like: (id)expression;
- (CBLQueryExpression*) notLike: (id)expression;
- (CBLQueryExpression*) regex: (id)expression;
- (CBLQueryExpression*) notRegex: (id)expression;
- (CBLQueryExpression*) match: (id)expression;
- (CBLQueryExpression*) notMatch: (id)expression;

// Null operators:
- (CBLQueryExpression*) isNull;
- (CBLQueryExpression*) notNull;

// Is operators:
- (CBLQueryExpression*) is: (id)expression;
- (CBLQueryExpression*) isNot: (id)expression;

// Aggregation operators:
- (CBLQueryExpression*) between: (id)expression1 and: (id)expression2;
- (CBLQueryExpression*) notBetween: (id)expression1 and: (id)expression2;

- (CBLQueryExpression*) inExpressions: (NSArray*)expressions;
- (CBLQueryExpression*) notInExpressions: (NSArray*)expressions;

// TODO: Subquery
// - (CBLQueryExpression*) inQuery: (CBLXQuery*)query;
// - (CBLQueryExpression*) notInQuery: (CBLXQuery*)query;
// - (CBLQueryExpression*) exists: (CBLXQuery*)query;
// - (CBLQueryExpression*) notExists: (CBLXQuery*)query;

@end


NS_ASSUME_NONNULL_END
