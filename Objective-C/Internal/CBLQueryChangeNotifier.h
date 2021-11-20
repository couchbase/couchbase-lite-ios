//
//  CBLQueryChangeNotifier.h
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

#import "CBLChangeNotifier.h"

@class CBLQuery;
@class CBLQueryChange;

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryChangeNotifier<ChangeType> : CBLChangeNotifier

/** Starts an observer and listener on the queue. */
- (CBLChangeListenerToken*) addQueryChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                                   listener: (void (^)(CBLQueryChange*))listener
                                                      queue: (CBLQuery*)query
                                                columnNames: (NSDictionary *)columnNames;

/** Removes the observer and listener*/
- (void) removeQueryChangeListenerWithToken: (id<CBLListenerToken>)token;

#pragma mark - Unavailable APIs

- (CBLChangeListenerToken*) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                              listener: (void (^)(ChangeType))listener NS_UNAVAILABLE;

- (NSUInteger) removeChangeListenerWithToken:(id<CBLListenerToken>)token NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
