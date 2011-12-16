//
//  TDBatcher.m
//  TouchDB
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDBatcher.h"

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
        [self performSelector: @selector(processNow) withObject: nil afterDelay: _delay];
    }
    [_inbox addObject: object];
}


- (void) flush {
    if (_inbox) {
        [NSObject cancelPreviousPerformRequestsWithTarget: self
                                                 selector: @selector(processNow) object:nil];
        [self processNow];
    }
}


- (NSUInteger) count {
    return _inbox.count;
}


@end
