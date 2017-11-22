//
//  CBLCompoundExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLCompoundExpression.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLCompoundExpression {
    NSArray* _expressions;
    CBLCompoundExpType _type;
}


- (instancetype) initWithExpressions: (NSArray*)expressions
                                type: (CBLCompoundExpType)type
{
    self = [super initWithNone];
    if (self) {
        _expressions = expressions;
        _type = type;
    }
    return self;
}


- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    
    switch (_type) {
        case CBLAndCompundExpType:
            [json addObject: @"AND"];
            break;
        case CBLOrCompundExpType:
            [json addObject: @"OR"];
            break;
        case CBLNotCompundExpType:
            [json addObject: @"NOT"];
            break;
        default:
            break;
    }
    
    for (id expr in _expressions) {
        [json addObject: [self jsonValue: expr]];
    }
    
    return json;
}


@end
