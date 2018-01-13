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
#import "CBLUnaryExpression.h"
#import "CBLValueExpression.h"
#import "CBLJSON.h"

@implementation CBLQueryExpression


#pragma mark - Property:


+ (CBLQueryExpression*) property: (NSString*)property {
    return [self property: property from: nil];
}


+ (CBLQueryExpression*) property: (NSString*)property from: (NSString *)alias {
    return [[CBLPropertyExpression alloc] initWithKeyPath: property
                                               columnName: nil
                                                     from: alias];
}


+ (CBLQueryExpression*) all {
    return [self allFrom: nil];
}


+ (CBLQueryExpression*) allFrom: (NSString*)alias {
    return [CBLPropertyExpression allFrom: alias];
}


#pragma mark - Values:


+ (CBLQueryExpression*) value: (nullable id)value {
    return [[CBLValueExpression alloc] initWithValue: value];
}


+ (CBLQueryExpression*) string: (nullable NSString*)value {
    return [self value: value];
}


+ (CBLQueryExpression*) number: (nullable NSNumber*)value {
    return [self value: value];
}


+ (CBLQueryExpression*) integer: (NSInteger)value {
    return [self value: @(value)];
}


+ (CBLQueryExpression*) longLong: (long long)value {
    return [self value: @(value)];
}


+ (CBLQueryExpression*) float: (float)value {
    return [self value: @(value)];
}


+ (CBLQueryExpression*) double: (double)value {
    return [self value: @(value)];
}


+ (CBLQueryExpression*) boolean: (BOOL)value {
    return [self value: @(value)];
}


+ (CBLQueryExpression*) date: (nullable NSDate*)value {
    return [self value: value];
}


#pragma mark - Parameter:


+ (CBLQueryExpression*) parameterNamed: (NSString*)name {
    return [[CBLParameterExpression alloc] initWithName: name];
}


#pragma mark - Unary operators:


+ (CBLQueryExpression*) negated: (CBLQueryExpression*)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[expression]
                                                         type: CBLNotCompundExpType];
}


+ (CBLQueryExpression*) not: (CBLQueryExpression*)expression {
    return [self negated: expression];
}


#pragma mark - Arithmetic Operators:


- (CBLQueryExpression*) multiply: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLMultiplyBinaryExpType];
}


- (CBLQueryExpression*) divide: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLDivideBinaryExpType];
}


- (CBLQueryExpression*) modulo: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLModulusBinaryExpType];
}


- (CBLQueryExpression*) add: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLAddBinaryExpType];
}


- (CBLQueryExpression*) subtract: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLSubtractBinaryExpType];
}


#pragma mark - Comparison operators:


- (CBLQueryExpression*) lessThan: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLessThanBinaryExpType];
}


- (CBLQueryExpression*) lessThanOrEqualTo: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLessThanOrEqualToBinaryExpType];
}


- (CBLQueryExpression*) greaterThan: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLGreaterThanBinaryExpType];
}


- (CBLQueryExpression*) greaterThanOrEqualTo: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLGreaterThanOrEqualToBinaryExpType];
}


- (CBLQueryExpression*) equalTo: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLEqualToBinaryExpType];
}


- (CBLQueryExpression*) notEqualTo: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLNotEqualToBinaryExpType];
}


#pragma mark - Like operators:


- (CBLQueryExpression*) like: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLikeBinaryExpType];
}


#pragma mark - Regex like operators:


- (CBLQueryExpression*) regex: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLRegexLikeBinaryExpType];
}


#pragma mark - IS operations:


- (CBLQueryExpression*) is: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLIsBinaryExpType];
}


- (CBLQueryExpression*) isNot: (CBLQueryExpression*)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLIsNotBinaryExpType];
}


#pragma mark - Null or Missing check operators:


- (CBLQueryExpression*) isNullOrMissing {
    return [[[CBLUnaryExpression alloc] initWithExpression: self type: CBLUnaryTypeNull] orExpression:
            [[CBLUnaryExpression alloc] initWithExpression: self type: CBLUnaryTypeMissing]];
}


- (CBLQueryExpression*) notNullOrMissing {
    return [[self class] negated: [self isNullOrMissing]];
}


#pragma mark - Bitwise operators:


- (CBLQueryExpression*) andExpression: (CBLQueryExpression*)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[self, expression]
                                                         type: CBLAndCompundExpType];
}


- (CBLQueryExpression*) orExpression: (CBLQueryExpression*)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[self, expression]
                                                         type: CBLOrCompundExpType];
}


#pragma mark - Aggregate operations:


- (CBLQueryExpression*) between: (CBLQueryExpression*)expression1 and: (CBLQueryExpression*)expression2 {
    CBLQueryExpression* aggr =
        [[CBLAggregateExpression alloc] initWithExpressions: @[expression1, expression2]];
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: aggr
                                                          type: CBLBetweenBinaryExpType];
}


#pragma mark - Collection operations:


- (CBLQueryExpression*) in: (NSArray<CBLQueryExpression*>*)expressions {
    CBLQueryExpression* aggr =
        [[CBLAggregateExpression alloc] initWithExpressions: expressions];
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: aggr
                                                          type: CBLInBinaryExpType];
}


#pragma mark - Collation:


- (CBLQueryExpression*) collate: (CBLQueryCollation*)collation {
    return [[CBLCollationExpression alloc] initWithOperand: self collation: collation];
}


#pragma mark - Internal 


- (instancetype) initWithNone {
    return [super init];
}


- (NSString*) description {
    NSString* desc = [CBLJSON stringWithJSONObject: [self asJSON] options: 0 error: nil];
    return [NSString stringWithFormat: @"%@[json=%@]", self.class, desc];
}

/*
- (id) jsonValue: (id)value {
    if ([value isKindOfClass: [CBLQueryExpression class]])
        return [value asJSON];
    else
        return value;
}
*/

- (id) asJSON {
    // Subclass needs to implement this method:
    return [NSNull null];
}


@end
