//
//  CBLTimer.m
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

#import "CBLTimer.h"

@implementation CBLTimer

+ (dispatch_source_t) scheduleIn: (nullable dispatch_queue_t)queue
                           after: (double)seconds
                           block: (dispatch_block_t)block {
    
    dispatch_queue_t q = queue ?: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    if (t) {
        dispatch_source_set_timer(t,
                                  dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                                  (int64_t)(seconds * NSEC_PER_SEC),
                                  (1ull * NSEC_PER_SEC) / 10);
        dispatch_source_set_event_handler(t, block);
        dispatch_resume(t);
    }
    return t;
}

@end
