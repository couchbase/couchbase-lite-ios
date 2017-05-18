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
#import "CBLStatus.h"

#import "c4Replicator.h"
#import "c4Socket.h"
#import "CBLWebSocket.h"
#import "FleeceCpp.hh"

using namespace fleece;
using namespace fleeceapi;

static C4LogDomain kCBLSyncLogDomain;


NSString* const kCBLReplicationStatusChangeNotification = @"CBLReplicationStatusChange";


@interface CBLReplication ()
@property (readwrite, nonatomic) CBLReplicationStatus status;
@property (readwrite, nonatomic) NSError* lastError;
@end


@implementation CBLReplication
{
    C4Replicator* _repl;
    AllocedDict _responseHeaders;   //TODO: Do something with these (for auth)
}

@synthesize database=_database, remoteURL=_remoteURL, otherDatabase=_otherDB;
@synthesize delegate=_delegate, delegateBridge=_delegateBridge, options=_options;
@synthesize push=_push, pull=_pull, continuous=_continuous, status=_status, lastError=_lastError;


+ (void) initialize {
    if (self == [CBLReplication class]) {
        kCBLSyncLogDomain = c4log_getDomain("Sync", true);
        [CBLWebSocket registerWithC4];
    }
}


- (instancetype) initWithDatabase: (CBLDatabase*)db
                        remoteURL: (NSURL*)remoteURL
                    otherDatabase: (CBLDatabase*)otherDB
{
    self = [super init];
    if (self) {
        _database = db;
        _remoteURL = remoteURL;
        _otherDB = otherDB;
        _push = _pull = YES;
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
            (_remoteURL ? _remoteURL.absoluteString : _otherDB.name)];
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
    CBLStringBytes scheme(_remoteURL.scheme);
    CBLStringBytes host(_remoteURL.host);
    CBLStringBytes path(_remoteURL.path.stringByDeletingLastPathComponent);
    CBLStringBytes dbName(_remoteURL.path.lastPathComponent);
    C4Address addr {
        .scheme = scheme,
        .hostname = host,
        .port = (uint16_t)_remoteURL.port.shortValue,
        .path = path
    };

    // Encode options:
    alloc_slice optionsFleece;
    if (_options.count) {
        Encoder enc;
        enc << _options;
        optionsFleece = enc.finish();
    }

    // Create a C4Replicator:
    C4Error err;
    _repl = c4repl_new(_database.c4db, addr, dbName, _otherDB.c4db,
                       mkmode(_push, _continuous), mkmode(_pull, _continuous),
                       {optionsFleece.buf, optionsFleece.size},
                       &statusChanged, (__bridge void*)self, &err);
    C4ReplicatorStatus status;
    if (_repl) {
        status = c4repl_getStatus(_repl);
        [_database.activeReplications addObject: self];     // keeps me from being dealloced
    } else {
        status = {kC4Stopped, {}, err};
    }
    [self setC4Status: status];

    // Post an initial notification:
    statusChanged(_repl, status, (__bridge void*)self);
}


- (void) stop {
    if (_repl)
        c4repl_stop(_repl);
}


static void statusChanged(C4Replicator *repl, C4ReplicatorStatus status, void *context) {
    dispatch_async(dispatch_get_main_queue(), ^{        //TODO: Support other queues
        [(__bridge CBLReplication*)context c4StatusChanged: status];
    });
}


- (void) c4StatusChanged: (C4ReplicatorStatus)status {
    [self setC4Status: status];

    id<CBLReplicationDelegate> delegate = _delegate;
    if ([delegate respondsToSelector: @selector(replication:didChangeStatus:)])
        [delegate replication: self didChangeStatus: _status];
    [NSNotificationCenter.defaultCenter
                    postNotificationName: kCBLReplicationStatusChangeNotification object: self];

    if (!_responseHeaders) {
        C4Slice h = c4repl_getResponseHeaders(_repl);
        _responseHeaders = AllocedDict(slice{h.buf, h.size});
    }

    if (status.level == kC4Stopped) {
        // Stopped:
        c4repl_free(_repl);
        _repl = nullptr;
        if ([delegate respondsToSelector: @selector(replication:didStopWithError:)])
            [delegate replication: self didStopWithError: _lastError];
        [_database.activeReplications removeObject: self];      // this is likely to dealloc me
    }
}


- (void) setC4Status: (C4ReplicatorStatus)state {
    NSError *error = nil;
    if (state.error.code)
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

- (CBLReplication*) replicationWithURL: (NSURL*)remoteURL {
    NSParameterAssert(remoteURL);
    CBLReplication* repl = [self.replications objectForKey: remoteURL];
    if (!repl) {
        repl = [[CBLReplication alloc] initWithDatabase: self
                                              remoteURL: remoteURL otherDatabase: nil];
        [self.replications setObject: repl forKey: remoteURL];
    }
    return repl;
}

- (CBLReplication*) replicationWithDatabase: (CBLDatabase*)otherDatabase {
    NSParameterAssert(otherDatabase);
    NSParameterAssert(otherDatabase != self);
    id key = otherDatabase.path;
    CBLReplication* repl = [self.replications objectForKey: key];
    if (!repl) {
        repl = [[CBLReplication alloc] initWithDatabase: self
                                              remoteURL: nil otherDatabase: otherDatabase];
        [self.replications setObject: repl forKey: key];
    }
    return repl;
}

@end
