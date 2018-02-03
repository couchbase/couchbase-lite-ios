//
//  CBLQuerySelectResult.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

/** A CBLQuerySelectResult represents a returning value in each query result row. */
@interface CBLQuerySelectResult : NSObject

/**
 Creates a CBLQuerySelectResult for the given property name.

 @param property The property name.
 @return The CBLQuerySelectResult.
 */
+ (instancetype) property: (NSString*)property;

/**
 Creates a CBLQuerySelectResult for the given property name and the alias name.
 
 @param property The property name.
 @param alias The alias name.
 @return The CBLQuerySelectResult.
 */
+ (instancetype) property: (NSString*)property as: (nullable NSString*)alias;

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
 will be grouped into a single CBLMutableDictionary object under the key of the data source name.
 
 @return The CBLQuerySelectResult.
 */
+ (instancetype) all;

/** 
 Creates a CBLQuerySelectResult that returns all properties data. The query returned result
 will be grouped into a single CBLMutableDictionary object under the key of the data source name key or
 the given alias data source name if specified.
 
 @param alias The data source alias name
 @return The CBLQuerySelectResult.
 */
+ (instancetype) allFrom: (nullable NSString*)alias;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
