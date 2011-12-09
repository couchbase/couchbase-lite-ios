//
//  TDReplicator.h
//  TouchDB
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TDDatabase, TDChangeTracker;


/** Abstract base class for push or pull replications. */
@interface TDReplicator : NSObject
{
    @protected
    TDDatabase* _db;
    NSURL* _remote;
    BOOL _continuous;
    id _lastSequence;
    BOOL _running;
    NSMutableArray* _inbox;
}

- (id) initWithDB: (TDDatabase*)db
           remote: (NSURL*)remote
       continuous: (BOOL)continuous;

@property (readonly) TDDatabase* db;
@property (readonly) NSURL* remote;

@property (copy) id lastSequence;

- (void) start;
- (void) stop;
@property (readonly) BOOL running;

// protected:
- (void) addToInbox: (NSDictionary*)change;
- (void) processInbox: (NSArray*)inbox;  // override this
- (void) flushInbox;  // optionally call this to flush the inbox
- (id) sendRequest: (NSString*)method path: (NSString*)relativePath body: (id)body;

@end


