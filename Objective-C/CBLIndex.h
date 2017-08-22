//
//  CBLIndex.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLValueIndexItem;
@class CBLFTSIndexItem;
@class CBLFTSIndexOptions;
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/**
 CBLIndex represents an index which could be a value index for regular queries or
 full-text search (FTS) index for full-text queries (using the match operator).
 */
@interface CBLIndex : NSObject


/**
 Create a value index with the given index items. The index items are a list of
 the properties or expressions to be indexed.

 @param items The index items.
 @return The value index.
 */
+ (CBLIndex*) valueIndexOn: (NSArray<CBLValueIndexItem*>*)items;


/**
 Create a full-text search index with the given index item and options. Typically the index item is
 the property that is used to perform the match operation against with. Setting the nil options
 means using the default options.

 @param item The index item.
 @param options The index options.
 @return The full-text search index.
 */
+ (CBLIndex*) ftsIndexOn: (CBLFTSIndexItem*)item options: (nullable CBLFTSIndexOptions*)options;

@end



/**
 Value Index Item.
 */
@interface CBLValueIndexItem: NSObject


/**
 Creates a value index item with the given expression.

 @param expression The expression to index. Typically a property expression.
 @return The value index item.
 */
+ (CBLValueIndexItem*) expression: (CBLQueryExpression*)expression;

@end



/**
 FTS Index Item.
 */
@interface CBLFTSIndexItem: NSObject


/**
 Creates a full-text search index item with the given expression.

 @param expression The expression to index. Typically a property expression used to perform the
                   match operation against with.
 @return The full-text search index item.
 */
+ (CBLFTSIndexItem*) expression: (CBLQueryExpression*)expression;

@end



/**
 Options for creating full-text search indexes. All properties are set to false or nil by default.
 */
@interface CBLFTSIndexOptions: NSObject


/**
 Set the true value to ignore accents/diacritical marks. The default value is false.
 */
@property (nonatomic) BOOL ignoreAccents;


/**
 The locale code which is an ISO-639 language code plus, optionally, an underscore and an ISO-3166
 country code: "en", "en_US", "fr_CA", etc. Setting the locale code affects how word breaks and
 word stems are parsed. Setting nil value to use current locale and setting "" to disable stemming.
 The default value is nil.
 */
@property (nonatomic, copy, nullable) NSString* locale;

- (instancetype) init;

@end

NS_ASSUME_NONNULL_END
