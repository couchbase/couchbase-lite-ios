//
//  CBLQueryArrayFunction.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
 
 @param expression The expression that evluates to an array.
 @param value The value to search for in the given array expression.
 @return The ARRAY_CONTAINS(expr, value) function.
 */
+ (CBLQueryExpression*) contains: (id)expression value: (nullable id)value;

/**
 Creates an ARRAY_LENGTH(expr) function that returns the length of the given array
 expression.
 
 @param expression The expression that evluates to an array.
 @return The ARRAY_LENGTH(expr) function.
 */
+ (CBLQueryExpression*) length: (id)expression;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
