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
        _orders = orders;
    }
    return self;
}


+ (CBLQueryOrderBy *) orderBy: (CBLQueryOrderBy *)orderBy, ... {
    NSMutableArray* orders = [NSMutableArray array];
    va_list args;
    va_start(args, orderBy);
    id o = orderBy;
    do { if (o) [orders addObject: o]; } while ((o=va_arg(args, id)));
    va_end(args);
    return [[[self class] alloc] initWithOrders: orders];
}


+ (CBLQuerySortOrder *) property: (NSString*)name {
    return [[self class] expression: [CBLQueryExpression property: name]];
}


+ (CBLQuerySortOrder *) expression: (CBLQueryExpression*)expression {
    return [[CBLQuerySortOrder alloc] initWithExpression: expression];
}


- (NSArray*) asSortDescriptors {
    NSMutableArray* descriptors = [NSMutableArray array];
    if ([self isKindOfClass: [CBLQuerySortOrder class]]) {
        CBLQuerySortOrder* so = (CBLQuerySortOrder*)self;
        NSExpression* exp = [$castIf(CBLQueryTypeExpression, so.expression) asNSExpression];
        if (exp.expressionType == NSKeyPathExpressionType) {
            if (so.isAscending)
                [descriptors addObject: exp.keyPath];
            else
                [descriptors addObject: [NSString stringWithFormat:@"-%@", exp.keyPath]];
        } else
            [descriptors addObject: exp];
    } else {
        for (CBLQueryOrderBy* o in self.orders)
            [descriptors addObjectsFromArray: [o asSortDescriptors]];
    }
    return descriptors;
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
    self.isAscending = YES;
    return self;
}


- (CBLQueryOrderBy*) descending {
    self.isAscending = NO;
    return self;
}


@end
