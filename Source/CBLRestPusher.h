//
//  CBLRestPusher.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/5/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLRestPuller.h"
#import "CBLDatabase.h"
#import "CBLStatus.h"


/** Replicator that pushes to a remote CouchDB. */
@interface CBLRestPusher : CBLRestReplicator
{
    BOOL _createTarget;
    BOOL _creatingTarget;
    BOOL _observing;
    BOOL _uploading;
    NSMutableArray* _uploaderQueue;
    BOOL _dontSendMultipart;
    NSMutableIndexSet* _pendingSequences;
    SequenceNumber _maxPendingSequence;
    CBLBatcher* _purgeQueue;
}

@property BOOL createTarget;

/** Returns the database revisions that still need to be pushed to the server, or nil on error. */
@property (readonly) CBL_RevisionList* unpushedRevisions;

@end


CBLStatus CBLStatusFromBulkDocsResponseItem(NSDictionary* item);
int CBLFindCommonAncestor(CBL_Revision* rev, NSArray* possibleRevIDs); // exposed for testing
