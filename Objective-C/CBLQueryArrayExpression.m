//
//  CBLQueryArrayExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryArrayExpression.h"
#import "CBLQuantifiedExpression.h"
#import "CBLVariableExpression.h"

@implementation CBLQueryArrayExpression


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


@end
