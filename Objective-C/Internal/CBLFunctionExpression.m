//
//  CBLFunctionExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFunctionExpression.h"

@implementation CBLFunctionExpression {
    NSString* _function;
    NSArray<CBLQueryExpression*>* _params;
}


- (instancetype) initWithFunction: (NSString*)function
                           params: (nullable NSArray<CBLQueryExpression*>*)params {
    self = [super initWithNone];
    if (self) {
        _function = function;
        _params = params;
    }
    return self;
}


- (id) asJSON {
    NSMutableArray* json = [NSMutableArray arrayWithCapacity: _params.count + 1];
    [json addObject: _function];
    
    for (CBLQueryExpression* param in _params) {
        [json addObject: [param asJSON]];
    }
    
    return json;
}

@end
