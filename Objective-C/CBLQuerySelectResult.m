//
//  CBLQuerySelectResult.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuerySelectResult.h"
#import "CBLQuery+Internal.h"

@implementation CBLQuerySelectResult {
    CBLQueryExpression* _expression;
}


+ (instancetype) expression: (CBLQueryExpression*)expression {
    return [[self alloc] initWithExpression: expression];
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
    return [_expression asJSON];
}


@end
