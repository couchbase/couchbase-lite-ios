//
//  CBLQueryExpression.m
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


+ (CBLQueryExpression*) property: (NSString*)property from: (nullable NSString *)alias {
    CBLAssertNotNil(property);
    
    return [[CBLPropertyExpression alloc] initWithKeyPath: property
                                               columnName: nil
                                                     from: alias];
}


+ (CBLQueryExpression*) all {
    return [self allFrom: nil];
}


+ (CBLQueryExpression*) allFrom: (nullable NSString*)alias {
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


+ (CBLQueryExpression*) dictionary: (nullable NSDictionary<NSString*,id>*)value {
    return [self value: value];
}


+ (CBLQueryExpression*) array: (nullable NSArray*)value {
    return [self value: value];
}

#pragma mark - Parameter:


+ (CBLQueryExpression*) parameterNamed: (NSString*)name {
    CBLAssertNotNil(name);
    
    return [[CBLParameterExpression alloc] initWithName: name];
}


#pragma mark - Unary operators:


+ (CBLQueryExpression*) negated: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLCompoundExpression alloc] initWithExpressions: @[expression]
                                                         type: CBLNotCompundExpType];
}


+ (CBLQueryExpression*) not: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [self negated: expression];
}


#pragma mark - Arithmetic Operators:


- (CBLQueryExpression*) multiply: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLMultiplyBinaryExpType];
}


- (CBLQueryExpression*) divide: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLDivideBinaryExpType];
}


- (CBLQueryExpression*) modulo: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLModulusBinaryExpType];
}


- (CBLQueryExpression*) add: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
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
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLessThanBinaryExpType];
}


- (CBLQueryExpression*) lessThanOrEqualTo: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLessThanOrEqualToBinaryExpType];
}


- (CBLQueryExpression*) greaterThan: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLGreaterThanBinaryExpType];
}


- (CBLQueryExpression*) greaterThanOrEqualTo: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLGreaterThanOrEqualToBinaryExpType];
}


- (CBLQueryExpression*) equalTo: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLEqualToBinaryExpType];
}


- (CBLQueryExpression*) notEqualTo: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLNotEqualToBinaryExpType];
}


#pragma mark - Like operators:


- (CBLQueryExpression*) like: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLikeBinaryExpType];
}


#pragma mark - Regex like operators:


- (CBLQueryExpression*) regex: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLRegexLikeBinaryExpType];
}


#pragma mark - IS operations:


- (CBLQueryExpression*) is: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLIsBinaryExpType];
}


- (CBLQueryExpression*) isNot: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
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
    CBLAssertNotNil(expression);
    
    return [[CBLCompoundExpression alloc] initWithExpressions: @[self, expression]
                                                         type: CBLAndCompundExpType];
}


- (CBLQueryExpression*) orExpression: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLCompoundExpression alloc] initWithExpressions: @[self, expression]
                                                         type: CBLOrCompundExpType];
}


#pragma mark - Aggregate operations:


- (CBLQueryExpression*) between: (CBLQueryExpression*)expression1 and: (CBLQueryExpression*)expression2 {
    CBLAssertNotNil(expression1);
    CBLAssertNotNil(expression2);
    
    CBLQueryExpression* aggr =
        [[CBLAggregateExpression alloc] initWithExpressions: @[expression1, expression2]];
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: aggr
                                                          type: CBLBetweenBinaryExpType];
}


#pragma mark - Collection operations:


- (CBLQueryExpression*) in: (NSArray<CBLQueryExpression*>*)expressions {
    CBLAssertNotNil(expressions);
    
    CBLQueryExpression* aggr =
        [[CBLAggregateExpression alloc] initWithExpressions: expressions];
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: aggr
                                                          type: CBLInBinaryExpType];
}


#pragma mark - Collation:


- (CBLQueryExpression*) collate: (CBLQueryCollation*)collation {
    CBLAssertNotNil(collation);
    
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


- (id) asJSON {
    // Subclass needs to implement this method:
    return [NSNull null];
}


@end
