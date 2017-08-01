//
//  CBLBinaryExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLBinaryExpression.h"
#import "CBLQuery+Internal.h"
#import "CBLAggregateExpression.h"

@implementation CBLBinaryExpression

@synthesize lhs=_lhs, rhs=_rhs, type=_type;

- (instancetype) initWithLeftExpression:(id)lhs
                        rightExpression:(id)rhs
                                   type:(CBLBinaryExpType)type {
    self = [super initWithNone];
    if (self) {
        _lhs = lhs;
        _rhs = rhs;
        _type = type;
    }
    return self;
}

- (id) asJSON {
    NSMutableArray *json = [NSMutableArray array];
    switch (_type) {
        case CBLAddBinaryExpType:
            [json addObject: @"+"];
            break;
        case CBLBetweenBinaryExpType:
            [json addObject: @"BETWEEN"];
            break;
        case CBLDivideBinaryExpType:
            [json addObject: @"/"];
            break;
        case CBLEqualToBinaryExpType:
            [json addObject: @"="];
            break;
        case CBLGreaterThanBinaryExpType:
            [json addObject: @">"];
            break;
        case CBLGreaterThanOrEqualToBinaryExpType:
            [json addObject: @">="];
            break;
        case CBLInBinaryExpType:
            [json addObject: @"IN"];
            break;
        case CBLIsBinaryExpType:
            [json addObject: @"IS"];
            break;
        case CBLIsNotBinaryExpType:
            [json addObject: @"IS NOT"];
            break;
        case CBLLessThanBinaryExpType:
            [json addObject: @"<"];
            break;
        case CBLLessThanOrEqualToBinaryExpType:
            [json addObject: @"<="];
            break;
        case CBLLikeBinaryExpType:
            [json addObject: @"LIKE"];
            break;
        case CBLMatchesBinaryExpType:
            [json addObject: @"MATCH"];
            break;
        case CBLModulusBinaryExpType:
            [json addObject: @"%"];
            break;
        case CBLMultiplyBinaryExpType:
            [json addObject: @"*"];
            break;
        case CBLNotEqualToBinaryExpType:
            [json addObject: @"!="];
            break;
        case CBLRegexLikeBinaryExpType:
            [json addObject: @"regexp_like()"];
            break;
        case CBLSubtractBinaryExpType:
            [json addObject: @"-"];
            break;
        default:
            break;
    }
    
    if ([_lhs isKindOfClass: [CBLQueryExpression class]])
        [json addObject: [(CBLQueryExpression*)_lhs asJSON]];
    else
        [json addObject: _lhs];
    
    if ([_rhs isKindOfClass: [CBLAggregateExpression class]])
        [json addObjectsFromArray: [(CBLAggregateExpression*)_rhs asJSON]];
    else if ([_rhs isKindOfClass: [CBLQueryExpression class]])
        [json addObject: [(CBLQueryExpression*)_rhs asJSON]];
    else
        [json addObject: _rhs];
    
    return json;
}

@end
