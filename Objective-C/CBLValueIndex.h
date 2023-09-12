//
//  CBLValueIndex.h
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
#import "CBLIndex.h"
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

@interface CBLValueIndex: CBLIndex

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

/**
 Value Index Item.
 */
@interface CBLValueIndexItem: NSObject

/**
 Creates a value index item with the given property name.
 
 @param property The property name
 @return The value index item;
 */
+ (CBLValueIndexItem*) property: (NSString*)property;

/**
 Creates a value index item with the given expression.
 
 @param expression The expression to index. Typically a property expression.
 @return The value index item.
 */
+ (CBLValueIndexItem*) expression: (CBLQueryExpression*)expression;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
