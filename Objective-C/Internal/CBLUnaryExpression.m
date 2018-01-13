//
//  CBLUnaryExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLUnaryExpression.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLUnaryExpression {
    CBLUnaryExpType _type;
    CBLQueryExpression* _operand;
}


- (instancetype) initWithExpression: (CBLQueryExpression*)operand
                               type: (CBLUnaryExpType)type
{
    self = [super initWithNone];
    if (self) {
        _operand = operand;
        _type = type;
    }
    return self;
}


- (id) asJSON {
    id operand = [_operand asJSON];
    
    switch (_type) {
        case CBLUnaryTypeMissing:
            return @[@"IS", operand, @[@"MISSING"]];
        case CBLUnaryTypeNotMissing:
            return @[@"IS NOT", operand, @[@"MISSING"]];
        case CBLUnaryTypeNull:
            return @[@"IS", operand, [NSNull null]];
        case CBLUnaryTypeNotNull:
            return @[@"IS NOT", operand, [NSNull null]];
        default:
            break;
    }
    
    return @[]; // Shouldn't happen
}

@end
