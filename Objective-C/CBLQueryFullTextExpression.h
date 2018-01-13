//
//  CBLQueryFullTextExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/**
 Full-text expression.
 */
@interface CBLQueryFullTextExpression : NSObject

/**
 Creates a full-text expression with the given full-text index name.

 @param name The full-text index name.
 @return The full-text expression.
 */
+ (CBLQueryFullTextExpression*) indexWithName: (NSString*)name;


/**
 Creates a full-text match expression with the given search text.

 @param query The query string.
 @return The full-text match expression.
 */
- (CBLQueryExpression*) match: (NSString*)query;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
