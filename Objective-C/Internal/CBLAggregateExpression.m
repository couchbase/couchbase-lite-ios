//
//  CBLAggregateExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLAggregateExpression.h"
#import "CBLQuery+Internal.h"

@implementation CBLAggregateExpression

@synthesize expressions=_expressions;

- (instancetype) initWithExpressions: (NSArray*)expressions {
    self = [super initWithNone];
    if (self) {
        _expressions = expressions;
    }
    return self;
}

- (id) asJSON {
    NSMutableArray *json = [NSMutableArray arrayWithObject: @"[]"];
    for (id expr in _expressions) {
        [json addObject: [self jsonValue: expr]];
    }
    return json;
}

@end
