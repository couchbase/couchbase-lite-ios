//
//  TDPuller.h
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDReplicator.h"
@class TDChangeTracker;


/** Replicator that pulls from a remote CouchDB. */
@interface TDPuller : TDReplicator
{
    @private
    TDChangeTracker* _changeTracker;
    NSThread* _thread;
    NSMutableArray* _revsToPull;
    NSUInteger _httpConnectionCount;
    TDBatcher* _revsToInsert;
}

@end
