//
//  CBLQueryLimit.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** 
 A CBLQueryLimit represents a query LIMIT clause used for constrainting the number of results
 returned by a query.
 */
@interface CBLQueryLimit : NSObject

/**
  Create a LIMIT component to limit the number of results to not more than the given limit value.
 */
+ (CBLQueryLimit*) limit: (CBLQueryExpression*)expression;

/** 
 Create a LIMIT component to skip the returned results for the given offset position
 and to limit the number of results to not more than the given limit value.
 */
+ (CBLQueryLimit*) limit: (CBLQueryExpression*)expression offset: (nullable CBLQueryExpression*)expression;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
