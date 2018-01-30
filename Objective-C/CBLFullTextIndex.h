//
//  CBLFTSIndex.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLIndex.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLFullTextIndex: CBLIndex

/**
 Set the true value to ignore accents/diacritical marks. The default value is false.
 */
@property (nonatomic) BOOL ignoreAccents;

/**
 The language code which is an ISO-639 language such as "en", "fr", etc.
 Setting the language code affects how word breaks and word stems are parsed.
 Without setting the value, the current locale's language will be used. Setting
 a nil or "" value to disable the language features.
 */
@property (nonatomic, copy, nullable) NSString* language;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

/**
 Full-text Index Item.
 */
@interface CBLFullTextIndexItem: NSObject

/**
 Creates a full-text search index item with the given expression.
 
 @param property A property used to perform the match operation against with.
 @return The full-text search index item.
 */
+ (CBLFullTextIndexItem*) property: (NSString*)property;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
