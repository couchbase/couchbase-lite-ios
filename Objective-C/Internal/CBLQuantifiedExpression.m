//
//  CBLQuantifiedExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuantifiedExpression.h"
#import "CBLQuery+Internal.h"

@implementation CBLQuantifiedExpression {
    CBLQuantifiedType _type;
    NSString* _variable;
    id _inExpression;
    id _satisfiesExpression;
}


- (instancetype) initWithType: (CBLQuantifiedType)type
                     variable: (NSString*)variable
                           in: (id)inExpression
                    satisfies: (id)satisfiesExpression
{
    self = [super initWithNone];
    if (self) {
        _type = type;
        _variable = variable;
        _inExpression = inExpression;
        _satisfiesExpression = satisfiesExpression;
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
    
    [json addObject: _variable];
    
    if ([_inExpression isKindOfClass: [CBLQueryExpression class]])
        [json addObject: [(CBLQueryExpression*)_inExpression asJSON]];
    else
        [json addObject: _inExpression];
    
    if ([_satisfiesExpression isKindOfClass: [CBLQueryExpression class]])
        [json addObject: [(CBLQueryExpression*)_satisfiesExpression asJSON]];
    else
        [json addObject: _satisfiesExpression];
    
    return json;
}

@end
