//
//  CBLLiveQuery.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/15/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLLiveQueryChange;
@class CBLQueryParameters;

NS_ASSUME_NONNULL_BEGIN

/** 
 A CBLLiveQuery automatically observes database changes and re-run the query that the CBLLiveQuery
 object is created from. If there is a new query result or an error occurred, the CBLLiveQuery will
 report the changed result via the added listener blocks.
 */
@interface CBLLiveQuery : NSObject

/**
 A CBLQueryParameters object used for setting values to the query parameters defined
 in the query. All parameters defined in the query must be given values
 before running the query, or the query will fail.
 */
@property (nonatomic, readonly) CBLQueryParameters* parameters;

/** Starts observing database changes and reports changes in the query result. */
- (void) start;

/** Stops observing database changes. */
- (void) stop;

/** 
 Returns a string describing the implementation of the compiled query.
 This is intended to be read by a developer for purposes of optimizing the query, especially
 to add database indexes. It's not machine-readable and its format may change.
 
 @param error On return, the error if any.
 @return The compiled query explanation.
 */
- (nullable NSString*) explain: (NSError**)error;

/** 
 Adds a query change listener block.
 
 @param block The block to be executed when the change is received.
 @return  An opaque object to act as the listener and for removing the listener
          when calling the -removeChangeListener: method.
 */
- (id<NSObject>) addChangeListener: (void (^)(CBLLiveQueryChange*))block;

/** 
 Removes a change listener. The given change listener is the opaque object
 returned by the -addChangeListener: method.
 
 @param listener The listener object to be removed.
 */
- (void) removeChangeListener: (id<NSObject>)listener;

@end

NS_ASSUME_NONNULL_END
