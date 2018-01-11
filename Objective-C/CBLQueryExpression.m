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


#pragma mark - Parameter:


+ (CBLQueryExpression*) parameterNamed: (NSString*)name {
    return [[CBLParameterExpression alloc] initWithName: name];
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


- (CBLQueryExpression*) lessThanOrEqualTo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLessThanOrEqualToBinaryExpType];
}


- (CBLQueryExpression*) greaterThan: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLGreaterThanBinaryExpType];
}


- (CBLQueryExpression*) greaterThanOrEqualTo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLGreaterThanOrEqualToBinaryExpType];
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


#pragma mark - Like operators:


- (CBLQueryExpression*) like: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLikeBinaryExpType];
}


#pragma mark - Regex like operators:


- (CBLQueryExpression*) regex: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLRegexLikeBinaryExpType];
}


#pragma mark - IS operations:


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


#pragma mark - Null or Missing check operators:


- (CBLQueryExpression*) isNullOrMissing {
    return [[[CBLUnaryExpression alloc] initWithExpression: self type: CBLUnaryTypeNull] orExpression:
            [[CBLUnaryExpression alloc] initWithExpression: self type: CBLUnaryTypeMissing]];
}


- (CBLQueryExpression*) notNullOrMissing {
    return [[self class] negated: [self isNullOrMissing]];
}


#pragma mark - Bitwise operators:


- (CBLQueryExpression*) andExpression: (id)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[self, expression]
                                                         type: CBLAndCompundExpType];
}


- (CBLQueryExpression*) orExpression: (id)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[self, expression]
                                                         type: CBLOrCompundExpType];
}


#pragma mark - Aggregate operations:


- (CBLQueryExpression*) between: (id)expression1 and: (id)expression2 {
    CBLQueryExpression* aggr =
        [[CBLAggregateExpression alloc] initWithExpressions: @[expression1, expression2]];
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: aggr
                                                          type: CBLBetweenBinaryExpType];
}


#pragma mark - Collection operations:


- (CBLQueryExpression*) in: (NSArray*)expressions {
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


- (id) jsonValue: (id)value {
    if ([value isKindOfClass: [CBLQueryExpression class]])
        return [value asJSON];
    else
        return value;
}


- (id) asJSON {
    // Subclass needs to implement this method:
    return [NSNull null];
}


@end
