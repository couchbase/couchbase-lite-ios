//
//  CBLBatcher.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


/** Utility that queues up objects until the queue fills up or a time interval elapses,
    then passes objects, in groups of its capacity, to a client-supplied processor block. */
@interface CBLBatcher : NSObject

/** Initializes a batcher.
    @param capacity  The maximum number of objects to batch up. If the queue reaches this size, the queued objects will be sent to the processor immediately.
    @param delay  The maximum waiting time to collect objects before processing them. In some circumstances objects will be processed sooner.
    @param processor  The block that will be called to process the objects. */
- (instancetype) initWithCapacity: (NSUInteger)capacity
                            delay: (NSTimeInterval)delay
                        processor: (void (^)(NSArray*))processor;

/** The number of objects currently in the queue. */
@property (readonly) NSUInteger count;

/** Adds an object to the queue. */
- (void) queueObject: (id)object;

/** Adds multiple objects to the queue. */
- (void) queueObjects: (NSArray*)objects;

/** Sends queued objects to the processor block (up to the capacity). */
- (void) flush;

/** Sends _all_ the queued objects at once to the processor block.
    After this method returns, the queue is guaranteed to be empty.*/
- (void) flushAll;

/** Empties the queue without processing any of the objects in it. */
- (void) clear;

@end
