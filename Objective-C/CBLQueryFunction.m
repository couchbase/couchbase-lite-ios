//
//  CBLQueryFunction.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLQueryFunction.h"
#import "CBLQuery+Internal.h"
#import "CBLFunctionExpression.h"


@implementation CBLQueryFunction

#pragma mark - Aggregation


+ (CBLQueryExpression*) avg: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"AVG()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) count: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"COUNT()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) min: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"MIN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) max: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"MAX()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) sum: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"SUM()"
                                                    params: @[expression]];
}


#pragma mark - Math


+ (CBLQueryExpression*) abs: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"ABS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) acos: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"ACOS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) asin: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"ASIN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) atan: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"ATAN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) atan2: (CBLQueryExpression*)x y: (CBLQueryExpression*)y {
    CBLAssertNotNil(x);
    CBLAssertNotNil(y);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"ATAN2()"
                                                    params: @[x, y]];
}


+ (CBLQueryExpression*) ceil: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"CEIL()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) cos: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"COS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) degrees: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"DEGREES()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) e {
    return [[CBLFunctionExpression alloc] initWithFunction: @"E()"
                                                    params: nil];
}


+ (CBLQueryExpression*) exp: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"EXP()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) floor: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"FLOOR()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) ln: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"LN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) log: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"LOG()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) pi {
    return [[CBLFunctionExpression alloc] initWithFunction: @"PI()"
                                                    params: nil];
}


+ (CBLQueryExpression*) power: (id)base exponent: (CBLQueryExpression*)exponent {
    CBLAssertNotNil(base);
    CBLAssertNotNil(exponent);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"POWER()"
                                                    params: @[base, exponent]];
}


+ (CBLQueryExpression*) radians: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"RADIANS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) round: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"ROUND()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) round: (CBLQueryExpression*)expression digits: (CBLQueryExpression*)digits {
    CBLAssertNotNil(expression);
    CBLAssertNotNil(digits);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"ROUND()"
                                                    params: @[expression, digits]];
}


+ (CBLQueryExpression*) sign: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"SIGN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) sin: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"SIN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) sqrt: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"SQRT()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) tan: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"TAN()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) trunc: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"TRUNC()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) trunc: (CBLQueryExpression*)expression digits: (CBLQueryExpression*)digits {
    CBLAssertNotNil(expression);
    CBLAssertNotNil(digits);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"TRUNC()"
                                                    params: @[expression, digits]];
}


#pragma mark - String


+ (CBLQueryExpression*) contains: (CBLQueryExpression*)expression substring: (CBLQueryExpression*)substring {
    CBLAssertNotNil(expression);
    CBLAssertNotNil(substring);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"CONTAINS()"
                                                    params: @[expression, substring]];
}


+ (CBLQueryExpression*) length: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"LENGTH()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) lower: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"LOWER()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) ltrim: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"LTRIM()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) rtrim: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"RTRIM()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) trim: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"TRIM()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) upper: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"UPPER()"
                                                    params: @[expression]];
}


# pragma mark - Date Time


+ (CBLQueryExpression*) stringToMillis:(CBLQueryExpression *)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"STR_TO_MILLIS()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) stringToUTC:(CBLQueryExpression *)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"STR_TO_UTC()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) millisToString:(CBLQueryExpression *)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"MILLIS_TO_STR()"
                                                    params: @[expression]];
}


+ (CBLQueryExpression*) millisToUTC:(CBLQueryExpression *)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLFunctionExpression alloc] initWithFunction: @"MILLIS_TO_UTC()"
                                                    params: @[expression]];
}

@end
