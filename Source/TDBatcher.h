//
//  TDBatcher.h
//  TouchDB
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


/** Utility that queues up objects until the queue fills up or a time interval elapses,
    then passes all the objects at once to a client-supplied processor block. */
@interface TDBatcher : NSObject
{
    NSUInteger _capacity;
    NSTimeInterval _delay;
    NSMutableArray* _inbox;
    void (^_processor)(NSArray*);
}

- (id) initWithCapacity: (NSUInteger)capacity
                  delay: (NSTimeInterval)delay
              processor: (void (^)(NSArray*))block;

@property (readonly) NSUInteger count;

- (void) queueObject: (id)object;

- (void) flush;

@end
