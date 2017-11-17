//
//  CBLReplicator.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplicator+Backgrounding.h"
#import "CBLReplicator+Internal.h"
#import "CBLReplicatorChange+Internal.h"
#import "CBLReplicatorConfiguration.h"

#import "CBLChangeListener.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLReachability.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"

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


@interface CBLReplicatorStatus ()
- (instancetype) initWithActivity: (CBLReplicatorActivityLevel)activity
                         progress: (CBLReplicatorProgress)progress
                            error: (NSError*)error;
@end


@implementation CBLReplicator
{
    C4Replicator* _repl;
    NSString* _desc;
    C4ReplicatorStatus _rawStatus;
    unsigned _retryCount;
    CBLReachability* _reachability;
    NSMutableSet* _changeListeners;
    BOOL _isStopping;
    BOOL _isSuspending;
}

@synthesize dispatchQueue=_dispatchQueue;
@synthesize config=_config;
@synthesize status=_status;
@synthesize bgMonitor=_bgMonitor;
@synthesize suspended=_suspended;


+ (void) initialize {
    if (self == [CBLReplicator class]) {
        kCBL_LogDomainSync = c4log_getDomain("Sync", true);
        [CBLWebSocket registerWithC4];
    }
}


- (instancetype) initWithConfig: (CBLReplicatorConfiguration *)config {
    self = [super init];
    if (self) {
        NSParameterAssert(config.database != nil && config.target != nil);
        _config = [config copy];
        _dispatchQueue = dispatch_queue_create("CBLReplicator", DISPATCH_QUEUE_SERIAL);
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
    dispatch_async(_dispatchQueue, ^{
        if (_repl) {
            CBLWarn(Sync, @"%@ has already started", self);
            return;
        }
        
        CBLLog(Sync, @"%@: Starting", self);
        _retryCount = 0;
        _suspended = NO;
        [self _start];
    });
}


- (void) retry {
    if (_repl || _rawStatus.level != kC4Offline)
        return;
    
    CBLLog(Sync, @"%@: Retrying...", self);
    [self _start];
}


- (void) _start {
    _desc = self.description;   // cache description; it may be called a lot when logging
    
    // Target:
    C4Address addr;
    CBLDatabase* otherDB;
    NSURL* remoteURL = $castIf(NSURL, _config.target);
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
        otherDB = _config.target;
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
    
    // Create a C4Replicator:
    C4ReplicatorParameters params = {
        .push = mkmode(isPush(_config.replicatorType), _config.continuous),
        .pull = mkmode(isPull(_config.replicatorType), _config.continuous),
        .optionsDictFleece = {optionsFleece.buf, optionsFleece.size},
        .onStatusChanged = &statusChanged,
        .onDocumentError = &onDocError,
        .callbackContext = (__bridge void*)self,
        // TODO: Add .validationFunc (public API TBD)
    };
    
    C4Error err;
    _repl = c4repl_new(_config.database.c4db, addr, dbName, otherDB.c4db, params, &err);
    C4ReplicatorStatus status;
    if (_repl) {
        status = c4repl_getStatus(_repl);
        [_config.database.activeReplications addObject: self];     // keeps me from being dealloced
        
#if TARGET_OS_IPHONE
        if (!_config.runInBackground)
            [self setupBackgrounding];
#endif
        
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
    dispatch_async(_dispatchQueue, ^{
        if (_repl)
            c4repl_stop(_repl);     // this is async; status will change when repl actually stops
        
        [_reachability stop];
        _reachability = nil;
        
        _isStopping = YES;
        _isSuspending = NO;
        
        // If the current status if offline,  _repl is already stopped so needs to manually
        // post notification:
        if (_rawStatus.level == kC4Offline)
            [self notifyStopped];
    });
}


- (void) startReachabilityObserver {
    if (_reachability)
        return;
    
    NSURL* remoteURL = $castIf(NSURL, _config.target);
    if (!remoteURL)
        return;
    
    NSString* hostname = remoteURL.host;
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


- (BOOL) isActive {
    return _rawStatus.level == kC4Connecting || _rawStatus.level == kC4Busy;
}


- (void) notifyStopped {
    C4ReplicatorStatus status = {.level = kC4Stopped};
    [self c4StatusChanged: status];
}


#pragma mark - Suspend:


- (void) setSuspended: (BOOL)suspended {
    // This is called under _dispatchQueue:
    if (suspended != _suspended) {
        if (_isStopping || _rawStatus.level == kC4Stopped) {
            CBLLog(Sync, @"%@: Ignore suspending, the replicator is stopping or already stopped.", self);
            _suspended = NO;
            return;
        }
        
        // Update suspended flag:
        _suspended = suspended;
        
        if (_isSuspending) // Already in process:
            return;
        
        if(_suspended) {
            CBLLog(Sync, @"%@: Suspending ...", self);
            _isSuspending = YES;
            if (_repl)
                c4repl_stop(_repl);
            else /* offline */
                [self notifyStopped];
        } else
            [self retry];
    }
}


#pragma mark - Change Listener:


- (id<NSObject>) addChangeListener: (void (^)(CBLReplicatorChange*))block {
    if (!_changeListeners) {
        _changeListeners = [NSMutableSet set];
    }
    
    CBLChangeListener* listener = [[CBLChangeListener alloc] initWithBlock:block];
    [_changeListeners addObject:listener];
    return listener;
}


- (void) removeChangeListener: (id<NSObject>)listener {
    [_changeListeners removeObject: listener];
}


#pragma mark - Status Changes:


static void statusChanged(C4Replicator *repl, C4ReplicatorStatus status, void *context) {
    auto replicator = (__bridge CBLReplicator*)context;
    dispatch_async(replicator->_dispatchQueue, ^{
        if (repl == replicator->_repl)
            [replicator c4StatusChanged: status];
    });
}


- (void) c4StatusChanged: (C4ReplicatorStatus)c4Status {
    BOOL shouldResume = NO;
    BOOL didSuspend = NO;
    if (c4Status.level == kC4Stopped) {
        didSuspend = [self handleSuspending: &shouldResume];
        if (didSuspend || [self handleError: c4Status.error]) {
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

    // Post change
    CBLReplicatorChange* change = [[CBLReplicatorChange alloc] initWithReplicator: self
                                                                           status: self.status];
    [self notifyChange: change];
    
    // If Stopped:
    if (c4Status.level == kC4Stopped) {
        // Stopped:
#if TARGET_OS_IPHONE
        [self endBackgrounding];
#endif
        _suspended = NO;
        _isStopping = NO;
        
        [self clearRepl];
        [_config.database.activeReplications removeObject: self];  // this is likely to dealloc me
    } else if (!self.isActive && !didSuspend) {
#if TARGET_OS_IPHONE
        [self okToEndBackgrounding];
#endif
    } else if (shouldResume)
        [self retry];
}


- (void) notifyChange: (CBLReplicatorChange*)change {
    // Notify changes on main thread:
    dispatch_async(dispatch_get_main_queue(), ^{
        // TODO: _changeListeners is not thread safe:
        for (CBLChangeListener* listener in _changeListeners) {
            void (^block)(CBLReplicatorChange*) = listener.block;
            block(change);
        }
    });
}


- (BOOL) handleSuspending: (BOOL*)resume {
    if (!_isSuspending)
        return NO;
    
    _isSuspending = NO;
    
    if (!_config.continuous)
        return NO;
    
    [self clearRepl];
    
    // Cancel retry and reachability:
    _retryCount = 0;
    [_reachability stop];
    _reachability = nil;
    
    if (_suspended)
        CBLLog(Sync, @"%@: Suspended", self);
    
    *resume = !_suspended;
    return YES;
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
                           if (_retryCount > 0)
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
    
    _rawStatus = c4Status;
    
    // Note: c4Status.level is current matched with CBLReplicatorActivityLevel:
    CBLReplicatorActivityLevel level = (CBLReplicatorActivityLevel)c4Status.level;
    CBLReplicatorProgress progress = { c4Status.progress.unitsCompleted, c4Status.progress.unitsTotal };
    self.status = [[CBLReplicatorStatus alloc] initWithActivity: level
                                                       progress: progress
                                                          error: error];
    
    CBLLog(Sync, @"%@ is %s, progress %llu/%llu, error: %@",
           self, kC4ReplicatorActivityLevelNames[c4Status.level],
           c4Status.progress.unitsCompleted, c4Status.progress.unitsTotal, error);
}


#pragma mark - DOCUMENT-LEVEL ERRORS:


static void onDocError(C4Replicator *repl,
                       bool pushing,
                       C4String docID,
                       C4Error error,
                       bool transient,
                       void *context)
{
    NSString* docIDStr = slice2string(docID);
    auto replicator = (__bridge CBLReplicator*)context;
    dispatch_async(replicator->_dispatchQueue, ^{
        if (repl == replicator->_repl)
            [replicator onDocError: error pushing: pushing docID: docIDStr isTransient: transient];
    });
}


- (void) onDocError: (C4Error)c4err
            pushing: (bool)pushing
              docID: (NSString*)docID
        isTransient: (bool)isTransient
{
    if (!pushing && c4err.domain == LiteCoreDomain && c4err.code == kC4ErrorConflict) {
        // Conflict pulling a document -- the revision was added but app needs to resolve it:
        CBLLog(Sync, @"%@: pulled conflicting version of '%@'", self, docID);
        NSError* error;
        if (![_config.database resolveConflictInDocument: docID
                                           usingResolver: _config.conflictResolver
                                                   error: &error]) {
            CBLWarn(Sync, @"Conflict resolution of '%@' failed: %@", docID, error);
            // TODO: Should pass error along to listener
        }
    } else {
        NSError* error;
        convertError(c4err, &error);
        CBLLog(Sync, @"%@: %serror %s '%@': %@",
               self,
               (isTransient ? "transient " : ""),
               (pushing ? "pushing" : "pulling"),
               docID, error);
        // TODO: Call an optional listener (API TBD)
    }
}


@end


#pragma mark - CBLReplicatorStatus


@implementation CBLReplicatorStatus

@synthesize activity=_activity, progress=_progress, error=_error;

- (instancetype) initWithActivity: (CBLReplicatorActivityLevel)activity
                         progress: (CBLReplicatorProgress)progress
                            error: (NSError*)error
{
    self = [super init];
    if (self) {
        _activity = activity;
        _progress = progress;
        _error = error;
    }
    return self;
}

@end

