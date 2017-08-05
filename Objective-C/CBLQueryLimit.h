//
//  CBLQueryLimit.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** 
 A CBLQueryLimit represents a query LIMIT clause used for constrainting the number of results
 returned by a query.
 */
@interface CBLQueryLimit : NSObject

/**
  Create a LIMIT component to limit the number of results to not more than the given limit value.
 */
+ (CBLQueryLimit*) limit: (id)expression;

/** 
 Create a LIMIT component to skip the returned results for the given offset position
 and to limit the number of results to not more than the given limit value.
 */
+ (CBLQueryLimit*) limit: (id)expression offset: (nullable id)expression;

@end

NS_ASSUME_NONNULL_END
