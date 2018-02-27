//
//  CBLQueryRow.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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
@class CBLMutableDocument;

NS_ASSUME_NONNULL_BEGIN


/** 
 A single result from a CBLQuery.
 The NSEnumeration returned by -[CBLQuery run:] produces these.
 */
@interface CBLQueryRow : NSObject

/** The number of values in this row (if the query has a "returning" specification.) */
@property (readonly, nonatomic) NSUInteger valueCount;

/** 
 The result value at the given index (if the query has a "returning" specification.)
 
 @param index The value index.
 @return The result value.
 */
- (nullable id) valueAtIndex: (NSUInteger)index;

/** 
 The result boolean value at the given index.
 
 @param index The value index.
 @return The result boolean value.
 */
- (bool) booleanAtIndex: (NSUInteger)index;

/** 
 The result integer value at the given index.
 
 @param index The value index.
 @return The result integer value.
 */
- (NSInteger) integerAtIndex: (NSUInteger)index;

/** 
 The result float value at the given index.
 
 @param index The value index.
 @return The result float value.
 */
- (float) floatAtIndex:   (NSUInteger)index;

/** 
 The result double value at the given index.
 
 @param index The value index.
 @return The result double value.
 */
- (double) doubleAtIndex:  (NSUInteger)index;

/** 
 The result string value at the given index.
 
 @param index The value index.
 @return The result string value.
 */
- (nullable NSString*) stringAtIndex:  (NSUInteger)index;

/** 
 The result date value at the given index.
 
 @param index The value index.
 @return The result date value.
 */
- (nullable NSDate*) dateAtIndex:    (NSUInteger)index;

/** The result object value at the given index.
 
 @param subscript The value index.
 @return The result object value.
 */
- (nullable id) objectAtIndexedSubscript: (NSUInteger)subscript;

/** Not Available. */
- (instancetype) init NS_UNAVAILABLE;

@end


/** A single result from a full-text CBLQuery. */
@interface CBLFullTextQueryRow : CBLQueryRow

/** 
 The text emitted when the view was indexed (the argument to CBLTextKey()) which contains the
 match(es).
 */
@property (readonly, nullable) NSString* fullTextMatched;

/** 
 The number of query words that were found in the fullText.
 (If a query word appears more than once, only the first instance is counted.)
 */
@property (readonly, nonatomic) NSUInteger matchCount;

/** 
 The character range in the fullText of a particular match.
 
 @param matchNumber The zero based match index.
 @return The charater range in the fullText of the given match index.
 */
- (NSRange) textRangeOfMatch: (NSUInteger)matchNumber;

/** 
 The index of the search term matched by a particular match. Search terms are the individual
 words in the full-text search expression, skipping duplicates and noise/stop-words. They're
 numbered from zero.
 
 @param matchNumber The zero based match index.
 @return The index of the search term matched by the given match index.
 */
- (NSUInteger) termIndexOfMatch: (NSUInteger)matchNumber;

@end


NS_ASSUME_NONNULL_END
