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

@interface CBLChangeListenerToken : NSObject <CBLListenerToken>

/**
 The listener block for posting changes.
 */
@property (nonatomic, readonly, copy) id listener;

/**
 The dispatch queue to post changes onto.
 */
@property (nonatomic, readonly) dispatch_queue_t queue;

/**
 Initialize with the given listener block and the dispatch queue.
 Without specifying the dispatch queue, the main queue will be used.

 @param listener The listener block.
 @param queue The dispatch queue.
 @return The CBLChangeListenerToken object.
 */
- (instancetype) initWithListener: (id)listener
                            queue: (nullable dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
