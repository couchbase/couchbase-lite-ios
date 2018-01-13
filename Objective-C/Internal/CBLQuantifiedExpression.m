//
//  CBLQuantifiedExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuantifiedExpression.h"
#import "CBLQueryExpression+Internal.h"
#import "CBLQueryVariableExpression+Internal.h"

@implementation CBLQuantifiedExpression {
    CBLQuantifiedType _type;
    CBLQueryVariableExpression* _variable;
    CBLQueryExpression* _inExpression;
    CBLQueryExpression* _satisfies;
}


- (instancetype) initWithType: (CBLQuantifiedType)type
                     variable: (CBLQueryVariableExpression*)variable
                           in: (CBLQueryExpression*)inExpression
                    satisfies: (CBLQueryExpression*)satisfies
{
    self = [super initWithNone];
    if (self) {
        _type = type;
        _variable = variable;
        _inExpression = inExpression;
        _satisfies = satisfies;
    }
    return self;
}


- (id) asJSON {
    NSMutableArray* json = [NSMutableArray arrayWithCapacity: 4];
    
    switch (_type) {
        case CBLQuantifiedTypeAny:
            [json addObject: @"ANY"];
            break;
        case CBLQuantifiedTypeAnyAndEvery:
            [json addObject: @"ANY AND EVERY"];
            break;
        case CBLQuantifiedTypeEvery:
            [json addObject: @"EVERY"];
            break;
        default:
            break;
    }
    
    [json addObject: _variable.name];
    [json addObject: [_inExpression asJSON]];
    [json addObject: [_satisfies asJSON]];
    
    return json;
}

@end
