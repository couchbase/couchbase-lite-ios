//
//  CBLCompoundExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLCompoundExpression.h"
#import "CBLQuery+Internal.h"

@implementation CBLCompoundExpression

@synthesize subexpressions=_subexpressions, type=_type;

- (instancetype) initWithExpressions: (NSArray*)subs type: (CBLCompoundExpType)type {
    self = [super initWithNone];
    if (self) {
        _subexpressions = [subs copy];
        _type = type;
    }
    return self;
}

- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    switch (self.type) {
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
    
    for (id exp in _subexpressions) {
        if ([exp isKindOfClass: [CBLQueryExpression class]])
            [json addObject: [(CBLQueryExpression *)exp asJSON]];
        else
            [json addObject: exp];
    }
    return json;
}

@end
