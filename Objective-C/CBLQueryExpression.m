//
//  CBLQueryExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryExpression.h"
#import "CBLQuery+Internal.h"

#import "CBLAggregateExpression.h"
#import "CBLBinaryExpression.h"
#import "CBLCollationExpression.h"
#import "CBLCompoundExpression.h"
#import "CBLParameterExpression.h"
#import "CBLPropertyExpression.h"
#import "CBLQuantifiedExpression.h"
#import "CBLUnaryExpression.h"
#import "CBLVariableExpression.h"

@implementation CBLQueryExpression


#pragma mark - Property:


+ (CBLQueryExpression*) property: (NSString*)property {
    return [self property: property from: nil];
}


+ (CBLQueryExpression*) property: (NSString*)property from:(NSString *)alias {
    return [[CBLPropertyExpression alloc] initWithKeyPath: property
                                               columnName: nil
                                                     from: alias];
}


#pragma mark - Meta:


+ (CBLQueryMeta*) meta {
    return [self metaFrom: nil];
}


+ (CBLQueryMeta*) metaFrom: (NSString*)alias {
    return [[CBLQueryMeta alloc] initWithFrom: alias];
}


#pragma mark - Parameter:


+ (CBLQueryExpression*) parameterNamed: (NSString*)name {
    return [[CBLParameterExpression alloc] initWithName: name];
}


#pragma mark - Collation:


- (CBLQueryExpression*) collate: (CBLQueryCollation*)collation {
    return [[CBLCollationExpression alloc] initWithOperand: self collation: collation];
}


#pragma mark - Unary operators:


+ (CBLQueryExpression*) negated: (id)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[expression]
                                                         type: CBLNotCompundExpType];
}


+ (CBLQueryExpression*) not: (id)expression {
    return [self negated: expression];
}


#pragma mark - Arithmetic Operators:


- (CBLQueryExpression*) concat: (id)expression {
    Assert(NO, @"Unsupported operation");
}


- (CBLQueryExpression*) multiply: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLMultiplyBinaryExpType];
}


- (CBLQueryExpression*) divide: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLDivideBinaryExpType];
}


- (CBLQueryExpression*) modulo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLModulusBinaryExpType];
}


- (CBLQueryExpression*) add: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLAddBinaryExpType];
}


- (CBLQueryExpression*) subtract: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLSubtractBinaryExpType];
}


#pragma mark - Comparison operators:


- (CBLQueryExpression*) lessThan: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLessThanBinaryExpType];
}


- (CBLQueryExpression*) notLessThan: (id)expression {
    return [self greaterThanOrEqualTo: expression];
}


- (CBLQueryExpression*) lessThanOrEqualTo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLessThanOrEqualToBinaryExpType];
}


- (CBLQueryExpression*) notLessThanOrEqualTo: (id)expression {
    return [self greaterThan: expression];
}


- (CBLQueryExpression*) greaterThan: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLGreaterThanBinaryExpType];
}


- (CBLQueryExpression*) notGreaterThan: (id)expression {
    return [self lessThanOrEqualTo: expression];
}


- (CBLQueryExpression*) greaterThanOrEqualTo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLGreaterThanOrEqualToBinaryExpType];
}


- (CBLQueryExpression*) notGreaterThanOrEqualTo: (id)expression {
    return [self lessThan: expression];
}


- (CBLQueryExpression*) equalTo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLEqualToBinaryExpType];
}


- (CBLQueryExpression*) notEqualTo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLNotEqualToBinaryExpType];
}


#pragma mark - Bitwise operators:


- (CBLQueryExpression*) and: (id)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[self, expression]
                                                         type: CBLAndCompundExpType];
}


- (CBLQueryExpression*) or: (id)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[self, expression]
                                                         type: CBLOrCompundExpType];
}


#pragma mark - Like operators:


- (CBLQueryExpression*) like: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLikeBinaryExpType];
}


- (CBLQueryExpression*) notLike: (id)expression {
    return [[self class] negated: [self like: expression]];
}


#pragma mark - Regex like operators:


- (CBLQueryExpression*) regex: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLRegexLikeBinaryExpType];
}


- (CBLQueryExpression*) notRegex: (id)expression {
    return [[self class] negated: [self regex: expression]];
}


#pragma mark - Fulltext search operators:


- (CBLQueryExpression*) match: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLMatchesBinaryExpType];
}


- (CBLQueryExpression*) notMatch: (id)expression {
    return [[self class] negated: [self match: expression]];
}


#pragma mark - Null check operators:


- (CBLQueryExpression*) isNullOrMissing {
    return [[[CBLUnaryExpression alloc] initWithExpression: self type: CBLUnaryTypeNull] or:
            [[CBLUnaryExpression alloc] initWithExpression: self type: CBLUnaryTypeMissing]];
}


- (CBLQueryExpression*) notNullOrMissing {
    return [[self class] negated: [self isNullOrMissing]];
}


#pragma mark - is operations:


- (CBLQueryExpression*) is: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLIsBinaryExpType];
}


- (CBLQueryExpression*) isNot: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLIsNotBinaryExpType];
}


#pragma mark - Aggregate operations:


- (CBLQueryExpression*) between: (id)expression1 and: (id)expression2 {
    CBLQueryExpression* aggr =
        [[CBLAggregateExpression alloc] initWithExpressions: @[expression1, expression2]];
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: aggr
                                                          type: CBLBetweenBinaryExpType];
}


- (CBLQueryExpression*) notBetween: (id)exp1 and: (id)exp2 {
    return [[self class] negated: [self between: exp1 and: exp2]];
}


#pragma mark - Collection operations:


- (CBLQueryExpression*) in: (NSArray*)expressions {
    CBLQueryExpression* aggr =
        [[CBLAggregateExpression alloc] initWithExpressions: expressions];
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: aggr
                                                          type: CBLInBinaryExpType];
}


- (CBLQueryExpression*) notIn: (NSArray*)expressions {
    return [[self class] negated: [self in: expressions]];
}


#pragma mark - Quantified operations:


+ (CBLQueryExpression*) variableNamed: (NSString*)name {
    return [[CBLVariableExpression alloc] initWithVariableNamed: name];
}


+ (CBLQueryExpression*) any: (NSString*)variableName
                         in: (id)inExpression
                  satisfies: (CBLQueryExpression*)satisfies
{
    return [[CBLQuantifiedExpression alloc] initWithType: CBLQuantifiedTypeAny
                                                variable: variableName
                                                      in: inExpression
                                               satisfies: satisfies];
}


+ (CBLQueryExpression*) anyAndEvery: (NSString*)variableName
                                 in: (id)inExpression
                          satisfies: (CBLQueryExpression*)satisfies
{
    return [[CBLQuantifiedExpression alloc] initWithType: CBLQuantifiedTypeAnyAndEvery
                                                variable: variableName
                                                      in: inExpression
                                               satisfies: satisfies];
}


+ (CBLQueryExpression*) every: (NSString*)variableName
                           in: (id)inExpression
                    satisfies: (CBLQueryExpression*)satisfies
{
    return [[CBLQuantifiedExpression alloc] initWithType: CBLQuantifiedTypeEvery
                                                variable: variableName
                                                      in: inExpression
                                               satisfies: satisfies];
}


#pragma mark - Internal 


- (instancetype) initWithNone {
    return [super init];
}


- (id) asJSON {
    // Subclass needs to implement this method:
    return [NSNull null];
}


- (NSString*) description {
    NSData* data = [NSJSONSerialization dataWithJSONObject: [self asJSON] options: 0 error: nil];
    NSString* desc = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    return [NSString stringWithFormat: @"%@[json=%@]", self.class, desc];
}

@end
