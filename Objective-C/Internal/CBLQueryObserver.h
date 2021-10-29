//
//  CBLQueryObserver.h
//  CouchbaseLite
//
//  Copyright (c) 2021 Couchbase, Inc All rights reserved.
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

@class CBLQuery;
@class CBLQueryChange;
@protocol CBLListenerToken;

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryObserver : NSObject

/** Initialize with a Query. */
- (instancetype) initWithQuery: (CBLQuery*)query columnNames:(nonnull NSDictionary *)columnNames;

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

@end

NS_ASSUME_NONNULL_END
