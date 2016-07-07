//
//  CBL_Replicator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/30/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_ReplicatorSettings.h"
@class CBLDatabase, CBL_Revision, CBL_RevisionList, CBLCookieStorage, CBL_AttachmentTask;


#ifdef MYLOGGING
UsingLogDomain(Sync);
UsingLogDomain(SyncPerf);
#endif


/** Describes the current status of a CBL_Replicator. */
typedef NS_ENUM(unsigned, CBL_ReplicatorStatus) {
    kCBLReplicatorStopped, /**< The replicator is finished or hit a fatal error. */
    kCBLReplicatorOffline, /**< The remote host is currently unreachable. */
    kCBLReplicatorIdle,    /**< Continuous replicator is caught up and waiting for more changes.*/
    kCBLReplicatorActive   /**< The replicator is actively transferring data. */
};


typedef void (^CBL_ReplicatorAttachmentProgressBlock)(uint64_t bytesRead,
                                                      uint64_t contentLength,
                                                      NSError* error);


/** Posted when .changesProcessed, .changesTotal or .status changes. */
extern NSString* CBL_ReplicatorProgressChangedNotification;

/** Posted when replicator stops running. */
extern NSString* CBL_ReplicatorStoppedNotification;



/** Protocol that replicator implementations must implement. */
@protocol CBL_Replicator <NSObject>

+ (BOOL) needsRunLoop;

- (id<CBL_Replicator>) initWithDB: (CBLDatabase*)db
                         settings: (CBL_ReplicatorSettings*)settings;

@property (readonly, nonatomic) CBL_ReplicatorSettings* settings;

@property (readonly, nonatomic) CBLDatabase* db;

@property (readonly) NSString* remoteCheckpointDocID;

@property (readonly) CBL_ReplicatorStatus status;

/** Latest error encountered while replicating.
    This is set to nil when starting. It may also be set to nil by the client if desired.
    Not all errors are fatal; if .running is still true, the replicator will retry. */
@property (strong, nonatomic) NSError* error;

/** Number of changes (docs or other metadata) transferred so far. */
@property (readonly, nonatomic) NSUInteger changesProcessed;

/** Approximate total number of changes to transfer.
    This is only an estimate and its value will change during replication. It starts at zero and returns to zero when replication stops. */
@property (readonly, nonatomic) NSUInteger changesTotal;

/** A unique-per-process string identifying this replicator instance. */
@property (copy, nonatomic) NSString* sessionID;

@property (readonly) SecCertificateRef serverCert;

/** Starts the replicator.
    Replicators run asynchronously so nothing will happen until later.
    A replicator can only be started once; don't reuse it after it stops. */
- (void) start;

/** Request to stop the replicator.
    Any pending asynchronous operations will be canceled.
    CBL_ReplicatorStoppedNotification will be posted when it finally stops. */
- (void) stop;

/** Setting suspended to YES pauses the replicator. */
@property (nonatomic) BOOL suspended;

/** Called by CBLDatabase to notify active replicators that it's about to close. */
- (void) databaseClosing;

/** Current lastSequence tracked by the replicator. */
@property (readonly) id lastSequence;

#if DEBUG // for unit tests
@property (readonly) BOOL active;
@property (readonly) BOOL savingCheckpoint;
#endif

@optional
/** The currently active tasks, each represented by an NSProgress object. (Observable) */
@property (readonly) NSArray* activeTasksInfo;

/** Requests asynchronous download of the given attachment from the server. */
- (void) downloadAttachment: (CBL_AttachmentTask*)attachment;

@end
