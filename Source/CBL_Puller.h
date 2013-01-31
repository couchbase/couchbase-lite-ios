//
//  CBL_Puller.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "CBL_Replicator.h"
#import "CBL_Revision.h"
@class CBLChangeTracker, CBLSequenceMap;


/** Replicator that pulls from a remote CouchDB. */
@interface CBL_Puller : CBL_Replicator
{
    @private
    CBLChangeTracker* _changeTracker;
    BOOL _caughtUp;                     // Have I received all current _changes entries?
    CBLSequenceMap* _pendingSequences;   // Received but not yet copied into local DB
    NSMutableArray* _revsToPull;        // Queue of CBLPulledRevisions to download
    NSMutableArray* _deletedRevsToPull; // Separate lower-priority of deleted CBLPulledRevisions
    NSMutableArray* _bulkRevsToPull;    // CBLPulledRevisions that can be fetched in bulk
    NSUInteger _httpConnectionCount;    // Number of active NSURLConnections
    CBLBatcher* _downloadsToInsert;      // Queue of CBLPulledRevisions, with bodies, to insert in DB
}

@end



/** A revision received from a remote server during a pull. Tracks the opaque remote sequence ID. */
@interface CBLPulledRevision : CBL_Revision
{
@private
    id _remoteSequenceID;
    bool _conflicted;
}

@property (copy) id remoteSequenceID;
@property bool conflicted;

@end
