//
//  CBLDatabase+Replication.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBL_Revision.h"
@class CBL_Replicator;


@interface CBLDatabase (Replication)

@property (readonly) NSArray* activeReplicators;

- (CBL_Replicator*) activeReplicatorLike: (CBL_Replicator*)repl;

- (void) addActiveReplicator: (CBL_Replicator*)repl;

- (BOOL) findMissingRevisions: (CBL_RevisionList*)revs;

@end
