//
//  CBLReplicator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDatabase.h"
@class CBLReplicatorConfiguration;

NS_ASSUME_NONNULL_BEGIN


/** Activity level of a replicator. */
typedef enum {
    kCBLStopped,    ///< The replication is finished or hit a fatal error.
    kCBLIdle,       ///< The replication is unactive; either waiting for changes or offline
                    ///< as the remote host is unreachable.
    kCBLBusy        ///< The replication is actively transferring data.
} CBLReplicatorActivityLevel;


/** Progress of a replicator. If `total` is zero, the progress is indeterminate; otherwise,
    dividing the two will produce a fraction that can be used to draw a progress bar. */
typedef struct {
    uint64_t completed; ///< The number of completed changes processed.
    uint64_t total;     ///< The total number of changes to be processed.
} CBLReplicatorProgress;


/** Combined activity level and progress of a replicator. */
@interface CBLReplicatorStatus: NSObject

/** The current activity level. */
@property (readonly, nonatomic) CBLReplicatorActivityLevel activity;

/** The current progress of the replicator. */
@property (readonly, nonatomic) CBLReplicatorProgress progress;

@end


/** This notification is posted by a CBLReplicator when its status/progress changes or when
 an error occurred. */
extern NSString* const kCBLReplicatorChangeNotification;

/** The key to access a CBLReplicatorStatus object containing information about 
    the current status of the replicator. */
extern NSString* const kCBLReplicatorStatusUserInfoKey;

/** The key to access an NSError object if an error occurred. */
extern NSString* const kCBLReplicatorErrorUserInfoKey;

/** A replicator for replicating document changes between a local database and a target database.
 The replicator can be bidirectional or either push or pull. The replicator can also be one-short
 or continuous. The replicator runs asynchronously, so observe the status property to
 be notified of progress. */
@interface CBLReplicator : NSObject

/** The replicator's configuration. */
@property (readonly, copy, nonatomic) CBLReplicatorConfiguration* config;

/** The replicator's current status: its activity level and progress. Observable. */
@property (readonly, nonatomic) CBLReplicatorStatus* status;

/** Initializes a replicator with the given configuration. */
- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config;

/** Starts the replicator. This method returns immediately; the replicator runs asynchronously 
    and will report its progress throuh the replicator change notification. */
- (void) start;

/** Stops a running replicator. This method returns immediately; when the replicator actually 
    stops, the replicator will change its status's activity level to `kCBLStopped` 
    and the replicator change notification will be notified accordingly. */
- (void) stop;

@end


NS_ASSUME_NONNULL_END
