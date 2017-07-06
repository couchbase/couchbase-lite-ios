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


+ (CBLQuerySortOrder *) property: (NSString*)name {
    return [[self class] expression: [CBLQueryExpression property: name]];
}


+ (CBLQuerySortOrder *) expression: (CBLQueryExpression*)expression {
    return [[CBLQuerySortOrder alloc] initWithExpression: expression];
}


#pragma mark - Internal

- (instancetype) initWithNone {
    return [super init];
}


- (id) asJSON {
    // Subclass implement
    return @[];
}


@end


@implementation CBLQuerySortOrder


@synthesize expression=_expression, isAscending=_isAscending;


- (instancetype) initWithExpression: (CBLQueryExpression*)expression {
    self = [super initWithNone];
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
