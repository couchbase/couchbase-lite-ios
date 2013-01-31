//
//  CBL_Replicator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CBL_Database, CBL_RevisionList, CBLBatcher, CBLReachability;
@protocol CBLAuthorizer;


/** Posted when changesProcessed or changesTotal changes. */
extern NSString* CBL_ReplicatorProgressChangedNotification;

/** Posted when replicator stops running. */
extern NSString* CBL_ReplicatorStoppedNotification;


/** Abstract base class for push or pull replications. */
@interface CBL_Replicator : NSObject
{
    @protected
    CBL_Database* __weak _db;
    NSThread* _thread;
    NSURL* _remote;
    BOOL _continuous;
    NSString* _filterName;
    NSDictionary* _filterParameters;
    NSString* _lastSequence;
    BOOL _lastSequenceChanged;
    NSDictionary* _remoteCheckpoint;
    BOOL _savingCheckpoint, _overdueForSave;
    BOOL _running, _online, _active;
    unsigned _revisionsFailed;
    NSError* _error;
    NSString* _sessionID;
    NSString* _documentID;
    CBLBatcher* _batcher;
    NSMutableArray* _remoteRequests;
    int _asyncTaskCount;
    NSUInteger _changesProcessed, _changesTotal;
    CFAbsoluteTime _startTime;
    id<CBLAuthorizer> _authorizer;
    NSDictionary* _options;
    NSDictionary* _requestHeaders;
    @private
    CBLReachability* _host;
}

+ (NSString *)progressChangedNotification;
+ (NSString *)stoppedNotification;

- (id) initWithDB: (CBL_Database*)db
           remote: (NSURL*)remote
             push: (BOOL)push
       continuous: (BOOL)continuous;

@property (weak, readonly) CBL_Database* db;
@property (readonly) NSURL* remote;
@property (readonly) BOOL isPush;
@property (readonly) BOOL continuous;
@property (copy) NSString* filterName;
@property (copy) NSDictionary* filterParameters;
@property (copy) NSDictionary* options;

/** Optional dictionary of headers to be added to all requests to remote servers. */
@property (copy) NSDictionary* requestHeaders;

@property (strong) id<CBLAuthorizer> authorizer;

/** Do these two replicators have identical settings? */
- (bool) hasSameSettingsAs: (CBL_Replicator*)other;

/** Starts the replicator.
    Replicators run asynchronously so nothing will happen until later.
    A replicator can only be started once; don't reuse it after it stops. */
- (void) start;

/** Request to stop the replicator.
    Any pending asynchronous operations will be canceled.
    CBL_ReplicatorStoppedNotification will be posted when it finally stops. */
- (void) stop;

/** Is the replicator running? (Observable) */
@property (readonly, nonatomic) BOOL running;

/** Is the replicator able to connect to the remote host? */
@property (readonly, nonatomic) BOOL online;

/** Is the replicator actively sending/receiving revisions? (Observable) */
@property (readonly, nonatomic) BOOL active;

/** Latest error encountered while replicating.
    This is set to nil when starting. It may also be set to nil by the client if desired.
    Not all errors are fatal; if .running is still true, the replicator will retry. */
@property (strong, nonatomic) NSError* error;

/** A unique-per-process string identifying this replicator instance. */
@property (copy, nonatomic) NSString* sessionID;

/** Document ID of the persistent replication this is associated with. */
@property (copy, nonatomic) NSString* documentID;

/** Number of changes (docs or other metadata) transferred so far. */
@property (readonly, nonatomic) NSUInteger changesProcessed;

/** Approximate total number of changes to transfer.
    This is only an estimate and its value will change during replication. It starts at zero and returns to zero when replication stops. */
@property (readonly, nonatomic) NSUInteger changesTotal;

/** JSON-compatible array of status info about active remote HTTP requests. */
@property (readonly) NSArray* activeRequestsStatus;

@end
