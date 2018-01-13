//
//  CBLAggregateExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLAggregateExpression.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLAggregateExpression

@synthesize expressions=_expressions;

- (instancetype) initWithExpressions: (NSArray<CBLQueryExpression*>*)expressions {
    self = [super initWithNone];
    if (self) {
        _expressions = expressions;
    }
    return self;
}

- (id) asJSON {
    NSMutableArray *json = [NSMutableArray arrayWithObject: @"[]"];
    for (CBLQueryExpression* expr in _expressions) {
        [json addObject: [expr asJSON]];
    }
    return json;
}

@end
