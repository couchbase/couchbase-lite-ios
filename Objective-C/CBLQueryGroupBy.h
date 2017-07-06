//
//  CBLQueryGroupBy.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** A CBLQueryGroupBy represents a query GROUP BY clause to group the query result. 
    The GROUP BY statement is normally used with aggregate functions (AVG, COUNT, MAX, MIN, SUM) 
    to aggregate the group of the values. */
@interface CBLQueryGroupBy : NSObject

/** Creates a CBLQueryGroupBy object from an expression. */
+ (CBLQueryGroupBy*) expression: (CBLQueryExpression*)expression;

@end

NS_ASSUME_NONNULL_END
