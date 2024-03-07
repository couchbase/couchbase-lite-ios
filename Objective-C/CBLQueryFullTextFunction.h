//
//  CBLQueryFullTextFunction.h
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <Foundation/Foundation.h>

@class CBLQueryExpression;
@protocol CBLQueryIndexExpressionProtocol;

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
+ (CBLQueryExpression*) rank: (NSString*)indexName
__deprecated_msg("Use [CBLQueryFullTextFunction rankWithIndex:] instead.")
NS_SWIFT_NAME(rank(withIndexName:));

/**
 Creates a full-text match expression with the given full-text index name and the query text

 @param indexName The full-text index name.
 @param query The query string.
 @return The full-text match expression.
 */
+ (CBLQueryExpression*) matchWithIndexName: (NSString*)indexName query: (NSString*)query
__deprecated_msg("Use [CBLQueryFullTextFunction matchWithIndex: query:] instead.")
NS_SWIFT_NAME(match(withIndexName:query:));

/**
 Creates a full-text rank() function with the given full-text index expression.
 
 The rank function indicates how well the current query result matches
 the full-text query when performing the match comparison.
 
 - Parameter index: The full-text index expression.
 - Returns: The full-text rank function.
 */
+ (CBLQueryExpression*) rankWithIndex: (id<CBLQueryIndexExpressionProtocol>)index
NS_SWIFT_NAME(rank(withIndex:));

/**
 Creates a full-text match() function  with the given full-text index expression and the query text
 
 - Parameter index: The full-text index expression.
 - Parameter query: The query string.
 - Returns: The full-text match() function expression.
 */
+ (CBLQueryExpression*) matchWithIndex: (id<CBLQueryIndexExpressionProtocol>)index query: (NSString*)query
NS_SWIFT_NAME(match(withIndex:query:));

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
