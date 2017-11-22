//
//  CBLQueryArrayFunction.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryArrayFunction.h"
#import "CBLFunctionExpression.h"

@implementation CBLQueryArrayFunction


+ (CBLQueryExpression*) contains: (id)expression value: (nullable id)value {
    if (!value)
        value = [NSNull null]; // Apple platform specific
    return [[CBLFunctionExpression alloc] initWithFunction: @"ARRAY_CONTAINS()"
                                                    params: @[expression, value]];
}


+ (CBLQueryExpression*) length: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ARRAY_LENGTH()"
                                                    params: @[expression]];
}


@end
