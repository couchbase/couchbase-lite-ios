//
//  CBLQueryVariableExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryVariableExpression.h"
#import "CBLQueryExpression+Internal.h"
#import "CBLQueryVariableExpression+Internal.h"

@implementation CBLQueryVariableExpression

@synthesize name=_name;

- (instancetype) initWithName: (id)name {
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
