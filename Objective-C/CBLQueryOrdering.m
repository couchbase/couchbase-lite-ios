//
//  CBLQueryOrdering.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryOrdering.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLQueryOrdering

@synthesize expression=_expression;

+ (CBLQuerySortOrder *) property: (NSString*)name {
    return [[self class] expression: [CBLQueryExpression property: name]];
}


+ (CBLQuerySortOrder *) expression: (CBLQueryExpression*)expression {
    return [[CBLQuerySortOrder alloc] initWithExpression: expression];
}


#pragma mark - Internal

- (instancetype) initWithExpression: (CBLQueryExpression*)expression {
    self = [super init];
    if (self) {
        _expression = expression;
    }
    return self;
}


- (id) asJSON {
    return [self.expression asJSON];
}


@end


@implementation CBLQuerySortOrder

@synthesize isAscending=_isAscending;


- (instancetype) initWithExpression: (CBLQueryExpression*)expression {
    self = [super initWithExpression: expression];
    if (self) {
        _isAscending = YES;
    }
    return self;
}


- (CBLQueryOrdering*) ascending {
    _isAscending = YES;
    return self;
}


- (CBLQueryOrdering*) descending {
    _isAscending = NO;
    return self;
}


- (id) asJSON {
    id json = _isAscending ? [super asJSON] : @[@"DESC", [super asJSON]];
    return json;
}


@end
