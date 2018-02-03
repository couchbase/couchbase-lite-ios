//
//  CBLReplicator.mm
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLReplicator+Internal.h"
#import "CBLReplicatorChange+Internal.h"
#import "CBLReplicatorConfiguration.h"
#import "CBLURLEndpoint.h"
#import "CBLDatabaseEndpoint.h"

#import "CBLChangeListenerToken.h"
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


@interface CBLReplicator ()
@property (readwrite, nonatomic) CBLReplicatorStatus* status;
@end


@implementation CBLReplicator
{
    dispatch_queue_t _dispatchQueue;
    C4Replicator* _repl;
    NSString* _desc;
    C4ReplicatorStatus _rawStatus;
    unsigned _retryCount;
    CBLReachability* _reachability;
    NSMutableSet* _listenerTokens;
}

@synthesize config=_config;
@synthesize status=_status;


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
        _config = [[CBLReplicatorConfiguration alloc] initWithConfig: config readonly: YES];
        _dispatchQueue = dispatch_get_main_queue();
    }
    return self;
}


- (CBLReplicatorConfiguration*) config {
    return _config;
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
    CBL_LOCK(self) {
        if (_repl) {
            CBLWarn(Sync, @"%@ has already started", self);
            return;
        }
        
        CBLLog(Sync, @"%@: Starting", self);
        _retryCount = 0;
        [self _start];
    }
}


- (void) retry {
    CBL_LOCK(self) {
        if (_repl || _rawStatus.level != kC4Offline)
            return;
        CBLLog(Sync, @"%@: Retrying...", self);
        [self _start];
    }
}


- (void) _start {
    _desc = self.description;   // cache description; it may be called a lot when logging
    
    // Target:
    C4Address addr;
    CBLDatabase* otherDB;
    NSURL* remoteURL = $castIf(CBLURLEndpoint, _config.target).url;
    CBLStringBytes dbName(remoteURL.path.lastPathComponent);
    CBLStringBytes scheme(remoteURL.scheme);
    CBLStringBytes host(remoteURL.host);
    CBLStringBytes path(remoteURL.path.stringByDeletingLastPathComponent);
    if (remoteURL) {
        // Fill out the C4Address:
        NSUInteger port = [remoteURL.port unsignedIntegerValue];
        addr = {
            .scheme = scheme,
            .hostname = host,
            .port = (uint16_t)port,
            .path = path
        };
    } else {
        otherDB = ((CBLDatabaseEndpoint*)_config.target).database;
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
    CBL_LOCK(_config.database) {
        _repl = c4repl_new(_config.database.c4db, addr, dbName, otherDB.c4db, params, &err);
    }
    
    C4ReplicatorStatus status;
    if (_repl) {
        status = c4repl_getStatus(_repl);
        CBL_LOCK(_config.database) {
            [_config.database.activeReplications addObject: self];     // keeps me from being dealloced
        }
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
    return type == kCBLReplicatorTypePushAndPull || type == kCBLReplicatorTypePush;
}


static BOOL isPull(CBLReplicatorType type) {
    return type == kCBLReplicatorTypePushAndPull || type == kCBLReplicatorTypePull;
}


- (void) stop {
    CBL_LOCK(self) {
        if (_repl)
            c4repl_stop(_repl);     // this is async; status will change when repl actually stops
        else if (_rawStatus.level == kC4Offline)
            [self c4StatusChanged: {.level = kC4Stopped}];
        
        [_reachability stop];
        _reachability = nil;
    }
}


- (void) startReachabilityObserver {
    if (_reachability)
        return;
    
    NSURL* remoteURL = $castIf(CBLURLEndpoint, _config.target).url;
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
    CBL_LOCK(self) {
        bool reachable = _reachability.reachable;
        if (reachable && !_repl) {
            CBLLog(Sync, @"%@: Server may now be reachable; retrying...", self);
            _retryCount = 0;
            [self retry];
        }
    }
}


- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLReplicatorChange*))listener {
    return [self addChangeListenerWithQueue: nil listener: listener];
}


- (id<CBLListenerToken>) addChangeListenerWithQueue: (dispatch_queue_t)queue
                                           listener: (void (^)(CBLReplicatorChange*))listener
{
    CBL_LOCK(self) {
        if (!_listenerTokens) {
            _listenerTokens = [NSMutableSet set];
        }
        
        id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                              queue: queue];
        [_listenerTokens addObject: token];
        return token;
    }
}


- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    CBL_LOCK(self) {
        [_listenerTokens removeObject: token];
    }
}


#pragma mark - STATUS CHANGES:


static void statusChanged(C4Replicator *repl, C4ReplicatorStatus status, void *context) {
    auto replicator = (__bridge CBLReplicator*)context;
    dispatch_async(replicator->_dispatchQueue, ^{
        if (repl == replicator->_repl)
            [replicator c4StatusChanged: status];
    });
}


- (void) c4StatusChanged: (C4ReplicatorStatus)c4Status {
    CBL_LOCK(self) {
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
        
        // Post change
        CBLReplicatorChange* change = [[CBLReplicatorChange alloc] initWithReplicator: self
                                                                               status: self.status];
        for (CBLChangeListenerToken* token in _listenerTokens) {
            void (^listener)(CBLReplicatorChange*) = token.listener;
            dispatch_async(token.queue, ^{
                listener(change);
            });
        }
        
        // If Stopped:
        if (c4Status.level == kC4Stopped) {
            // Stopped:
            [self clearRepl];
            CBL_LOCK(_config.database) {
                [_config.database.activeReplications removeObject: self];      // this is likely to dealloc me
            }
        }
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
        CBL_LOCK(replicator) {
            if (repl == replicator->_repl)
                [replicator onDocError: error pushing: pushing docID: docIDStr isTransient: transient];
        }
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

