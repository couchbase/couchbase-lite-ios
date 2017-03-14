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

@implementation CBLReplication
{
    C4Replicator* _repl;
    C4ReplicatorMode _pushMode, _pullMode;
}

@synthesize database=_database, remoteURL=_remoteURL, delegate=_delegate;
@synthesize push=_push, pull=_pull, continuous=_continuous;


+ (void) initialize {
    if (self == [CBLReplication class]) {
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


static C4ReplicatorMode mkmode(BOOL active, BOOL continuous) {
    C4ReplicatorMode const kModes[4] = {kC4Disabled, kC4Disabled, kC4OneShot, kC4Continuous};
    return kModes[2*!!active + !!continuous];
}


- (void) start {
    if (_repl)
        return;
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
    if (_repl)
        [_database.activeReplications addObject: self];     // keeps me from being dealloced

    // Post an initial notification:
    auto state = _repl ? C4ReplicatorState{kC4Connecting} : C4ReplicatorState{kC4Stopped, err};
    stateChanged(_repl, state, (__bridge void*)self);
}


- (void) stop {
    if (_repl)
        c4repl_stop(_repl);
}


static void stateChanged(C4Replicator *repl,
                         C4ReplicatorState state,
                         void *context)
{
    dispatch_async(dispatch_get_main_queue(), ^{        //TODO: Support other queues
        [(__bridge CBLReplication*)context stateChanged: state];
    });
}


- (void) stateChanged: (C4ReplicatorState)state {
    id<CBLReplicationDelegate> delegate = _delegate;
    if (state.level == kC4Stopped) {
        // Stopped:
        c4repl_free(_repl);
        _repl = nullptr;
        NSError* error = nil;
        convertError(state.error, &error);
        [delegate replication: self didStopWithError: error];
        [_database.activeReplications removeObject: self];      // likely to dealloc me
    } else {
        //NOTE: CBLReplicationStatus needs to match C4ReplicatorActivityLevel!
        [delegate replication: self didChangeStatus: (CBLReplicationStatus)state.level];
    }
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
