//
//  CBLQueryFunction.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

/** CBLQueryFunction represents a function expression. */
@interface CBLQueryFunction : CBLQueryExpression

/** Create an AVG() function expression that returns the average of all the number values 
    in the group of the values expressed by the given expression.
    @param expression   The expression.
    @return The average value. */
+ (instancetype) avg: (id)expression;

/** Create a COUNT() function expression that returns the count of all values 
    in the group of the values expressed by the given expression.
    @param expression   The expression.
    @return The count value. */
+ (instancetype) count: (id)expression;

/** Create a MIN() function expression that returns the minimum value 
    in the group of the values expressed by the given expression. 
    @param expression   The expression.
    @return The minimum value. */
+ (instancetype) min: (id)expression;

/** Create a MAX() function expression that returns the maximum value
    in the group of the values expressed by the given expression.
    @param expression   The expression.
    @return The maximum value. */
+ (instancetype) max: (id)expression;

/** Create a SUM() function expression that return the sum of all number values 
    in the group of the values expressed by the given expression.
    @param expression   The expression.
    @return The sum value. */
+ (instancetype) sum: (id)expression;

@end
