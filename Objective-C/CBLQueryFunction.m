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
    NSArray* _params;
}

#pragma mark - Aggregation


+ (instancetype) avg: (id)expression {
    return [[self alloc] initWithFunction: @"AVG()" params: @[expression]];
}


+ (instancetype) count: (id)expression {
    return [[self alloc] initWithFunction: @"COUNT()" params: @[expression]];
}


+ (instancetype) min: (id)expression {
    return [[self alloc] initWithFunction: @"MIN()" params: @[expression]];
}


+ (instancetype) max: (id)expression {
    return [[self alloc] initWithFunction: @"MAX()" params: @[expression]];
}


+ (instancetype) sum: (id)expression {
    return [[self alloc] initWithFunction: @"SUM()" params: @[expression]];
}


#pragma mark - Array


+ (instancetype) arrayContains: (id)expression value: (nullable id)value {
    if (!value)
        value = [NSNull null]; // Apple platform specific
    return [[self alloc] initWithFunction: @"ARRAY_CONTAINS()" params: @[expression, value]];
}


+ (instancetype) arrayLength: (id)expression {
    return [[self alloc] initWithFunction: @"ARRAY_LENGTH()" params: @[expression]];
}


#pragma mark - Math

+ (instancetype) abs: (id)expression {
    return [[self alloc] initWithFunction: @"ABS()" params: @[expression]];
}

+ (instancetype) acos: (id)expression {
    return [[self alloc] initWithFunction: @"ACOS()" params: @[expression]];
}

+ (instancetype) asin: (id)expression {
    return [[self alloc] initWithFunction: @"ASIN()" params: @[expression]];
}

+ (instancetype) atan: (id)expression {
    return [[self alloc] initWithFunction: @"ATAN()" params: @[expression]];
}

+ (instancetype) atan2: (id)x y: (id)y {
    return [[self alloc] initWithFunction: @"ATAN2()" params: @[x, y]];
}

+ (instancetype) ceil: (id)expression {
    return [[self alloc] initWithFunction: @"CEIL()" params: @[expression]];
}

+ (instancetype) cos: (id)expression {
    return [[self alloc] initWithFunction: @"COS()" params: @[expression]];
}

+ (instancetype) degrees: (id)expression {
    return [[self alloc] initWithFunction: @"DEGREES()" params: @[expression]];
}

+ (instancetype) e {
    return [[self alloc] initWithFunction: @"E()" params: nil];
}

+ (instancetype) exp: (id)expression {
    return [[self alloc] initWithFunction: @"EXP()" params: @[expression]];
}

+ (instancetype) floor: (id)expression {
    return [[self alloc] initWithFunction: @"FLOOR()" params: @[expression]];
}

+ (instancetype) ln: (id)expression {
    return [[self alloc] initWithFunction: @"LN()" params: @[expression]];
}

+ (instancetype) log: (id)expression {
    return [[self alloc] initWithFunction: @"LOG()" params: @[expression]];
}

+ (instancetype) pi {
    return [[self alloc] initWithFunction: @"PI()" params: nil];
}

+ (instancetype) power: (id)base exponent: (id)exponent {
    return [[self alloc] initWithFunction: @"POWER()" params: @[base, exponent]];
}

+ (instancetype) radians: (id)expression {
    return [[self alloc] initWithFunction: @"RADIANS()" params: @[expression]];
}

+ (instancetype) round: (id)expression {
    return [[self alloc] initWithFunction: @"ROUND()" params: @[expression]];
}

+ (instancetype) round: (id)expression digits: (NSInteger)digits {
    return [[self alloc] initWithFunction: @"ROUND()" params: @[expression, @(digits)]];
}

+ (instancetype) sign: (id)expression {
    return [[self alloc] initWithFunction: @"SIGN()" params: @[expression]];
}

+ (instancetype) sin: (id)expression {
    return [[self alloc] initWithFunction: @"SIN()" params: @[expression]];
}

+ (instancetype) sqrt: (id)expression {
    return [[self alloc] initWithFunction: @"SQRT()" params: @[expression]];
}

+ (instancetype) tan: (id)expression {
    return [[self alloc] initWithFunction: @"TAN()" params: @[expression]];
}

+ (instancetype) trunc: (id)expression {
    return [[self alloc] initWithFunction: @"TRUNC()" params: @[expression]];
}

+ (instancetype) trunc: (id)expression digits: (NSInteger)digits {
    return [[self alloc] initWithFunction: @"TRUNC()" params: @[expression, @(digits)]];
}

#pragma mark - String

+ (instancetype) contains: (id)expression substring: (id)substring {
    return [[self alloc] initWithFunction: @"CONTAINS()" params: @[expression, substring]];
}

+ (instancetype) length: (id)expression {
    return [[self alloc] initWithFunction: @"LENGTH()" params: @[expression]];
}

+ (instancetype) lower: (id)expression {
    return [[self alloc] initWithFunction: @"LOWER()" params: @[expression]];
}

+ (instancetype) ltrim: (id)expression {
    return [[self alloc] initWithFunction: @"LTRIM()" params: @[expression]];
}

+ (instancetype) rtrim: (id)expression {
    return [[self alloc] initWithFunction: @"RTRIM()" params: @[expression]];
}

+ (instancetype) trim: (id)expression {
    return [[self alloc] initWithFunction: @"TRIM()" params: @[expression]];
}

+ (instancetype) upper: (id)expression {
    return [[self alloc] initWithFunction: @"UPPER()" params: @[expression]];
}

#pragma mark - Type

+ (instancetype) isArray:(id)expression {
    return [[self alloc] initWithFunction: @"ISARRAY()" params: @[expression]];
}

+ (instancetype) isBoolean:(id)expression {
    return [[self alloc] initWithFunction: @"ISBOOLEAN()" params: @[expression]];
}

+ (instancetype) isNumber:(id)expression {
    return [[self alloc] initWithFunction: @"ISNUMBER()" params: @[expression]];
}

+ (instancetype) isDictionary:(id)expression {
    return [[self alloc] initWithFunction: @"ISOBJECT()" params: @[expression]];
}

+ (instancetype) isString:(id)expression {
    return [[self alloc] initWithFunction: @"ISSTRING()" params: @[expression]];
}

#pragma mark - Internal


- (instancetype) initWithFunction: (NSString*)function params: (nullable NSArray*)params {
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
    
    for (id param in _params) {
        [json addObject: [self jsonValue: param]];
    }
    
    return json;
}


@end
