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
    id _satisfies;
}


- (instancetype) initWithType: (CBLQuantifiedType)type
                     variable: (NSString*)variable
                           in: (id)inExpression
                    satisfies: (id)satisfies
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
    
    [json addObject: _variable];
    [json addObject: [self jsonValue: _inExpression]];
    [json addObject: [self jsonValue: _satisfies]];
    
    return json;
}

@end
