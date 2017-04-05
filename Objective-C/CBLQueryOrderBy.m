//
//  CBLQueryOrderBy.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryOrderBy.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryExpression.h"

@implementation CBLQueryOrderBy


@synthesize orders=_orders;


- (instancetype) initWithOrders: (NSArray *)orders {
    self = [super init];
    if (self) {
        _orders = [orders copy];
    }
    return self;
}


+ (CBLQueryOrderBy*) orderBy: (NSArray<CBLQueryOrderBy*>*)orders {
    return [[[self class] alloc] initWithOrders: orders];
}


+ (CBLQuerySortOrder *) property: (NSString*)name {
    return [[self class] expression: [CBLQueryExpression property: name]];
}


+ (CBLQuerySortOrder *) expression: (CBLQueryExpression*)expression {
    return [[CBLQuerySortOrder alloc] initWithExpression: expression];
}

- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    for (CBLQueryOrderBy* o in _orders) {
        if ([o isKindOfClass:[CBLQuerySortOrder class]])
            [json addObject: [o asJSON]];
        else
            [json addObjectsFromArray: [o asJSON]];
    }
    return json;
}

@end


@implementation CBLQuerySortOrder


@synthesize expression=_expression, isAscending=_isAscending;


- (instancetype) initWithExpression: (CBLQueryExpression*)expression {
    self = [super initWithOrders: nil];
    if (self) {
        _expression = expression;
        _isAscending = YES;
    }
    return self;
}


- (CBLQueryOrderBy*) ascending {
    _isAscending = YES;
    return self;
}


- (CBLQueryOrderBy*) descending {
    _isAscending = NO;
    return self;
}

- (id) asJSON {
    id json = _isAscending ? [_expression asJSON] : @[@"DESC", [_expression asJSON]];
    return json;
}

@end
