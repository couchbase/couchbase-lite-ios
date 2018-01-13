//
//  CBLQueryFunction.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryFunction.h"
#import "CBLQuery+Internal.h"
#import "CBLFunctionExpression.h"


@implementation CBLQueryFunction

#pragma mark - Aggregation


+ (CBLQueryExpression*) avg: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"AVG()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) count: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"COUNT()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) min: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"MIN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) max: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"MAX()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) sum: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"SUM()"
                                                    params: @[expression]];
}


#pragma mark - Math


+ (CBLQueryExpression*) abs: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ABS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) acos: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ACOS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) asin: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ASIN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) atan: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ATAN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) atan2: (CBLQueryExpression*)x y: (CBLQueryExpression*)y {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ATAN2()"
                                                    params: @[x, y]];
}


+ (CBLQueryExpression*) ceil: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"CEIL()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) cos: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"COS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) degrees: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"DEGREES()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) e {
    return [[CBLFunctionExpression alloc] initWithFunction: @"E()"
                                                    params: nil];
}


+ (CBLQueryExpression*) exp: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"EXP()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) floor: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"FLOOR()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) ln: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"LN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) log: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"LOG()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) pi {
    return [[CBLFunctionExpression alloc] initWithFunction: @"PI()"
                                                    params: nil];
}


+ (CBLQueryExpression*) power: (id)base exponent: (CBLQueryExpression*)exponent {
    return [[CBLFunctionExpression alloc] initWithFunction: @"POWER()"
                                                    params: @[base, exponent]];
}


+ (CBLQueryExpression*) radians: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"RADIANS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) round: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ROUND()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) round: (CBLQueryExpression*)expression digits: (CBLQueryExpression*)digits {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ROUND()"
                                                    params: @[expression, digits]];
}


+ (CBLQueryExpression*) sign: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"SIGN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) sin: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"SIN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) sqrt: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"SQRT()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) tan: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"TAN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) trunc: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"TRUNC()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) trunc: (CBLQueryExpression*)expression digits: (CBLQueryExpression*)digits {
    return [[CBLFunctionExpression alloc] initWithFunction: @"TRUNC()"
                                                    params: @[expression, digits]];
}


#pragma mark - String


+ (CBLQueryExpression*) contains: (CBLQueryExpression*)expression substring: (CBLQueryExpression*)substring {
    return [[CBLFunctionExpression alloc] initWithFunction: @"CONTAINS()"
                                                    params: @[expression, substring]];
}


+ (CBLQueryExpression*) length: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"LENGTH()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) lower: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"LOWER()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) ltrim: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"LTRIM()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) rtrim: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"RTRIM()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) trim: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"TRIM()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) upper: (CBLQueryExpression*)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"UPPER()"
                                                    params: @[expression]];
}


@end
