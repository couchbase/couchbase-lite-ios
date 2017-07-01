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

/** A CBLQueryGroupBy represents a query GROUP BY clause to aggregate data returned 
    in the result set. */
@interface CBLQueryGroupBy : NSObject

/** Creates a CBLQueryGroupBy object from an expression. */
+ (CBLQueryGroupBy*) expression: (CBLQueryExpression*)expression;

@end

NS_ASSUME_NONNULL_END
