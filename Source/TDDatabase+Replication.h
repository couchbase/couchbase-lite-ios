//
//  TDDatabase+Replication.h
//  TouchDB
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TDDatabase.h>
@class TDReplicator;


@interface TDDatabase (Replication)

@property (readonly) NSArray* activeReplicators;

- (TDReplicator*) activeReplicatorWithRemoteURL: (NSURL*)remote
                                           push: (BOOL)push;

- (TDReplicator*) replicatorWithRemoteURL: (NSURL*)remote
                                     push: (BOOL)push
                               continuous: (BOOL)continuous;

- (BOOL) findMissingRevisions: (TDRevisionList*)revs;

@end
