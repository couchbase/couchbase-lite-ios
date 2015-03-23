//
//  CBLDatabase+Replication.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBL_Revision.h"
#import "CBLStatus.h"
@class CBL_Replicator;


@interface CBLDatabase (Replication)

@property (readonly) NSArray* activeReplicators;

- (CBL_Replicator*) activeReplicatorLike: (CBL_Replicator*)repl;

- (void) addActiveReplicator: (CBL_Replicator*)repl;

/** Save current local uuid into the local checkpoint document. This method is called only
    when importing or replacing the database. The old localUUID is used by replicators 
    to get the local checkpoint from the imported database in order to start replicating 
    from from the current local checkpoint of the imported database after importing. */
- (BOOL) saveLocalUUIDInLocalCheckpointDocument: (NSError**)outError;

/** Put a property with a given key and value into the local checkpoint document. */
- (BOOL) putLocalCheckpointDocumentWithKey: (NSString*)key
                                     value:(id)value
                                  outError: (NSError**)outError;

/** Returns a property value specifiec by the key from the local checkpoint document. */
- (id) getLocalCheckpointDocumentPropertyValueForKey: (NSString*)key;

/** Returns local checkpoint document if it exists. Otherwise returns nil. */
- (NSDictionary*) getLocalCheckpointDocument;

// Local checkpoint document keys:
#define kCBLDatabaseLocalCheckpoint_LocalUUID @"localUUID"

@end
