//
//  CBLChangeNotifier.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/3/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLChangeListenerToken.h"

NS_ASSUME_NONNULL_BEGIN


/** A support class that manages change listeners and broadcasts changes,
    on behalf of an object that creates the changes. */
@interface CBLChangeNotifier<ChangeType> : NSObject

/**
 Adds a change listener with the dispatch queue on which changes
 will be posted. If the dispatch queue is not specified, the changes will be
 posted on the main queue.

 @param queue The dispatch queue.
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
 */
- (CBLChangeListenerToken*) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                              listener: (void (^)(ChangeType))listener;


/**
 Removes a change listener with the given listener token.

 @param token The listener token
 @return The number of remaining listeners
 */
- (NSUInteger) removeChangeListenerWithToken: (id<CBLListenerToken>)token;


/** Posts a change notification object to all listeners, asynchronously. */
- (void) postChange: (ChangeType)change;

@end


NS_ASSUME_NONNULL_END
