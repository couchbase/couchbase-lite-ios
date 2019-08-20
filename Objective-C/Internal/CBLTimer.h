//
//  CBLTimer.h
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

@interface CBLTimer : NSObject

/**
 Schedules the block to execute after given seconds, on a given dispatch queue.
 
 Returns the dispatch source object, which can be used to cancel already scheduled timer.
 
 @param queue The dispatch queue on which the block will be executed. If nil, it uses global default queue.
 @param seconds The delay after the block will start execute.
 @param block The handler block to submit for later execution.
 */
+ (dispatch_source_t) scheduleIn: (nullable dispatch_queue_t)queue
                           after: (double)seconds
                           block: (dispatch_block_t)block;

/**
Cancels an already scheduled timer.

@param timer The dispatch source object, which receives during the schedule of timer.
*/
+ (void) cancel: (dispatch_source_t)timer;

@end

NS_ASSUME_NONNULL_END
