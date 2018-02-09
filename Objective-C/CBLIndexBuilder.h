//
//  CBLIndexBuilder.h
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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
@class CBLFullTextIndex;
@class CBLFullTextIndexItem;
@class CBLValueIndex;
@class CBLValueIndexItem;

NS_ASSUME_NONNULL_BEGIN

@interface CBLIndexBuilder : NSObject

/**
 Create a value index with the given index items. The index items are a list of
 the properties or expressions to be indexed.
 
 @param items The index items.
 @return The value index.
 */
+ (CBLValueIndex*) valueIndexWithItems: (NSArray<CBLValueIndexItem*>*)items;

/**
 Create a full-text search index with the given index item and options. Typically the index item is
 the property that is used to perform the match operation against with. Setting the nil options
 means using the default options.
 
 @param items The index items.
 @return The full-text search index.
 */
+ (CBLFullTextIndex*) fullTextIndexWithItems: (NSArray<CBLFullTextIndexItem*>*)items;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
