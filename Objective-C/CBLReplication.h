//
//  CBLReplication.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDatabase.h"
@protocol CBLReplicationDelegate;

NS_ASSUME_NONNULL_BEGIN


// *** WARNING ***  This is an unofficial placeholder API. It WILL change.


/** Activity level of a replication. */
typedef enum {
    kCBLStopped,
    kCBLOffline,
    kCBLConnecting,
    kCBLIdle,
    kCBLBusy
} CBLReplicationActivityLevel;


/** Progress of a replication. If `total` is zero, the progress is indeterminate; otherwise,
    dividing the two will produce a fraction that can be used to draw a progress bar. */
typedef struct {
    uint64_t completed;
    uint64_t total;
} CBLReplicationProgress;


/** Combined activity level and progress of a replication. */
typedef struct {
    CBLReplicationActivityLevel activity;
    CBLReplicationProgress progress;
} CBLReplicationStatus;


/** This notification is posted by a CBLReplication when its status/progress changes. */
extern NSString* const kCBLReplicationStatusChangeNotification;


/** A replication between a local and a target database.
    The target is usually remote, identified by a URL, but may instead be local.
    Replications are by default bidirectional; to change this, set either the `push` or `pull`
    property to `NO` before starting.
    The replication runs asynchronously, so set a delegate or observe the status property
    to be notified of progress. */
@interface CBLReplication : NSObject

/** The local database. */
@property (readonly, nonatomic) CBLDatabase* database;

/** The URL of the remote database to replicate with, or nil if the target database is local. */
@property (readonly, nonatomic, nullable) NSURL* remoteURL;

/** The target database, if it's local, else nil. */
@property (readonly, nonatomic, nullable) CBLDatabase* otherDatabase;

/** Should the replication push documents to the target? */
@property (nonatomic) BOOL push;

/** Should the replication pull documents from the target? */
@property (nonatomic) BOOL pull;

/** Should the replication stay active indefinitely, and push/pull changed documents? */
@property (nonatomic) BOOL continuous;

/** An object that will receive progress and error notifications. */
@property (weak, nonatomic, nullable) id<CBLReplicationDelegate> delegate;

/** Starts the replication. This method returns immediately; the replication runs asynchronously
    and will report its progress to the delegate.
    (After the replication starts, changes to the `push`, `pull` or `continuous` properties are
    ignored.) */
- (void) start;

/** Stops a running replication. This method returns immediately; when the replicator actually
    stops, the CBLReplication will change its status's activity level to `kCBLStopped`
    and call the delegate. */
- (void) stop;

/** The replication's current status: its activity level and progress. Observable. */
@property (readonly, nonatomic) CBLReplicationStatus status;

/** Any error that's occurred during replication. Observable. */
@property (readonly, nonatomic, nullable) NSError* lastError;
@end



/** A CBLReplication's delegate is called with progress information while the replication is
    running and when it stops. */
@protocol CBLReplicationDelegate <NSObject>
@optional

/** Called when a replication changes its status (activity level and/or progress) while running. */
- (void) replication: (CBLReplication*)replication
     didChangeStatus: (CBLReplicationStatus)status;

/** Called when a replication stops, either because it finished or due to an error. */
- (void) replication: (CBLReplication*)replication
    didStopWithError: (nullable NSError*)error;

@end



@interface CBLDatabase (Replication)

/** Creates a replication between this database and a remote one,
    or returns an existing one if it's already been created. */
- (CBLReplication*) replicationWithURL: (NSURL*)remote;

/** Creates a replication between this database and another local database,
    or returns an existing one if it's already been created. */
- (CBLReplication*) replicationWithDatabase: (CBLDatabase*)otherDatabase;

@end


NS_ASSUME_NONNULL_END
