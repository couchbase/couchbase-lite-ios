//
//  CBLParameterExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLParameterExpression.h"
#import "CBLQuery+Internal.h"

@implementation CBLParameterExpression {
    NSString* _name;
}


- (instancetype)initWithName: (id)name {
    self = [super initWithNone];
    if (self) {
        _name = name;
    }
    return self;
}


- (id) asJSON {
    return @[[NSString stringWithFormat: @"$%@", _name]];
}


@end
