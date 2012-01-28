//
//  TDReplicator.h
//  TouchDB
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TDDatabase, TDRevisionList, TDBatcher;


/** Posted when changesProcessed or changesTotal changes. */
extern NSString* TDReplicatorProgressChangedNotification;

/** Posted when replicator stops running. */
extern NSString* TDReplicatorStoppedNotification;


/** Abstract base class for push or pull replications. */
@interface TDReplicator : NSObject
{
    @protected
    TDDatabase* _db;
    NSURL* _remote;
    BOOL _continuous;
    NSString* _lastSequence;
    BOOL _lastSequenceChanged;
    NSDictionary* _remoteCheckpoint;
    BOOL _running, _active;
    NSError* _error;
    NSString* _sessionID;
    TDBatcher* _batcher;
    int _asyncTaskCount;
    NSUInteger _changesProcessed, _changesTotal;
}

- (id) initWithDB: (TDDatabase*)db
           remote: (NSURL*)remote
             push: (BOOL)push
       continuous: (BOOL)continuous;

@property (readonly) TDDatabase* db;
@property (readonly) NSURL* remote;
@property (readonly) BOOL isPush;

/** Starts the replicator.
    Replicators run asynchronously so nothing will happen until later.
    A replicator can only be started once; don't reuse it after it stops. */
- (void) start;

/** Request to stop the replicator.
    Any pending asynchronous operations will be finished first.
    TDReplicatorStoppedNotification will be posted when it finally stops. */
- (void) stop;

/** Is the replicator active? (Observable) */
@property (readonly) BOOL running;

/** Is the replicator actively sending/receiving revisions? (Observable) */
@property (readonly) BOOL active;

/** Latest error encountered while replicating.
    This is set to nil when starting. It may also be set to nil by the client if desired.
    Not all errors are fatal; if .running is still true, the replicator will retry. */
@property (retain) NSError* error;

/** A unique-per-process string identifying this replicator instance. */
@property (readonly) NSString* sessionID;

/** Number of changes (docs or other metadata) transferred so far. */
@property (readonly, nonatomic) NSUInteger changesProcessed;

/** Approximate total number of changes to transfer.
    This is only an estimate and its value will change during replication. It starts at zero and returns to zero when replication stops. */
@property (readonly, nonatomic) NSUInteger changesTotal;

@end


