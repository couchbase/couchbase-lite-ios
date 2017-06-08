//
//  CBLReplicator.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplicator+Internal.h"
#import "CBLReplicatorConfiguration.h"
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


NSString* const kCBLReplicatorChangeNotification = @"kCBLReplicatorChangeNotification";
NSString* const kCBLReplicatorStatusUserInfoKey = @"kCBLReplicatorStatusUserInfoKey";
NSString* const kCBLReplicatorErrorUserInfoKey = @"kCBLReplicatorErrorUserInfoKey";


@interface CBLReplicatorStatus ()
- (instancetype) initWithActivity: (CBLReplicatorActivityLevel)activity
                         progress: (CBLReplicatorProgress)progress;
@end


@interface CBLReplicator ()
@property (readwrite, nonatomic) CBLReplicatorStatus* status;
@property (readwrite, nonatomic) NSError* lastError;
@end


@implementation CBLReplicator
{
    dispatch_queue_t _dispatchQueue;
    C4Replicator* _repl;
    NSString* _desc;
    AllocedDict _responseHeaders;   //TODO: Do something with these (for auth)
    C4ReplicatorStatus _rawStatus;
    unsigned _retryCount;
    CBLReachability* _reachability;
}

@synthesize config=_config;
@synthesize status=_status, lastError=_lastError;


+ (void) initialize {
    if (self == [CBLReplicator class]) {
        kCBLSyncLogDomain = c4log_getDomain("Sync", true);
        [CBLWebSocket registerWithC4];
    }
}


- (instancetype) initWithConfig: (CBLReplicatorConfiguration *)config {
    self = [super init];
    if (self) {
        NSParameterAssert(config.database != nil && config.target != nil);
        _config = [config copy];
        _dispatchQueue = dispatch_get_main_queue();
    }
    return self;
}


- (CBLReplicatorConfiguration*) config {
    return [_config copy];
}


- (void) dealloc {
    c4repl_free(_repl);
    [_reachability stop];
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%s%s%s %@]",
            self.class,
            (isPull(_config.replicatorType) ? "<" : ""),
            (_config.continuous ? "*" : "-"),
            (isPush(_config.replicatorType)  ? ">" : ""),
            _config.target];
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
    if (_repl || _rawStatus.level != kC4Offline)
        return;
    CBLLog(Sync, @"%@: Retrying...", self);
    [self _start];
}


- (void) _start {
    Assert(_config.database);
    Assert(_config.target);
    
    _desc = self.description;   // cache description; it may be called a lot when logging
    
    // Target:
    C4Address addr;
    CBLDatabase* otherDB;
    NSURL* remoteURL = _config.target.url;
    CBLStringBytes dbName(remoteURL.path.lastPathComponent);
    CBLStringBytes scheme(remoteURL.scheme);
    CBLStringBytes host(remoteURL.host);
    CBLStringBytes path(remoteURL.path.stringByDeletingLastPathComponent);
    if (remoteURL) {
        // Fill out the C4Address:
        addr = {
            .scheme = scheme,
            .hostname = host,
            .port = (uint16_t)remoteURL.port.shortValue,
            .path = path
        };
    } else {
        otherDB = _config.target.database;
        Assert(otherDB);
    }

    // Encode the options:
    alloc_slice optionsFleece;
    NSDictionary* options = _config.effectiveOptions;
    if (options.count) {
        Encoder enc;
        enc << options;
        optionsFleece = enc.finish();
    }
    
    // Push / Pull / Continuous:
    BOOL push = isPush(_config.replicatorType);
    BOOL pull = isPull(_config.replicatorType);
    BOOL continuous = _config.continuous;

    // Create a C4Replicator:
    C4Error err;
    _repl = c4repl_new(_config.database.c4db, addr, dbName, otherDB.c4db,
                       mkmode(push, continuous), mkmode(pull, continuous),
                       {optionsFleece.buf, optionsFleece.size},
                       &statusChanged, (__bridge void*)self, &err);
    C4ReplicatorStatus status;
    if (_repl) {
        status = c4repl_getStatus(_repl);
        [_config.database.activeReplications addObject: self];     // keeps me from being dealloced
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


static BOOL isPush(CBLReplicatorType type) {
    return type == kCBLPushAndPull || type == kCBLPush;
}


static BOOL isPull(CBLReplicatorType type) {
    return type == kCBLPushAndPull || type == kCBLPull;
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
    NSURL *remoteURL = _config.target.url;
    NSString *hostname = remoteURL.host;
    if ([hostname isEqualToString: @"localhost"] || [hostname isEqualToString: @"127.0.0.1"])
        return;
    _reachability = [[CBLReachability alloc] initWithURL: remoteURL];
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
    auto replicator = (__bridge CBLReplicator*)context;
    dispatch_async(replicator->_dispatchQueue, ^{
        if (repl == replicator->_repl)
            [replicator c4StatusChanged: status];
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

    // Post a NSNotification:
    NSMutableDictionary* userinfo = [NSMutableDictionary new];
    userinfo[kCBLReplicatorStatusUserInfoKey] = self.status;
    userinfo[kCBLReplicatorErrorUserInfoKey] = self.lastError;
    [NSNotificationCenter.defaultCenter postNotificationName: kCBLReplicatorChangeNotification
                                                      object: self userInfo: userinfo];
    
    // If Stopped:
    if (c4Status.level == kC4Stopped) {
        // Stopped:
        [self clearRepl];
        [_config.database.activeReplications removeObject: self];      // this is likely to dealloc me
    }
}


- (bool) handleError: (C4Error)c4err {
    // If this is a transient error, or if I'm continuous and the error might go away with a change
    // in network (i.e. network down, hostname unknown), then go offline and retry later.
    bool transient = c4error_mayBeTransient(c4err);
    if (!transient && !(_config.continuous && c4error_mayBeNetworkDependent(c4err)))
        return false;   // nope, this is permanent
    if (!_config.continuous && _retryCount >= kMaxOneShotRetryCount)
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

    _rawStatus = c4Status;
    
    CBLReplicatorActivityLevel level;
    switch (c4Status.level) {
        case kC4Stopped:
            level = kCBLStopped;
            break;
        case kC4Idle:
        case kC4Offline:
            level = kCBLIdle;
            break;
        default:
            level = kCBLBusy;
            break;
    }
    CBLReplicatorProgress progress = { c4Status.progress.completed, c4Status.progress.total };
    self.status = [[CBLReplicatorStatus alloc] initWithActivity: level progress: progress];
    
    CBLLog(Sync, @"%@ is %s, progress %llu/%llu, error: %@",
           self, kC4ReplicatorActivityLevelNames[c4Status.level],
           c4Status.progress.completed, c4Status.progress.total, error);
}


@end


#pragma mark - CBLReplicatorStatus


@implementation CBLReplicatorStatus

@synthesize activity=_activity, progress=_progress;

- (instancetype) initWithActivity: (CBLReplicatorActivityLevel)activity
                         progress: (CBLReplicatorProgress)progress
{
    self = [super init];
    if (self) {
        _activity = activity;
        _progress = progress;
    }
    return self;
}

@end

