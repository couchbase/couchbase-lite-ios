//
//  CBLUnaryExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLUnaryExpression.h"
#import "CBLQuery+Internal.h"

@implementation CBLUnaryExpression

@synthesize operand=_operand, type=_type;

- (instancetype) initWithExpression: (id)operand type: (CBLUnaryExpType)type {
    self = [super initWithNone];
    if (self) {
        _operand = operand;
        _type = type;
    }
    return self;
}

- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    switch (_type) {
        case CBLMissingUnaryExpType:
            [json addObject: @"IS MISSING"];
            break;
        case CBLNotMissingUnaryExpType:
            [json addObject: @"IS NOT MISSING"];
            break;
        case CBLNotNullUnaryExpType:
            [json addObject: @"IS NOT NULL"];
            break;
        case CBLNullUnaryExpType:
            [json addObject: @"IS NULL"];
            break;
        default:
            break;
    }
    
    if ([_operand isKindOfClass: [CBLQueryExpression class]])
        [json addObject: [(CBLQueryExpression*)_operand asJSON]];
    else
        [json addObject: _operand];
    
    return json;
}

@end
