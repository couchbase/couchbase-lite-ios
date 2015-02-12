//
//  CBLQuery+FullTextSearch.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/21/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import "CBLQuery.h"


#if __has_feature(nullability) // Xcode 6.3+
#pragma clang assume_nonnull begin
#else
#define nullable
#define __nullable
#endif

/** CBLQuery interface for full-text searches.
    To use this, the view's map function must have emitted full-text strings as keys
    using the CBLTextKey() function. */
@interface CBLQuery (FullTextSearch)

/** Query string for a full-text search; works only if the view's map function has triggered full-
    text indexing by emitting strings wrapped by CBLTextKey().
    The query rows produced by this search will be instances of CBLFullTextQueryRow.

    The query string will be broken up into words. "Noise" words like "the" and "hello" (also
    called "stop-words") are ignored.

    The result will include a row corresponding to every emitted CBLTextKey() that contains _any_
    of the words in the query. Word matching tries to account for (English) grammatical variations
    like plurals and verb tenses, so for example "cat" will match "cats" and "type" will match
    "typing".

    **NOTE:** Full-text views have no keys, so the key-related query properties will be ignored.
    They also can't be reduced or grouped, so those properties are ignored too. */
@property (copy, nullable) NSString* fullTextQuery;

@end



/** A result row from a full-text query.
    A CBLQuery with its .fullTextQuery property set will produce CBLFullTextQueryRows. */
@interface CBLFullTextQueryRow : CBLQueryRow

/** The text emitted when the view was indexed (the argument to CBLTextKey()) which contains the
    match(es). */
@property (readonly, nullable) NSString* fullText;

/** The number of query words that were found in the fullText.
    (If a query word appears more than once, only the first instance is counted.) */
@property (readonly) NSUInteger matchCount;

/** The character range in the fullText of a particular match. */
- (NSRange) textRangeOfMatch: (NSUInteger)matchNumber;

/** The index of the search term matched by a particular match. Search terms are the individual 
    words in the full-text search expression, skipping duplicates and noise/stop-words. They're
    numbered from zero. */
- (NSUInteger) termIndexOfMatch: (NSUInteger)matchNumber;

@end


#if __has_feature(nullability)
#pragma clang assume_nonnull end
#endif
