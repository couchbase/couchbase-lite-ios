//
//  CBLQuerySelectResult.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** A CBLQuerySelectResult represents a returning value in each query result row. */
@interface CBLQuerySelectResult : NSObject

/** 
 Creates a CBLQuerySelectResult for the given expression.
 @param expression The expression.
 @return The CBLQuerySelectResult.
 */
+ (instancetype) expression: (CBLQueryExpression*)expression;

/** 
 Creates a CBLQuerySelectResult for the given expression and the alias name.
 
 @param expression The expression.
 @param alias The alias name.
 @return The CBLQuerySelectResult.
 */
+ (instancetype) expression: (CBLQueryExpression*)expression as: (nullable NSString*)alias;

/** 
 Creates a CBLQuerySelectResult that returns all properties data. The query returned result
 will be grouped into a single CBLDictionary object under the key of the data source name.
 
 @return The CBLQuerySelectResult.
 */
+ (instancetype) all;

/** 
 Creates a CBLQuerySelectResult that returns all properties data. The query returned result
 will be grouped into a single CBLDictionary object under the key of the data source name key or
 the given alias data source name if specified.
 
 @param alias The data source alias name
 @return The CBLQuerySelectResult.
 */
+ (instancetype) allFrom: (nullable NSString*)alias;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
