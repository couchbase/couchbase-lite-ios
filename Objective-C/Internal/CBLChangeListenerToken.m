//
//  CBLChangeListenerToken.m
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

#import "CBLChangeListenerToken.h"


@implementation CBLChangeListenerToken
{
    void (^_listener)(id);
    dispatch_queue_t _queue;
}

@synthesize key=_key;


- (instancetype) initWithListener: (void (^)(id))listener
                            queue: (nullable dispatch_queue_t)queue
{
    self = [super init];
    if (self) {
        _listener = listener;
        _queue = queue ?: dispatch_get_main_queue();
    }
    return self;
}


- (void) postChange: (id)change {
    void (^listener)(id) = _listener;
    dispatch_async(_queue, ^{
        listener(change);
    });
}


@end
