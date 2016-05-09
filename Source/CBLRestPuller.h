//
//  CBLRestPuller.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLRestReplicator.h"
#import "CBL_Revision.h"
@class CBLChangeTracker, CBLSequenceMap, CBLPulledRevision;


// Maximum number of revision IDs to pass in an "?atts_since=" query param
#define kMaxNumberOfAttsSince 10u


/** Replicator that pulls from a remote CouchDB. */
@interface CBLRestPuller : CBLRestReplicator
{
    @private
    CBLChangeTracker* _changeTracker;   // Watcher of the _changes feed
    BOOL _canBulkGet;                   // Does the server support _bulk_get requests?
    BOOL _caughtUp;                     // Have I received all current _changes entries?
    CBLSequenceMap* _pendingSequences;  // Received but not yet copied into local DB
    NSMutableArray<CBLPulledRevision*>* _revsToPull;        // Queue of revs to download
    NSMutableArray<CBLPulledRevision*>* _deletedRevsToPull; // Separate lower-priority of deleted revs
    NSMutableArray<CBLPulledRevision*>* _bulkRevsToPull;    // revs that can be fetched in bulk
    NSUInteger _httpConnectionCount;    // Number of active NSURLConnections
    CBLBatcher* _downloadsToInsert;     // Queue of CBLPulledRevisions, with bodies, to insert
    NSMutableArray* _waitingAttachments;// CBL_AttachmentTasks waiting to start downloading
    NSMutableDictionary* _attachmentDownloads; // CBL_AttachmentID -> CBLAttachmentDownloader
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
