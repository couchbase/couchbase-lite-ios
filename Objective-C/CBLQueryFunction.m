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


+ (CBLQueryExpression*) avg: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"AVG()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) count: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"COUNT()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) min: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"MIN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) max: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"MAX()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) sum: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"SUM()"
                                                    params: @[expression]];
}


#pragma mark - Math


+ (CBLQueryExpression*) abs: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ABS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) acos: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ACOS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) asin: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ASIN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) atan: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ATAN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) atan2: (id)x y: (id)y {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ATAN2()"
                                                    params: @[x, y]];
}


+ (CBLQueryExpression*) ceil: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"CEIL()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) cos: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"COS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) degrees: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"DEGREES()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) e {
    return [[CBLFunctionExpression alloc] initWithFunction: @"E()"
                                                    params: nil];
}


+ (CBLQueryExpression*) exp: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"EXP()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) floor: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"FLOOR()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) ln: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"LN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) log: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"LOG()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) pi {
    return [[CBLFunctionExpression alloc] initWithFunction: @"PI()"
                                                    params: nil];
}


+ (CBLQueryExpression*) power: (id)base exponent: (id)exponent {
    return [[CBLFunctionExpression alloc] initWithFunction: @"POWER()"
                                                    params: @[base, exponent]];
}


+ (CBLQueryExpression*) radians: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"RADIANS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) round: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ROUND()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) round: (id)expression digits: (NSInteger)digits {
    return [[CBLFunctionExpression alloc] initWithFunction: @"ROUND()"
                                                    params: @[expression, @(digits)]];
}


+ (CBLQueryExpression*) sign: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"SIGN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) sin: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"SIN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) sqrt: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"SQRT()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) tan: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"TAN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) trunc: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"TRUNC()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) trunc: (id)expression digits: (NSInteger)digits {
    return [[CBLFunctionExpression alloc] initWithFunction: @"TRUNC()"
                                                    params: @[expression,
                                                              @(digits)]];
}


#pragma mark - String


+ (CBLQueryExpression*) contains: (id)expression substring: (id)substring {
    return [[CBLFunctionExpression alloc] initWithFunction: @"CONTAINS()"
                                                    params: @[expression,
                                                              substring]];
}


+ (CBLQueryExpression*) length: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"LENGTH()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) lower: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"LOWER()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) ltrim: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"LTRIM()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) rtrim: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"RTRIM()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) trim: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"TRIM()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) upper: (id)expression {
    return [[CBLFunctionExpression alloc] initWithFunction: @"UPPER()"
                                                    params: @[expression]];
}


@end
