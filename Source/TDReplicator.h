//
//  TDReplicator.h
//  TouchDB
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TDDatabase, TDRevisionList, TDBatcher, TDReachability;
@protocol TDAuthorizer;


/** Posted when changesProcessed or changesTotal changes. */
extern NSString* TDReplicatorProgressChangedNotification;

/** Posted when replicator stops running. */
extern NSString* TDReplicatorStoppedNotification;


/** Abstract base class for push or pull replications. */
@interface TDReplicator : NSObject
{
    @protected
    NSThread* _thread;
    TDDatabase* _db;
    NSURL* _remote;
    TDReachability* _host;
    BOOL _continuous;
    NSString* _filterName;
    NSDictionary* _filterParameters;
    NSString* _lastSequence;
    BOOL _lastSequenceChanged;
    NSDictionary* _remoteCheckpoint;
    BOOL _savingCheckpoint, _overdueForSave;
    BOOL _running, _online, _active;
    NSError* _error;
    NSString* _sessionID;
    TDBatcher* _batcher;
    int _asyncTaskCount;
    NSUInteger _changesProcessed, _changesTotal;
    CFAbsoluteTime _startTime;
    id<TDAuthorizer> _authorizer;
    NSDictionary* _options;
    NSDictionary* _requestHeaders;
}

+ (NSString *)progressChangedNotification;
+ (NSString *)stoppedNotification;

- (id) initWithDB: (TDDatabase*)db
           remote: (NSURL*)remote
             push: (BOOL)push
       continuous: (BOOL)continuous;

@property (readonly) TDDatabase* db;
@property (readonly) NSURL* remote;
@property (readonly) BOOL isPush;
@property (readonly) BOOL continuous;
@property (copy) NSString* filterName;
@property (copy) NSDictionary* filterParameters;
@property (copy) NSDictionary* options;

/** Optional dictionary of headers to be added to all requests to remote servers. */
@property (copy) NSDictionary* requestHeaders;

@property (retain) id<TDAuthorizer> authorizer;

/** Starts the replicator.
    Replicators run asynchronously so nothing will happen until later.
    A replicator can only be started once; don't reuse it after it stops. */
- (void) start;

/** Request to stop the replicator.
    Any pending asynchronous operations will be finished first.
    TDReplicatorStoppedNotification will be posted when it finally stops. */
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
@property (retain, nonatomic) NSError* error;

/** A unique-per-process string identifying this replicator instance. */
@property (copy, nonatomic) NSString* sessionID;

/** Number of changes (docs or other metadata) transferred so far. */
@property (readonly, nonatomic) NSUInteger changesProcessed;

/** Approximate total number of changes to transfer.
    This is only an estimate and its value will change during replication. It starts at zero and returns to zero when replication stops. */
@property (readonly, nonatomic) NSUInteger changesTotal;

@end
