//
//  TDBatcher.h
//  TouchDB
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


/** Utility that queues up objects until the queue fills up or a time interval elapses,
    then passes objects, in groups of its capacity, to a client-supplied processor block. */
@interface TDBatcher : NSObject
{
    NSUInteger _capacity;
    NSTimeInterval _delay;
    NSMutableArray* _inbox;
    bool _scheduled;
    NSTimeInterval _scheduledDelay;
    void (^_processor)(NSArray*);
}

- (id) initWithCapacity: (NSUInteger)capacity
                  delay: (NSTimeInterval)delay
              processor: (void (^)(NSArray*))block;

@property (readonly) NSUInteger count;

- (void) queueObject: (id)object;
- (void) queueObjects: (NSArray*)objects;

/** Sends queued objects to the processor block (up to the capacity). */
- (void) flush;

/** Sends _all_ the queued objects at once to the processor block.
    After this method returns, all the queued objects will have been processed.*/
- (void) flushAll;

@end
