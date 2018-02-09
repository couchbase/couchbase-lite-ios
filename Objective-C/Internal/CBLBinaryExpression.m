//
//  CBLBinaryExpression.m
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

#import "CBLBinaryExpression.h"
#import "CBLAggregateExpression.h"
#import "CBLQueryExpression+Internal.h"


@implementation CBLBinaryExpression {
    CBLQueryExpression* _lhs;
    CBLQueryExpression* _rhs;
    CBLBinaryExpType _type;
}

- (instancetype) initWithLeftExpression:(CBLQueryExpression*)lhs
                        rightExpression:(CBLQueryExpression*)rhs
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
    
    [json addObject: [_lhs asJSON]];

    if (_type == CBLBetweenBinaryExpType) {
        // "between"'s RHS is an aggregate of the min and max, but the min and max need to be
        // written out as parameters to the BETWEEN operation:
        NSArray<CBLQueryExpression*>* rangeExprs = ((CBLAggregateExpression*)_rhs).expressions;
        [json addObject: [rangeExprs[0] asJSON] ];
        [json addObject: [rangeExprs[1] asJSON]];
    } else
        [json addObject:  [_rhs asJSON]];
    
    return json;
}

@end
