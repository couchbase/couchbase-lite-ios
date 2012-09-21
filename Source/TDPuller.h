//
//  TDPuller.h
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDReplicator.h"
#import <TouchDB/TDRevision.h>
@class TDChangeTracker, TDSequenceMap;


/** Replicator that pulls from a remote CouchDB. */
@interface TDPuller : TDReplicator
{
    @private
    TDChangeTracker* _changeTracker;
    BOOL _caughtUp;                     // Have I received all current _changes entries?
    TDSequenceMap* _pendingSequences;   // Received but not yet copied into local DB
    NSMutableArray* _revsToPull;        // Queue of TDPulledRevisions to download
    NSMutableArray* _deletedRevsToPull; // Separate lower-priority of deleted TDPulledRevisions
    NSMutableArray* _bulkRevsToPull;    // TDPulledRevisions that can be fetched in bulk
    NSUInteger _httpConnectionCount;    // Number of active NSURLConnections
    TDBatcher* _downloadsToInsert;      // Queue of TDPulledRevisions, with bodies, to insert in DB
}

@end



/** A revision received from a remote server during a pull. Tracks the opaque remote sequence ID. */
@interface TDPulledRevision : TDRevision
{
@private
    NSString* _remoteSequenceID;
    bool _conflicted;
}

@property (copy) NSString* remoteSequenceID;
@property bool conflicted;

@end
