//
//  CBLChangeNotifier.h
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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
