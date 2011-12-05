//
//  ToyPuller.h
//  ToyCouch
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ToyDB, CouchChangeTracker;


/** Replicator that pulls from a remote CouchDB. */
@interface ToyPuller : NSObject
{
    @private
    ToyDB* _db;
    NSURL* _remote;
    CouchChangeTracker* _changeTracker;
    NSString* _lastSequence;
    NSMutableArray* _inbox;
}

- (id) initWithDB: (ToyDB*)db remote: (NSURL*)remote;

@property (readonly) NSURL* remote;

- (void) start;

@property (copy) NSString* lastSequence;

@end
