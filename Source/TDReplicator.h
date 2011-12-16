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


/** Abstract base class for push or pull replications. */
@interface TDReplicator : NSObject
{
    @protected
    TDDatabase* _db;
    NSURL* _remote;
    BOOL _continuous;
    NSString* _lastSequence;
    BOOL _running, _active;
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

- (void) start;
- (void) stop;

/** Has the replicator been started? (Observable) */
@property (readonly) BOOL running;

/** Is the replicator actively sending/receiving revisions? (Observable) */
@property (readonly) BOOL active;

@property (readonly) NSString* sessionID;
@property (readonly, nonatomic) NSUInteger changesProcessed;
@property (readonly, nonatomic) NSUInteger changesTotal;
@end


