//
//  CBLDatabase+Replication.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBL_Revision.h"
#import "CBLStatus.h"
@protocol CBL_Replicator;
@class CBL_ReplicatorSettings;


@interface CBLDatabase (Replication)

@property (readonly) NSArray* activeReplicators;

- (id<CBL_Replicator>) activeReplicatorLike: (id<CBL_Replicator>)repl;

- (void) addActiveReplicator: (id<CBL_Replicator>)repl;

/** Save current local uuid into the local checkpoint document. This method is called only
    when importing or replacing the database. The old localUUID is used by replicators 
    to get the local checkpoint from the imported database in order to start replicating 
    from from the current local checkpoint of the imported database after importing. */
- (BOOL) saveLocalUUIDInLocalCheckpointDocument: (NSError**)outError;

/** Put a property with a given key and value into the local checkpoint document. */
- (BOOL) putLocalCheckpointDocumentWithKey: (NSString*)key
                                     value:(id)value
                                  outError: (NSError**)outError;

/** Remove a property with a given key from the local checkpoint document. */
- (BOOL) removeLocalCheckpointDocumentWithKey: (NSString*)key
                                     outError: (NSError**)outError;

/** Returns a property value specifiec by the key from the local checkpoint document. */
- (id) getLocalCheckpointDocumentPropertyValueForKey: (NSString*)key;

/** Returns local checkpoint document if it exists. Otherwise returns nil. */
- (NSDictionary*) getLocalCheckpointDocument;

// Local checkpoint document keys:
#define kCBLDatabaseLocalCheckpoint_LocalUUID @"localUUID"

- (void) stopAndForgetReplicator: (id<CBL_Replicator>)repl;
- (NSString*) lastSequenceWithCheckpointID: (NSString*)checkpointID;
- (BOOL) setLastSequence: (NSString*)lastSequence withCheckpointID: (NSString*)checkpointID;

/** Get the current last sequence for a given replicator settings */
- (NSString*) lastSequenceForReplicator: (CBL_ReplicatorSettings*)settings;

/** Get unpushed revisions for a replicator since a given sequence */
- (CBL_RevisionList*) unpushedRevisionsSince: (NSString*)sequence
                                      filter: (CBLFilterBlock)filter
                                      params: (NSDictionary*)filterParams
                                       error: (NSError**)outError;

@end
