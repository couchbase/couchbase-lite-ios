//
//  TDPuller.h
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDReplicator.h"
#import "TDRevision.h"
@class TDChangeTracker, TDSequenceMap;


/** Replicator that pulls from a remote CouchDB. */
@interface TDPuller : TDReplicator
{
    @private
    TDChangeTracker* _changeTracker;
    TDSequenceMap* _pendingSequences;
    NSMutableArray* _revsToPull;
    NSUInteger _httpConnectionCount;
    TDBatcher* _downloadsToInsert;
}

@end



/** A revision received from a remote server during a pull. Tracks the opaque remote sequence ID. */
@interface TDPulledRevision : TDRevision
{
@private
    NSString* _remoteSequenceID;
}

@property (copy) NSString* remoteSequenceID;

@end
