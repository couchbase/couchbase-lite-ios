//
//  CBLReplication.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplication+Internal.h"
#import "CBLReachability.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLInternal.h"
#import "CBLStatus.h"

#import "c4Replicator.h"
#import "c4Socket.h"
#import "CBLWebSocket.h"
#import "FleeceCpp.hh"
#import <algorithm>

using namespace std;
using namespace fleece;
using namespace fleeceapi;


// Maximum number of retries before a one-shot replication gives up
static constexpr unsigned kMaxOneShotRetryCount = 2;

// Longest possible retry delay (only a continuous replication will reach this)
// But a change in reachability will also trigger a retry.
static constexpr NSTimeInterval kMaxRetryDelay = 10 * 60;

// The function governing the exponential backoff of retries
static NSTimeInterval retryDelay(unsigned retryCount) {
    NSTimeInterval delay = 1 << min(retryCount, 30u);
    return min(delay, kMaxRetryDelay);
}


C4LogDomain kCBLSyncLogDomain;


NSString* const kCBLReplicationStatusChangeNotification = @"CBLReplicationStatusChange";

NSString* const kCBLReplicationAuthOption           = @"" kC4ReplicatorOptionAuthentication;
NSString* const kCBLReplicationAuthType             = @"" kC4ReplicatorAuthType;
NSString* const kCBLReplicationAuthUserName         = @"" kC4ReplicatorAuthUserName;
NSString* const kCBLReplicationAuthPassword         = @"" kC4ReplicatorAuthPassword;


@interface CBLReplication ()
@property (readwrite, nonatomic) CBLReplicationStatus status;
@property (readwrite, nonatomic) NSError* lastError;
@end


@implementation CBLReplication
{
    dispatch_queue_t _dispatchQueue;
    C4Replicator* _repl;
    NSString* _desc;
    AllocedDict _responseHeaders;   //TODO: Do something with these (for auth)
    unsigned _retryCount;
    CBLReachability* _reachability;
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
        _dispatchQueue = dispatch_get_main_queue();
    }
    return self;
}


- (void) dealloc {
    c4repl_free(_repl);
    [_reachability stop];
}


- (NSString*) description {
    if (_desc)
        return _desc;
    return [NSString stringWithFormat: @"%@[%s%s%s %@]",
            self.class,
            (_pull ? "<" : ""),
            (_continuous ? "*" : "-"),
            (_push ? ">" : ""),
            (_remoteURL ? _remoteURL.absoluteString : _otherDB.name)];
}


- (void) clearRepl {
    c4repl_free(_repl);
    _repl = nullptr;
    _desc = nil;
}


- (void) start {
    if (_repl) {
        CBLWarn(Sync, @"%@ has already started", self);
        return;
    }
    CBLLog(Sync, @"%@: Starting", self);
    _retryCount = 0;
    [self _start];
}


- (void) retry {
    if (_repl || _status.activity != kCBLOffline)
        return;
    CBLLog(Sync, @"%@: Retrying...", self);
    [self _start];
}


- (void) _start {
    _desc = self.description;   // cache description; it may be called a lot when logging
    NSAssert(_push || _pull, @"Replication must either push or pull, or both");
    // Fill out the C4Address:
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

    // If the URL has a hardcoded username/password, add them as an "auth" option:
    NSMutableDictionary* options = _options.mutableCopy;
    NSString* username = _remoteURL.user;
    if (username && !options[kCBLReplicationAuthOption]) {
        NSMutableDictionary *auth = [NSMutableDictionary new];
        auth[kCBLReplicationAuthUserName] = username;
        auth[kCBLReplicationAuthPassword] = _remoteURL.password;
        if (!options)
            options = [NSMutableDictionary new];
        options[kCBLReplicationAuthOption] = auth;
    }

    // Encode the options:
    alloc_slice optionsFleece;
    if (options.count) {
        Encoder enc;
        enc << options;
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
    [self updateStateProperties: status];

    // Post an initial notification:
    statusChanged(_repl, status, (__bridge void*)self);
}


static C4ReplicatorMode mkmode(BOOL active, BOOL continuous) {
    C4ReplicatorMode const kModes[4] = {kC4Disabled, kC4Disabled, kC4OneShot, kC4Continuous};
    return kModes[2*!!active + !!continuous];
}


- (void) stop {
    if (_repl)
        c4repl_stop(_repl);     // this is async; status will change when repl actually stops
    [_reachability stop];
    _reachability = nil;
}


- (void) startReachabilityObserver {
    if (_reachability)
        return;
    NSString *hostname = _remoteURL.host;
    if ([hostname isEqualToString: @"localhost"] || [hostname isEqualToString: @"127.0.0.1"])
        return;
    _reachability = [[CBLReachability alloc] initWithURL: _remoteURL];
    __weak auto weakSelf = self;
    _reachability.onChange = ^{ [weakSelf reachabilityChanged]; };
    [_reachability startOnQueue: _dispatchQueue];
}

- (void) reachabilityChanged {
    bool reachable = _reachability.reachable;
    if (reachable && !_repl) {
        CBLLog(Sync, @"%@: Server may now be reachable; retrying...", self);
        _retryCount = 0;
        [self retry];
    }
}


static void statusChanged(C4Replicator *repl, C4ReplicatorStatus status, void *context) {
    auto replication = (__bridge CBLReplication*)context;
    dispatch_async(replication->_dispatchQueue, ^{
        if (repl == replication->_repl)
            [replication c4StatusChanged: status];
    });
}


- (void) c4StatusChanged: (C4ReplicatorStatus)c4Status {
    if (!_responseHeaders && _repl) {
        C4Slice h = c4repl_getResponseHeaders(_repl);
        _responseHeaders = AllocedDict(slice{h.buf, h.size});
    }

    if (c4Status.level == kC4Stopped) {
        if ([self handleError: c4Status.error]) {
            // Change c4Status to offline, so my state will reflect that, and proceed:
            c4Status.level = kC4Offline;
        }
    } else if (c4Status.level > kC4Connecting) {
        _retryCount = 0;
        [_reachability stop];
        _reachability = nil;
    }

    // Update my properties:
    [self updateStateProperties: c4Status];

    // Notify the delegate and post a NSNotification:
    id<CBLReplicationDelegate> delegate = _delegate;
    if ([delegate respondsToSelector: @selector(replication:didChangeStatus:)])
        [delegate replication: self didChangeStatus: _status];
    [NSNotificationCenter.defaultCenter
                    postNotificationName: kCBLReplicationStatusChangeNotification object: self];

    if (c4Status.level == kC4Stopped) {
        // Stopped:
        [self clearRepl];
        if ([delegate respondsToSelector: @selector(replication:didStopWithError:)])
            [delegate replication: self didStopWithError: _lastError];
        [_database.activeReplications removeObject: self];      // this is likely to dealloc me
    }
}


- (bool) handleError: (C4Error)c4err {
    // If this is a transient error, or if I'm continuous and the error might go away with a change
    // in network (i.e. network down, hostname unknown), then go offline and retry later.
    bool transient = c4error_mayBeTransient(c4err);
    if (!transient && !(_continuous && c4error_mayBeNetworkDependent(c4err)))
        return false;   // nope, this is permanent
    if (!_continuous && _retryCount >= kMaxOneShotRetryCount)
        return false;   // too many retries

    [self clearRepl];
    NSError *error = nil;
    convertError(c4err, &error);
    if (transient) {
        // On transient error, retry periodically, with exponential backoff:
        auto delay = retryDelay(++_retryCount);
        CBLLog(Sync, @"%@: Transient error (%@); will retry in %.0f sec...",
               self, error.localizedDescription, delay);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       _dispatchQueue, ^{
                           [self retry];
                       });
    } else {
        CBLLog(Sync, @"%@: Network error (%@); will retry when network changes...",
               self, error.localizedDescription);
    }
    // Also retry when the network changes:
    [self startReachabilityObserver];
    return true;
}


- (void) updateStateProperties: (C4ReplicatorStatus)c4Status {
    NSError *error = nil;
    if (c4Status.error.code)
        convertError(c4Status.error, &error);
    if (error != _lastError)
        self.lastError = error;

    //NOTE: CBLReplicationStatus values needs to match C4ReplicatorActivityLevel!
    auto status = _status;
    status.activity = (CBLReplicationActivityLevel)c4Status.level;
    status.progress = {c4Status.progress.completed, c4Status.progress.total};
    self.status = status;
    CBLLog(Sync, @"%@ is %s, progress %llu/%llu",
           self, kC4ReplicatorActivityLevelNames[c4Status.level],
           c4Status.progress.completed, c4Status.progress.total);
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
