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

/** Create an AVG() function expression. */
+ (instancetype) avg: (id)expression;

/** Create a COUNT() function expression. */
+ (instancetype) count: (id)expression;

/** Create a MIN() function expression. */
+ (instancetype) min: (id)expression;

/** Create a MAX() function expression. */
+ (instancetype) max: (id)expression;

/** Create a SUM() function expression. */
+ (instancetype) sum: (id)expression;

@end
