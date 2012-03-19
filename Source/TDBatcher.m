//
//  TDBatcher.m
//  TouchDB
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDBatcher.h"
#import "MYBlockUtils.h"


@implementation TDBatcher


- (id) initWithCapacity: (NSUInteger)capacity
                  delay: (NSTimeInterval)delay
              processor: (void (^)(NSArray*))block {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _delay = delay;
        _processor = [block copy];
    }
    return self;
}


- (void)dealloc {
    [_inbox release];
    [_processor release];
    [super dealloc];
}


- (void) processNow {
    if (_inbox.count == 0)
        return;
    NSMutableArray* toProcess = _inbox;
    _inbox = nil;
    _processor(toProcess);
    [toProcess release];
}


- (void) queueObject: (id)object {
    if (_inbox.count >= _capacity)
        [self flush];
    if (!_inbox) {
        _inbox = [[NSMutableArray alloc] init];
        MYAfterDelay(_delay, ^{[self processNow];});
    }
    [_inbox addObject: object];
}


- (void) flush {
    if (_inbox)
        [self processNow];
}


- (NSUInteger) count {
    return _inbox.count;
}


@end
