//
//  CBLReplicator.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <Foundation/Foundation.h>
@class CBLDatabase;
@class CBLDocumentReplication;
@class CBLReplicatorChange;
@class CBLReplicatorConfiguration;
@protocol CBLListenerToken;

NS_ASSUME_NONNULL_BEGIN


/** Activity level of a replicator. */
typedef enum {
    kCBLReplicatorStopped,    ///< The replicator is finished or hit a fatal error.
    kCBLReplicatorOffline,    ///< The replicator is offline as the remote host is unreachable.
    kCBLReplicatorConnecting, ///< The replicator is connecting to the remote host.
    kCBLReplicatorIdle,       ///< The replicator is inactive waiting for changes or offline.
    kCBLReplicatorBusy        ///< The replicator is actively transferring data.
} CBLReplicatorActivityLevel;


/** 
 Progress of a replicator. If `total` is zero, the progress is indeterminate; otherwise,
 dividing the two will produce a fraction that can be used to draw a progress bar.
 */
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

/** The current error of the replicator. */
@property (readonly, nonatomic, nullable) NSError* error;

@end


/** 
 A replicator for replicating document changes between a local database and a target database.
 The replicator can be bidirectional or either push or pull. The replicator can also be one-short
 or continuous. The replicator runs asynchronously, so observe the status property to
 be notified of progress.
 */
@interface CBLReplicator : NSObject

/**
 The replicator's configuration. The returned configuration object is readonly;
 an NSInternalInconsistencyException exception will be thrown if
 the configuration object is modified.
 */
@property (readonly, nonatomic) CBLReplicatorConfiguration* config;

/** The replicator's current status: its activity level and progress. Observable. */
@property (readonly, atomic) CBLReplicatorStatus* status;

/** The SSL/TLS certificate received when connecting to the server. The application code takes responsibility
    for releasing the certificate object when the application code finishes using the certificate. */
@property (readonly, copy, atomic, nullable) __attribute__((NSObject)) SecCertificateRef serverCertificate;

/** Initializes a replicator with the given configuration. */
- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

/** 
 Starts the replicator. This method returns immediately; the replicator runs asynchronously
 and will report its progress through the replicator change notification.
 */
- (void) start;

/**
Starts the replicator with an option to reset the local checkpoint of the replicator. When the local checkpoint
is reset, the replicator will sync all changes since the beginning of time from the remote database.
This method returns immediately; the replicator runs asynchronously and will report its progress through
the replicator change notification.
 
 @param reset Resets the local checkpoint before starting the replicator.
*/
- (void) startWithReset: (BOOL)reset;

/** 
 Stops a running replicator. This method returns immediately; when the replicator actually
 stops, the replicator will change its status's activity level to `kCBLStopped`
 and the replicator change notification will be notified accordingly.
 */
- (void) stop;

/** 
 Adds a replicator change listener. Changes will be posted on the main queue.
 
 @param listener The listener to post the changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLReplicatorChange*))listener;

/**
 Adds a replicator change listener with the dispatch queue on which changes
 will be posted. If the dispatch queue is not specified, the changes will be
 posted on the main queue.
 
 @param queue The dispatch queue.
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLReplicatorChange*))listener;

/**
 Adds a replication event listener. The replication event will be posted on the main queue.
 
 According to performance optimization in the replicator, the document replication listeners need to be added
 before starting the replicator. If the listeners are added after the replicator is started, the replicator needs to be
 stopped and restarted again to ensure that the listeners will get the document replication events.
 
 @param listener The listener to post replication events.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addDocumentReplicationListener: (void (^)(CBLDocumentReplication*))listener;

/**
 Adds a replication event listener with the dispatch queue on which replication events
 will be posted. If the dispatch queue is not specified, the replication events will be
 posted on the main queue.
 
 According to performance optimization in the replicator, the document replication listeners need to be added
 before starting the replicator. If the listeners are added after the replicator is started, the replicator needs to be
 stopped and restarted again to ensure that the listeners will get the document replication events.
 
 @param queue The dispatch queue.
 @param listener The listener to post replication events.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addDocumentReplicationListenerWithQueue: (nullable dispatch_queue_t)queue
                                                        listener: (void (^)(CBLDocumentReplication*))listener;

/** 
 Removes a change listener with the given listener token.
 
 @param token The listener token;
 */
- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token;

/**
 Gets a set of document Ids, who have revisions pending push. This API is a snapshot and results may
 change between the time the call was made and the time the call returns.
 
 @param error error On return, the error if any.
 @return A  set of document Ids, each of which has one or more pending revisions. If error, nil.
 */
- (nullable NSSet<NSString*>*) pendingDocumentIDs: (NSError**)error;

/**
 Checks if the document with the given ID has revisions pending push.  This API is a snapshot and results may
 change between the time the call was made and the time the call returns.
 @param documentID The ID of the document to check
 @param error error On return, the error if any.
 @return true if the document has one or more revisions pending, false otherwise
 
 */
- (BOOL) isDocumentPending: (NSString*)documentID error: (NSError**)error NS_SWIFT_NOTHROW;

@end


NS_ASSUME_NONNULL_END
