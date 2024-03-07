//
//  CBLCollectionChangeObservable.h
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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

#import <CouchbaseLite/CBLCollectionChange.h>
#import <CouchbaseLite/CBLListenerToken.h>

NS_ASSUME_NONNULL_BEGIN
/**
 The CollectionChangeObservable interface represents the object that can notify
 change events that occur to documents in collections.
 */
@protocol CBLCollectionChangeObservable <NSObject>

/**
 Add a change listener to listen to change events occurring to any documents in the collection.
 To remove the listener, call remove() function on the returned listener token.
 
 If the collection is deleted or the database is closed, a warning message will be logged.
 
 @param listener The listener to post the changes.
 @return An opaque listener token object for removing the listener
 */
- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLCollectionChange*))listener;

/**
 Add a change listener to listen to change events occurring to any documents in the collection.
 If a dispatch queue is given, the events will be posted on the dispatch queue.
 To remove the listener, call remove() function on the returned listener token.
 
 If the collection is deleted or the database is closed, a warning message will be logged.
 
 @param queue The dispatch queue.
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener
 */
- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLCollectionChange*))listener;


@end

NS_ASSUME_NONNULL_END
