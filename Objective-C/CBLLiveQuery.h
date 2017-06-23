//
//  CBLLiveQuery.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/15/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLLiveQueryChange;

NS_ASSUME_NONNULL_BEGIN

/** A CBLLiveQuery automatically observes database changes and re-run the query that the CBLLiveQuery
    object is created from. If there is a new query result or an error occurred, the CBLLiveQuery will
    report the changed result via the added listener blocks. */
@interface CBLLiveQuery : NSObject

/** Starts observing database changes and reports changes in the query result. */
- (void) run;

/** Stops observing database changes. */
- (void) stop;

/** Adds a query result change listener block.
    @param block    a change listener block
    @return the opaque listener object used for removing the added change listener block. */
- (id<NSObject>) addChangeListener: (void (^)(CBLLiveQueryChange*))block;

/** Removed a change listener.
    @param listener  a listener object received when adding the change listener block. */
- (void) removeChangeListener: (id<NSObject>)listener;

@end

NS_ASSUME_NONNULL_END
