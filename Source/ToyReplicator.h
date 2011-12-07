//
//  ToyReplicator.h
//  ToyCouch
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ToyDB, CouchChangeTracker;


/** Abstract base class for push or pull replications. */
@interface ToyReplicator : NSObject
{
    @protected
    ToyDB* _db;
    NSURL* _remote;
    BOOL _continuous;
    id _lastSequence;
    BOOL _running;
    NSMutableArray* _inbox;
}

- (id) initWithDB: (ToyDB*)db
           remote: (NSURL*)remote
       continuous: (BOOL)continuous;

@property (readonly) ToyDB* db;
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


