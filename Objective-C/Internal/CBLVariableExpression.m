//
//  CBLVariableExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLVariableExpression.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLVariableExpression {
    NSString* _name;
}


- (instancetype) initWithVariableNamed: (id)name {
    self = [super initWithNone];
    if (self) {
        _name = name;
    }
    return self;
}


- (id) asJSON {
    return @[[NSString stringWithFormat:@"?%@", _name]];
}


@end
