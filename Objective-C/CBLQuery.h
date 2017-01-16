//
//  CBLQuery.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 11/30/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase, CBLQueryRow, CBLDocument;

NS_ASSUME_NONNULL_BEGIN


/** A compiled database query. Can be run multiple times with different parameters. */
@interface CBLQuery : NSObject

/** The database to query. */
@property (nonatomic, readonly) CBLDatabase* database;

/** The number of initial result rows to skip. Defaults to 0.
    This can be useful to "page" through a large query, but skipping large numbers of rows can be
    slow. */
@property (nonatomic) NSUInteger skip;

/** The maximum number of rows to return. Defaults to "unlimited" (UINT64_MAX). */
@property (nonatomic) NSUInteger limit;

/** Values to substitute for placeholder parameters defined in the query. Defaults to nil.
    The dictionary's keys are parameter names, and values are the values to use.
    All parameters must be given values before running the query, or it will fail. */
@property (copy, nonatomic, nullable) NSDictionary* parameters;

/** Runs the query, using the current settings (skip, limit, parameters), returning an enumerator
    that returns result rows one at a time.
    You can run the query any number of times, and you can even have multiple enumerators active at
    once.
    The results come from a snapshot of the database taken at the moment -run: is called, so they
    will not reflect any changes made to the database afterwards. */
- (nullable NSEnumerator<CBLQueryRow*>*) run: (NSError**)error;

- (instancetype) init NS_UNAVAILABLE;

@end


/** A single result from a CBLQuery.
    The NSEnumeration returned by -[CBLQuery run:] produces these. */
@interface CBLQueryRow : NSObject

/** The ID of the document that produced this row. */
@property (readonly, nonatomic) NSString* documentID;

/** The sequence number of the document revision that produced this row. */
@property (readonly, nonatomic) uint64_t sequence;

/** The document that produced this row. */
@property (readonly, nonatomic) CBLDocument* document;

@end


/** A single result from a full-text CBLQuery. */
@interface CBLFullTextQueryRow : CBLQueryRow

/** The text emitted when the view was indexed (the argument to CBLTextKey()) which contains the
    match(es). */
@property (readonly, nullable) NSString* fullTextMatched;

/** The number of query words that were found in the fullText.
    (If a query word appears more than once, only the first instance is counted.) */
@property (readonly, nonatomic) NSUInteger matchCount;

/** The character range in the fullText of a particular match. */
- (NSRange) textRangeOfMatch: (NSUInteger)matchNumber;

/** The index of the search term matched by a particular match. Search terms are the individual
    words in the full-text search expression, skipping duplicates and noise/stop-words. They're
    numbered from zero. */
- (NSUInteger) termIndexOfMatch: (NSUInteger)matchNumber;

@end


NS_ASSUME_NONNULL_END
