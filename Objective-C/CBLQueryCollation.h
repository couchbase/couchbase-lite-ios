//
//  CBLQueryCollation.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


/**
 CBLQueryCollation defines how strings are compared and is used when creating a COLLATE expression.
 The COLLATE expression can be used in the WHERE clause when comparing two strings or in the
 ORDER BY clause when specifying how the order of the query results. CouchbaseLite provides
 two types of the Collation, ASCII and Unicode. Without specifying the COLLATE expression
 Couchbase Lite will use the ASCII with case sensitive collation by default.
 */
@interface CBLQueryCollation : NSObject

/**
 Creates an ASCII Collation that compares strings by using binary comparison. If the ignoring case
 or case-insenstive is specified, the collation will treat ASCII uppercase and lowercase letters
 as equivalent.

 @param ignoreCase True for case-insensitive; false for case-sensitive.
 @return The ASCII Collation.
 */
+ (CBLQueryCollation*) asciiWithIgnoreCase: (BOOL)ignoreCase;

/**
 Creates a Unicode Collation that compares strings by using Unicode Collation Algorithm.
 If the locale is not specified, the collation is Unicode-aware but not localized; for example,
 accented Roman letters sort right after the base letter
 (This is implemented by using the "en_US" locale).
 
 @param locale The locale code which is an ISO-639 language code plus, optionally,
               an underscore and an ISO-3166 country code: "en", "en_US", "fr_CA", etc.
               Specifing the locale will allow the collation to compare strings appropriately
               base on the locale. If not specified, the 'en_US' will be used by default.
 @param ignoreCase True for case-insensitive; false for case sensitive.
 @param ignoreAccents True for accent-insensitive; false for accent-sensitive.
 @return The Unicode Collation.
*/
+ (CBLQueryCollation*) unicodeWithLocale: (nullable NSString*)locale
                              ignoreCase: (BOOL)ignoreCase
                           ignoreAccents: (BOOL)ignoreAccents;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
