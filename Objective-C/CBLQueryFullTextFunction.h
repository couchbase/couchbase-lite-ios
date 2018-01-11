//
//  CBLQueryFullTextFunction.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/**
 Full-text function.
 */
@interface CBLQueryFullTextFunction : NSObject

/**
 Creates a full-text rank function with the given full-text index name.
 The rank function indicates how well the current query result matches
 the full-text query when performing the match comparison.
 
 @param indexName The full-text index name.
 @return The full-text rank function.
 */
+ (CBLQueryExpression*) rank: (NSString*)indexName;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
