//
//  CBLQueryFunction.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryFunction.h"
#import "CBLQuery+Internal.h"


@implementation CBLQueryFunction {
    NSString* _function;
    id _param;
}


+ (instancetype) avg: (id)expression {
    return [[self alloc] initWithFunction: @"AVG()" parameter: expression];
}


+ (instancetype) count: (id)expression {
    return [[self alloc] initWithFunction: @"COUNT()" parameter: expression];
}


+ (instancetype) min: (id)expression {
    return [[self alloc] initWithFunction: @"MIN()" parameter: expression];
}


+ (instancetype) max: (id)expression {
    return [[self alloc] initWithFunction: @"MAX()" parameter: expression];
}


+ (instancetype) sum: (id)expression {
    return [[self alloc] initWithFunction: @"SUM()" parameter: expression];
}


#pragma mark - Internal


- (instancetype) initWithFunction:(NSString *)function parameter: (id)param {
    self = [super initWithNone];
    if (self) {
        _function = function;
        _param = param;
    }
    return self;
}


- (id) asJSON {
    id param;
    if ([_param isKindOfClass: [CBLQueryExpression class]])
        param = [_param asJSON];
    else
        param = _param;
    return @[_function, param];
}


@end
