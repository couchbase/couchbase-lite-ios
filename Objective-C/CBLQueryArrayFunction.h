//
//  CBLQueryArrayFunction.h
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

#import <Foundation/Foundation.h>
@class CBLQueryExpression;


NS_ASSUME_NONNULL_BEGIN

/**
 CBLQueryArrayFunction provides array based functions.
 */
@interface CBLQueryArrayFunction : NSObject

/**
 Creates an ARRAY_CONTAINS(expr, value) function that checks whether the given array
 expression contains the given value or not.
 
 @param expression The expression that evaluates to an array.
 @param value The value to search for in the given array expression.
 @return The ARRAY_CONTAINS(expr, value) function.
 */
+ (CBLQueryExpression*) contains: (CBLQueryExpression*)expression
                           value: (CBLQueryExpression*)value;

/**
 Creates an ARRAY_LENGTH(expr) function that returns the length of the given array
 expression.
 
 @param expression The expression that evaluates to an array.
 @return The ARRAY_LENGTH(expr) function.
 */
+ (CBLQueryExpression*) length: (CBLQueryExpression*)expression;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
