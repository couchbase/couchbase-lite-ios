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


/** Status of a replication. */
typedef enum {
    kCBLStopped,
    kCBLOffline,
    kCBLConnecting,
    kCBLIdle,
    kCBLBusy
} CBLReplicationStatus;



/** A replication between a local and a remote database.
    Before starting the replication, you just set either the `push` or `pull` property to `YES`.
    (You can also set both.) */
@interface CBLReplication : NSObject

@property (readonly, nonatomic) CBLDatabase* database;
@property (readonly, nonatomic) NSURL* remoteURL;

/** Should the replication push documents to the remote? */
@property (nonatomic) BOOL push;

/** Should the replication pull documents from the remote? */
@property (nonatomic) BOOL pull;

/** Should the replication stay active indefinitely, and push/pull changed documents? */
@property (nonatomic) BOOL continuous;

/** An object that will receive progress and error notifications. */
@property (weak, nullable, nonatomic) id<CBLReplicationDelegate> delegate;

/** Starts the replication. This method returns immediately; the replication runs asynchronously
    and will report its progress to the delegate. */
- (void) start;

/** Stops a running replication. This method returns immediately; the replication will call the
    delegate after it actually stops. */
- (void) stop;

@end



/** Called with progress information while a CBLReplication is running. */
@protocol CBLReplicationDelegate <NSObject>

/** Called when a replication changes its state while running. */
- (void) replication: (CBLReplication*)replication
     didChangeStatus: (CBLReplicationStatus)status;

/** Called when a replication stops, either because it finished or due to an error. */
- (void) replication: (CBLReplication*)replication
    didStopWithError: (nullable NSError*)error;

@end



@interface CBLDatabase (Replication)

/** Creates a replication between this database and a remote one,
    or returns an existing one if it's already been created. */
- (CBLReplication*) replicationWithDatabase: (NSURL*)remote;

@end


NS_ASSUME_NONNULL_END
