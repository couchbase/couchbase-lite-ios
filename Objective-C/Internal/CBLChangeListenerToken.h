//
//  CBLChangeListenerToken.h
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
#import "CBLListenerToken.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLChangeListenerToken<ChangeType> : NSObject <CBLListenerToken>

/**
 Initialize with the given listener block and the dispatch queue.

 @param listener The listener block.
 @param queue The dispatch queue; if nil, the main queue will be used.
 @return The CBLChangeListenerToken object.
 */
- (instancetype) initWithListener: (void (^)(ChangeType))listener
                            queue: (nullable dispatch_queue_t)queue;

/** An arbitrary value that can be associated by the client, such as a document ID. */
@property (nonatomic) id key;

/**
 Posts an asynchronous change notification to the listener block on its dispatch queue.
 */
- (void) postChange: (ChangeType)change;

@end

NS_ASSUME_NONNULL_END
