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

/** A CBLLiveQuery automatically observes database changes and re-run the query that the CBLLiveQuery
    object is created from. If there is a new query result or an error occurred, the CBLLiveQuery will
    report the changed result via the added listener blocks. */
@interface CBLLiveQuery : NSObject

@property (nonatomic, readonly) CBLQueryParameters* parameters;

/** Starts observing database changes and reports changes in the query result. */
- (void) run;

/** Stops observing database changes. */
- (void) stop;

/** Adds a query change listener block.
    @param block   The block to be executed when the change is received.
    @return An opaque object to act as the listener and for removing the listener
            when calling the -removeChangeListener: method. */
- (id<NSObject>) addChangeListener: (void (^)(CBLLiveQueryChange*))block;

/** Removes a change listener. The given change listener is the opaque object
    returned by the -addChangeListener: method.
    @param listener The listener object to be removed. */
- (void) removeChangeListener: (id<NSObject>)listener;

@end

NS_ASSUME_NONNULL_END
