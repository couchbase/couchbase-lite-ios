//
//  CBLQueryGroupBy.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryGroupBy.h"
#import "CBLQuery+Internal.h"

@implementation CBLQueryGroupBy {
    CBLQueryExpression* _expression;
}


+ (CBLQueryGroupBy*) expression: (CBLQueryExpression*)expression {
    return [[self alloc] initWithExpression:expression];
}


- (instancetype) initWithExpression: (CBLQueryExpression*)expression {
    self = [super init];
    if (self) {
        _expression = expression;
    }
    return self;
}


- (id) asJSON {
    return [_expression asJSON];
}


@end
