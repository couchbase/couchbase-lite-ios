//
//  TouchReplication.h
//  TouchDB
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchModel.h"
@class TouchDatabase, TDDatabase, TDServer, TDReplicator;


typedef enum {
    kTouchReplicationStopped,
    kTouchReplicationOffline,
    kTouchReplicationIdle,
    kTouchReplicationActive
} TouchReplicationMode;


/** A 'push' or 'pull' replication between a local and a remote database.
    Replications can be one-shot, continuous or persistent.
    Saving a replication makes it persistent. */
@interface TouchReplication : TouchModel
{
    @private
    NSURL* _remoteURL;
    bool _pull;
    NSThread* _thread;
    bool _started;
    bool _running;
    unsigned _completed, _total;
    TouchReplicationMode _mode;
    NSError* _error;
    
    TDReplicator* _replicator;  // ONLY used on the server thread
    TDDatabase* _serverDatabase;
}

/** The local database being replicated to/from. */
@property (nonatomic, readonly) TouchDatabase* localDatabase;

/** The URL of the remote database. */
@property (nonatomic, readonly) NSURL* remoteURL;

/** Does the replication pull from (as opposed to push to) the target? */
@property (nonatomic, readonly) bool pull;


#pragma mark - OPTIONS:

/** Is this replication remembered persistently in the _replicator database?
    Persistent continuous replications will automatically restart on the next launch. */
@property bool persistent;

/** Should the target database be created if it doesn't already exist? (Defaults to NO). */
@property (nonatomic) bool create_target;

/** Should the replication operate continuously, copying changes as soon as the source database is modified? (Defaults to NO). */
@property (nonatomic) bool continuous;

/** Path of an optional filter function to run on the source server.
    Only documents for which the function returns true are replicated.
    The path looks like "designdocname/filtername". */
@property (nonatomic, copy) NSString* filter;

/** Parameters to pass to the filter function.
    Should be a JSON-compatible dictionary. */
@property (nonatomic, copy) NSDictionary* query_params;

/** Sets the documents to specify as part of the replication. */
@property (copy) NSArray *doc_ids;

/** Extra HTTP headers to send in all requests to the remote server.
    Should map strings (header names) to strings. */
@property (nonatomic, copy) NSDictionary* headers;

/** OAuth parameters that the replicator should use when authenticating to the remote database.
    Keys in the dictionary should be "consumer_key", "consumer_secret", "token", "token_secret", and optionally "signature_method". */
@property (nonatomic, copy) NSDictionary* OAuth;


#pragma mark - STATUS:

/** Starts the replication, asynchronously.
    @return  The operation to start replication, or nil if replication is already started. */
- (void) start;

/** Stops replication, asynchronously. */
- (void) stop;

@property (nonatomic, readonly) bool running;

/** The number of completed changes processed, if the task is active, else 0 (observable). */
@property (nonatomic, readonly) unsigned completed;

/** The total number of changes to be processed, if the task is active, else 0 (observable). */
@property (nonatomic, readonly) unsigned total;

@property (nonatomic, readonly, retain) NSError* error;

@property (nonatomic, readonly) TouchReplicationMode mode;


@end


/** This notification is posted by a TouchReplication when its progress changes. */
extern NSString* const kTouchReplicationChangeNotification;
