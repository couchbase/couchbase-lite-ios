//
//  CBLQuery.h
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
@class CBLQueryParameters;
@class CBLQueryResultSet;
@class CBLQueryChange;
@protocol CBLListenerToken;


NS_ASSUME_NONNULL_BEGIN


/** 
 A database query.
 A CBLQuery instance can be constructed by calling one of the select methods.
 */
@interface CBLQuery : NSObject

/**
 A CBLQueryParameters object used for setting values to the query parameters defined
 in the query. All parameters defined in the query must be given values
 before running the query, or the query will fail.
 
 The returned CBLQueryParameters object will be readonly.
 an NSInternalInconsistencyException exception will be thrown if the parameters
 object is modified.
 */
@property (atomic, copy, nullable) CBLQueryParameters* parameters;

/** 
 Returns a string describing the implementation of the compiled query.
 This is intended to be read by a developer for purposes of optimizing the query, especially
 to add database indexes. It's not machine-readable and its format may change.
 
 As currently implemented, the result is two or more lines separated by newline characters:
 * The first line is the SQLite SELECT statement.
 * The subsequent lines are the output of SQLite's "EXPLAIN QUERY PLAN" command applied to that
 statement; for help interpreting this, see https://www.sqlite.org/eqp.html . The most
 important thing to know is that if you see "SCAN TABLE", it means that SQLite is doing a
 slow linear scan of the documents instead of using an index.
 
 @param outError If an error occurs, it will be stored here if this parameter is non-NULL.
 @return A string describing the implementation of the compiled query.
 */
- (nullable NSString*) explain: (NSError**)outError;

/** 
 Executes the query. The returning an enumerator that returns result rows one at a time.
 You can run the query any number of times, and you can even have multiple enumerators active at
 once.
 The results come from a snapshot of the database taken at the moment -run: is called, so they
 will not reflect any changes made to the database afterwards.
 
 @param outError If an error occurs, it will be stored here if this parameter is non-NULL.
 @return An enumerator of the query result.
 */
- (nullable CBLQueryResultSet*) execute: (NSError**)outError;

/**
 Adds a query change listener. Changes will be posted on the main queue.
 
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLQueryChange*))listener;

/**
 Adds a query change listener with the dispatch queue on which changes
 will be posted. If the dispatch queue is not specified, the changes will be
 posted on the main queue.
 
 @param queue The dispatch queue.
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLQueryChange*))listener;

/**
 Removes a change listener wih the given listener token.
 
 @param token The listener token.
 */
- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token;


/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
