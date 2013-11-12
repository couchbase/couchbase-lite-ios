//
//  CBLQuery+FullTextSearch.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/21/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import "CBLQuery.h"


/** CBLQuery interface for full-text searches.
    To use this, the view's map function must have emitted full-text strings as keys
    using the CBLTextKey() function. */
@interface CBLQuery (FullTextSearch)

/** Query string for a full-text search; works only if the view's map function has triggered full-
    text indexing by emitting strings wrapped by CBLTextKey().
    The query string syntax is described in http://sqlite.org/fts3.html#section_3 .
    The query rows produced by this search will be instances of CBLFullTextQueryRow.
    **NOTE:** Full-text views have no keys, so the key-related query properties will be ignored.
    They also can't be reduced or grouped, so those properties are ignored too. */
@property (copy) NSString* fullTextQuery;

/** If set to YES, the query will collect snippets of the text surrounding each match, available
    via the CBLFullTextQueryRow's -snippetWithWordStart:wordEnd: method. */
@property BOOL fullTextSnippets;

/** If YES (the default) the full-text query result rows will be sorted by (approximate) relevance.
    If set to NO, the rows will be returned in the order the documents were added to the database,
    i.e. essentially unordered; this is somewhat faster, so it can be useful if you don't care
    about the ordering of the rows. */
@property BOOL fullTextRanking;

@end



/** A result row from a full-text query.
    A CBLQuery with its .fullTextQuery property set will produce CBLFullTextQueryRows. */
@interface CBLFullTextQueryRow : CBLQueryRow

/** The text emitted when the view was indexed, which contains the match. */
@property (readonly) NSString* fullText;

/** Returns a short substring of the full text containing at least some of the matched words.
    This is useful to display in search results, and is faster than fetching the .fullText.
    NOTE: The "fullTextSnippets" property of the CBLQuery must be set to YES to enable this;
    otherwise the result will be nil.
    @param wordStart  A delimiter that will be inserted before every instance of a match.
    @param wordEnd  A delimiter that will be inserted after every instance of a match. */
- (NSString*) snippetWithWordStart: (NSString*)wordStart
                           wordEnd: (NSString*)wordEnd;

/** The number of matches found in the fullText. */
@property (readonly) NSUInteger matchCount;

/** The character range in the fullText of a particular match. */
- (NSRange) textRangeOfMatch: (NSUInteger)matchNumber;

/** The search term matched by a particular match. Search terms are the individual words (or
    quoted phrases) in the full-text search expression. They're numbered starting from 0, except
    terms prefixed with "NOT" are skipped. (Details at http://sqlite.org/fts3.html#matchable ) */
- (NSUInteger) termIndexOfMatch: (NSUInteger)matchNumber;

@end
