//
//  CBLQueryFTS.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN


/**
 CBLQueryFTS is a factory class for creating full-text search related expressions.
 */
@interface CBLQueryFTS : NSObject

/**
 Creates a full text search ranking value expression with the given property name.
 The ranking value expression indicates how well the current query result
 matches the full-text query.
 
 @param property The property name in the key path format.
 @return The ranking value expression.
 */
- (CBLQueryExpression*) rank: (NSString*)property;

/**
 Creates a full text search ranking value expression with the given property name and the data
 source alias name. The ranking value expression indicates how well the current query result
 matches the full-text query.

 @param property The property name in the key path format.
 @param alias The data source alias name.
 @return The ranking value expression.
 */
- (CBLQueryExpression*) rank: (NSString*)property from: (nullable NSString*)alias;

@end

NS_ASSUME_NONNULL_END
