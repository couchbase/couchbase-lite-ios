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

@synthesize subexpressions=_subexpressions;

- (instancetype) initWithExpressions: (NSArray *)subs {
    self = [super initWithNone];
    if (self) {
        _subexpressions = [subs copy];
    }
    return self;
}

- (id) asJSON {
    NSMutableArray *json = [NSMutableArray arrayWithObject: @"[]"];
    for (id exp in _subexpressions) {
        if ([exp isKindOfClass:[CBLQueryExpression class]])
            [json addObject: [(CBLQueryExpression *)exp asJSON]];
        else
            [json addObject: exp];
    }
    return json;
}

@end
