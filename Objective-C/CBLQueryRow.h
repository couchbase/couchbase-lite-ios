//
//  CBLQueryRow.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDocument;

NS_ASSUME_NONNULL_BEGIN


/** A single result from a CBLQuery.
    The NSEnumeration returned by -[CBLQuery run:] produces these. */
@interface CBLQueryRow : NSObject

/** The ID of the document that produced this row. */
@property (readonly, nonatomic) NSString* documentID;

/** The sequence number of the document revision that produced this row. */
@property (readonly, nonatomic) uint64_t sequence;

/** The document that produced this row. */
@property (readonly, nonatomic) CBLDocument* document;

/** The result value at the given index (if the query has a "returning" specification.) */
- (nullable id) valueAtIndex: (NSUInteger)index;

- (bool)                booleanAtIndex: (NSUInteger)index;
- (NSInteger)           integerAtIndex: (NSUInteger)index;
- (float)               floatAtIndex:   (NSUInteger)index;
- (double)              doubleAtIndex:  (NSUInteger)index;
- (nullable NSString*)  stringAtIndex:  (NSUInteger)index;
- (nullable NSDate*)    dateAtIndex:    (NSUInteger)index;

- (nullable id) objectForSubscript: (NSUInteger)subscript;

- (instancetype) init NS_UNAVAILABLE;

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
