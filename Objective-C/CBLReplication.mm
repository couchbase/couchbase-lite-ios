//
//  CBLReplication.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplication+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLInternal.h"
#import <CouchbaseLiteReplicator/CouchbaseLiteReplicator.h>


static C4LogDomain kCBLSyncLogDomain;

@interface CBLReplication ()
@property (readwrite, nonatomic) CBLReplicationStatus status;
@property (readwrite, nonatomic) NSError* lastError;
@end


@implementation CBLReplication
{
    C4Replicator* _repl;
    C4ReplicatorMode _pushMode, _pullMode;
}

@synthesize database=_database, remoteURL=_remoteURL, delegate=_delegate;
@synthesize push=_push, pull=_pull, continuous=_continuous, status=_status, lastError=_lastError;


+ (void) initialize {
    if (self == [CBLReplication class]) {
        kCBLSyncLogDomain = c4log_getDomain("Sync", true);
        [CBLWebSocket registerWithC4];
    }
}


- (instancetype) initWithDatabase: (CBLDatabase*)db
                              URL: (NSURL*)remote
{
    self = [super init];
    if (self) {
        _database = db;
        _remoteURL = remote;
    }
    return self;
}


- (void) dealloc {
    c4repl_free(_repl);
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%s%s%s %@]",
            self.class,
            (_pull ? "<" : ""),
            (_continuous ? "*" : "-"),
            (_push ? ">" : ""),
            _remoteURL.absoluteString];
}



static C4ReplicatorMode mkmode(BOOL active, BOOL continuous) {
    C4ReplicatorMode const kModes[4] = {kC4Disabled, kC4Disabled, kC4OneShot, kC4Continuous};
    return kModes[2*!!active + !!continuous];
}


- (void) start {
    if (_repl) {
        CBLWarn(Sync, @"%@ has already started", self);
        return;
    }
    NSAssert(_push || _pull, @"Replication must either push or pull, or both");
    CBLStringBytes host(_remoteURL.host);
    CBLStringBytes path(_remoteURL.path.stringByDeletingLastPathComponent);
    CBLStringBytes dbName(_remoteURL.path.lastPathComponent);
    C4Address addr {
        .scheme = kC4Replicator2Scheme,
        .hostname = host,
        .port = (uint16_t)_remoteURL.port.shortValue,
        .path = path
    };
    C4Error err;
    _repl = c4repl_new(_database.c4db, addr, dbName,
                       mkmode(_push, _continuous), mkmode(_pull, _continuous),
                       &stateChanged, (__bridge void*)self, &err);
    C4ReplicatorStatus status;
    if (_repl) {
        status = c4repl_getStatus(_repl);
        [_database.activeReplications addObject: self];     // keeps me from being dealloced
    } else {
        status = {kC4Stopped, {}, err};
    }
    [self setC4State: status];

    // Post an initial notification:
    stateChanged(_repl, status, (__bridge void*)self);
}


- (void) stop {
    if (_repl)
        c4repl_stop(_repl);
}


static void stateChanged(C4Replicator *repl, C4ReplicatorStatus status, void *context) {
    dispatch_async(dispatch_get_main_queue(), ^{        //TODO: Support other queues
        [(__bridge CBLReplication*)context c4StatusChanged: status];
    });
}


- (void) c4StatusChanged: (C4ReplicatorStatus)state {
    [self setC4State: state];
    id<CBLReplicationDelegate> delegate = _delegate;

    if ([delegate respondsToSelector: @selector(replication:didChangeStatus:)])
        [delegate replication: self didChangeStatus: _status];

    if (state.level == kC4Stopped) {
        // Stopped:
        c4repl_free(_repl);
        _repl = nullptr;
        if ([delegate respondsToSelector: @selector(replication:didStopWithError:)])
            [delegate replication: self didStopWithError: _lastError];
        [_database.activeReplications removeObject: self];      // this is likely to dealloc me
    }
}


- (void) setC4State: (C4ReplicatorStatus)state {
    NSError *error = nil;;
    convertError(state.error, &error);
    if (error != _lastError)
        self.lastError = error;

    //NOTE: CBLReplicationStatus values needs to match C4ReplicatorActivityLevel!
    auto status = _status;
    status.activity = (CBLReplicationActivityLevel)state.level;
    status.progress = {state.progress.completed, state.progress.total};
    self.status = status;
    CBLLog(Sync, @"%@ is %s, progress %llu/%llu",
           self, kC4ReplicatorActivityLevelNames[state.level],
           state.progress.completed, state.progress.total);
}


@end


#pragma mark - CBLDATABASE CATEGORY


@implementation CBLDatabase (Replication)

- (CBLReplication*) replicationWithDatabase: (NSURL*)remote {
    CBLReplication* repl = [self.replications objectForKey: remote];
    if (!repl) {
        repl = [[CBLReplication alloc] initWithDatabase: self URL: remote];
        [self.replications setObject: repl forKey: remote];
    }
    return repl;
}

@end
