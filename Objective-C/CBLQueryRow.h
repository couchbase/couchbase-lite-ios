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

/** The ID of the document that produced this row.
    This will be nil if the query uses aggregate functions, since it will then be composed of
    aggregate data from multiple rows. */
@property (readonly, nonatomic) NSString* documentID;

/** The sequence number of the document revision that produced this row.
    This will be 0 if the query uses aggregate functions, since it will then be composed of
    aggregate data from multiple rows. */
@property (readonly, nonatomic) uint64_t sequence;

/** The document that produced this row.
    This will be nil if the query uses aggregate functions, since it will then be composed of
    aggregate data from multiple rows. */
@property (readonly, nonatomic) CBLDocument* document;

/** The number of values in this row (if the query has a "returning" specification.) */
@property (readonly, nonatomic) NSUInteger valueCount;

/** The result value at the given index (if the query has a "returning" specification.)
    @param index    the value index.
    @return the result value. */
- (nullable id) valueAtIndex: (NSUInteger)index;

/** The result boolean value at the given index. 
    @param index    the value index.
    @return the result boolean value. */
- (bool)                booleanAtIndex: (NSUInteger)index;

/** The result integer value at the given index. 
    @param index    the value index.
    @return the result integer value. */
- (NSInteger)           integerAtIndex: (NSUInteger)index;

/** The result float value at the given index.
    @param index    the value index.
    @return the result float value. */
- (float)               floatAtIndex:   (NSUInteger)index;

/** The result double value at the given index. 
    @param index    the value index.
    @return the result double value. */
- (double)              doubleAtIndex:  (NSUInteger)index;

/** The result string value at the given index. 
    @param index    the value index.
    @return the result string value. */
- (nullable NSString*)  stringAtIndex:  (NSUInteger)index;

/** The result date value at the given index. 
    @param index    the value index.
    @return the result date value. */
- (nullable NSDate*)    dateAtIndex:    (NSUInteger)index;

/** The result object value at the given index. 
    @param subscript    the value index.
    @return  the result object value. */
- (nullable id) objectAtIndexedSubscript: (NSUInteger)subscript;

/** Not Available. */
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

/** The character range in the fullText of a particular match. 
    @param matchNumber  the zero based match index.
    @return the charater range in the fullText of the given match index. */
- (NSRange) textRangeOfMatch: (NSUInteger)matchNumber;

/** The index of the search term matched by a particular match. Search terms are the individual
    words in the full-text search expression, skipping duplicates and noise/stop-words. They're
    numbered from zero. 
    @param matchNumber  the zero based match index.
    @return The index of the search term matched by the given match index. */
- (NSUInteger) termIndexOfMatch: (NSUInteger)matchNumber;

@end


NS_ASSUME_NONNULL_END
