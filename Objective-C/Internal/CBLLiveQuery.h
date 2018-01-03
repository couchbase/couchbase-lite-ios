//
//  CBLLiveQuery.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/15/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQuery;
@class CBLQueryChange;
@class CBLQueryParameters;
@protocol CBLListenerToken;

NS_ASSUME_NONNULL_BEGIN

/** 
 A CBLLiveQuery automatically observes database changes and re-run the query that the CBLLiveQuery
 object is created from. If there is a new query result or an error occurred, the CBLLiveQuery will
 report the changed result via the added listener blocks.
 */
@interface CBLLiveQuery : NSObject

/** Initialize with a Query. */
- (instancetype) initWithQuery: (CBLQuery*)query;

/** Starts observing database changes and reports changes in the query result. */
- (void) start;

/** Stops observing database changes. */
- (void) stop;

/** Call this method to notify that the query parameters have been changed,
    the CBLLiveQuery object will re-run the query if it's already started. */
- (void) queryParametersChanged;

/** 
 Adds a query change listener with the given dispatch queue on which the changes
 will be posted. If the dispatch queue is not specified, the changes will be
 posted on the main queue.
 
 @param queue The dispatch queue.
 @param listener The listener block to post the changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLQueryChange*))listener;

/** 
 Removes a change listener with the given listener token.
 
 @param listenerToken The listener token.
 */
- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)listenerToken;

@end

NS_ASSUME_NONNULL_END
