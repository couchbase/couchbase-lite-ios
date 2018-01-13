//
//  CBLQueryArrayExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryArrayExpression.h"
#import "CBLQuantifiedExpression.h"
#import "CBLQueryVariableExpression+Internal.h"

@implementation CBLQueryArrayExpression


+ (CBLQueryVariableExpression*) variableWithName: (NSString*)name {
    return [[CBLQueryVariableExpression alloc] initWithName: name];
}


+ (CBLQueryExpression*) any: (CBLQueryVariableExpression*)variable
                         in: (CBLQueryExpression*)inExpression
                  satisfies: (CBLQueryExpression*)satisfies
{
    return [[CBLQuantifiedExpression alloc] initWithType: CBLQuantifiedTypeAny
                                                variable: variable
                                                      in: inExpression
                                               satisfies: satisfies];
}


+ (CBLQueryExpression*) anyAndEvery: (CBLQueryVariableExpression*)variable
                                 in: (CBLQueryExpression*)inExpression
                          satisfies: (CBLQueryExpression*)satisfies
{
    return [[CBLQuantifiedExpression alloc] initWithType: CBLQuantifiedTypeAnyAndEvery
                                                variable: variable
                                                      in: inExpression
                                               satisfies: satisfies];
}


+ (CBLQueryExpression*) every: (CBLQueryVariableExpression*)variable
                           in: (CBLQueryExpression*)inExpression
                    satisfies: (CBLQueryExpression*)satisfies
{
    return [[CBLQuantifiedExpression alloc] initWithType: CBLQuantifiedTypeEvery
                                                variable: variable
                                                      in: inExpression
                                               satisfies: satisfies];
}


@end
