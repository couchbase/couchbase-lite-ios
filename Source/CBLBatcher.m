//
//  CBLBatcher.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLBatcher.h"

@implementation CBLBatcher
{
    NSUInteger _capacity;
    NSTimeInterval _delay;
    NSMutableArray* _inbox;
    bool _scheduled;
    NSTimeInterval _scheduledDelay;
    CFAbsoluteTime _lastProcessedTime;
    void (^_processor)(NSArray*);
}


- (instancetype) initWithCapacity: (NSUInteger)capacity
                            delay: (NSTimeInterval)delay
                        processor: (void (^)(NSArray*))block
{
    self = [super init];
    if (self) {
        _capacity = capacity;
        _delay = delay;
        _processor = [block copy];
    }
    return self;
}




- (void) unschedule {
    _scheduled = false;
    [NSObject cancelPreviousPerformRequestsWithTarget: self
                                             selector: @selector(processNow) object:nil];
}


- (void) scheduleWithDelay: (NSTimeInterval)delay {
    if (_scheduled && delay < _scheduledDelay)
        [self unschedule];
    if (!_scheduled) {
        _scheduled = true;
        _scheduledDelay = delay;
        [self performSelector: @selector(processNow) withObject: nil afterDelay: delay];
    }
}


- (void) processNow {
    _scheduled = false;
    NSArray* toProcess;
    NSUInteger count = _inbox.count;
    if (count == 0) {
        return;
    } else if (count <= _capacity) {
        toProcess = _inbox;
        _inbox = nil;
    } else {
        toProcess = [_inbox subarrayWithRange: NSMakeRange(0, _capacity)];
        [_inbox removeObjectsInRange: NSMakeRange(0, _capacity)];
        // There are more objects left, so schedule them Real Soon:
        [self scheduleWithDelay: 0.0];
    }

    __unused id retainSelf = self;  // Prevent _processor block from deallocating me (#508)

    _processor(toProcess);
    _lastProcessedTime = CFAbsoluteTimeGetCurrent();
}


- (void) queueObjects: (NSArray*)objects {
    if (objects.count == 0)
        return;
    if (!_inbox)
        _inbox = [[NSMutableArray alloc] init];
    [_inbox addObjectsFromArray: objects];

    if (_inbox.count < _capacity) {
        // Schedule the processing. To improve latency, if we haven't processed anything
        // in at least our delay time, rush these object(s) through ASAP:
        NSTimeInterval delay = _delay;
        if (CFAbsoluteTimeGetCurrent() - _lastProcessedTime >= _delay)
            delay = 0.0;
        [self scheduleWithDelay: delay];
    } else {
        // If inbox fills up, process it immediately:
        [self unschedule];
        [self processNow];
    }
}


- (void) queueObject: (id)object {
    [self queueObjects: @[object]];
}


- (void) flush {
    [self unschedule];
    [self processNow];
}


- (void) flushAll {
    __unused id retainSelf = self;  // Prevent _processor block from deallocating me (#508)

    while (_inbox.count > 0) {
        [self unschedule];
        NSArray* toProcess = _inbox;
        _inbox = nil;
        _processor(toProcess);
        _lastProcessedTime = CFAbsoluteTimeGetCurrent();
    }
}


- (void) clear {
    [self unschedule];
    _inbox = nil;
}


- (NSUInteger) count {
    return _inbox.count;
}


@end
