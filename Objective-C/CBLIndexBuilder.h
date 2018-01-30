//
//  CBLIndexBuilder.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/29/18.
//  Copyright © 2018 Couchbase. All rights reserved.
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
