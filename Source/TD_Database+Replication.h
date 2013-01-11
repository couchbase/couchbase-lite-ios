//
//  TD_Database+Replication.h
//  TouchDB
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TD_Database.h>
@class TDReplicator;


@interface TD_Database (Replication)

@property (readonly) NSArray* activeReplicators;

- (TDReplicator*) activeReplicatorLike: (TDReplicator*)repl;

- (void) addActiveReplicator: (TDReplicator*)repl;

- (BOOL) findMissingRevisions: (TD_RevisionList*)revs;

@end
