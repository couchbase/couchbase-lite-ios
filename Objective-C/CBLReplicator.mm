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

#import "CBLReplicator+Backgrounding.h"
#import "CBLDocumentReplication+Internal.h"
#import "CBLReplicator+Internal.h"
#import "CBLReplicatorChange+Internal.h"
#import "CBLReplicatorConfiguration.h"
#import "CBLURLEndpoint.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLDatabaseEndpoint.h"
#import "CBLMessageEndpoint+Internal.h"
#endif

#import "CBLChangeNotifier.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLReachability.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"

#import "c4Replicator.h"
#import "c4Socket.h"
#import "CBLWebSocket.h"
#import "fleece/Fleece.hh"
#import <algorithm>

using namespace std;
using namespace fleece;


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

typedef enum {
    kCBLProgressLevelBasic = 0,
    kCBLProgressLevelDocument
} CBLReplicatorProgressLevel;

@interface CBLReplicator ()
@property (readwrite, atomic) CBLReplicatorStatus* status;
@end


@implementation CBLReplicator
{
    dispatch_queue_t _dispatchQueue;
    C4Replicator* _repl;
    NSString* _desc;
    C4ReplicatorStatus _rawStatus;
    unsigned _retryCount;
    BOOL _allowReachability;
    CBLReachability* _reachability;
    CBLReplicatorProgressLevel _progressLevel;
    CBLChangeNotifier<CBLReplicatorChange*>* _changeNotifier;
    CBLChangeNotifier<CBLDocumentReplication*>* _docReplicationNotifier;
    BOOL _resetCheckpoint;
    
    // TODO: Instead of having multiple boolean variables, we could
    // have a enum based variable to represent the replicator state.
    BOOL _isStopping;
    BOOL _isSuspending;
}

@synthesize config=_config;
@synthesize status=_status;
@synthesize bgMonitor=_bgMonitor;
@synthesize suspended=_suspended;
@synthesize dispatchQueue=_dispatchQueue;


- (instancetype) initWithConfig: (CBLReplicatorConfiguration *)config {
    CBLAssertNotNil(config);
    
    self = [super init];
    if (self) {
        NSParameterAssert(config.database != nil && config.target != nil);
        _config = [[CBLReplicatorConfiguration alloc] initWithConfig: config readonly: YES];
        _dispatchQueue = config.database.dispatchQueue;
        _progressLevel = kCBLProgressLevelBasic;
        _changeNotifier = [CBLChangeNotifier new];
        _docReplicationNotifier = [CBLChangeNotifier new];
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
        _suspended = NO;
        _isSuspending = NO;
        [self _start];
    }
}


- (void) retry {
    CBL_LOCK(self) {
        if (_repl || _rawStatus.level != kC4Offline) {
            CBLLog(Sync, @"%@: Ignore retrying (status = %d)", self, _rawStatus.level);
            return;
        }
        
        CBLLog(Sync, @"%@: Retrying...", self);
        [self _start];
    }
}


- (void) _start {
    _desc = self.description;   // cache description; it may be called a lot when logging
    
    // Target:
    id<CBLEndpoint> endpoint = _config.target;
    C4Address addr = {};
    CBLDatabase* otherDB = nil;
    NSURL* remoteURL = $castIf(CBLURLEndpoint, endpoint).url;
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
#ifdef COUCHBASE_ENTERPRISE
        otherDB = $castIf(CBLDatabaseEndpoint, endpoint).database;
#else
        Assert(remoteURL, @"Endpoint has no URL");
#endif
    }

    // Encode the options:
    alloc_slice optionsFleece;
    
    NSMutableDictionary* options = [_config.effectiveOptions mutableCopy];
    options[@kC4ReplicatorOptionProgressLevel] = @(_progressLevel);
    
    // Update resetCheckpoint flag if needed:
    if (_resetCheckpoint) {
        options[@kC4ReplicatorResetCheckpoint] = @(YES);
        _resetCheckpoint = NO;
    }
    
    if (options.count) {
        Encoder enc;
        enc << options;
        optionsFleece = enc.finish();
    }
    
    _allowReachability = YES;
    C4SocketFactory socketFactory = { };
#ifdef COUCHBASE_ENTERPRISE
    auto messageEndpoint = $castIf(CBLMessageEndpoint, endpoint);
    if (messageEndpoint) {
        socketFactory = messageEndpoint.socketFactory;
        addr.scheme = C4STR("x-msg-endpt"); // put something in the address so it's not illegal
        _allowReachability = NO;
    } else
#endif
        if (remoteURL)
            socketFactory = CBLWebSocket.socketFactory;
    socketFactory.context = (__bridge void*)self;
    
    // Create a C4Replicator:
    C4ReplicatorParameters params = {
        .push = mkmode(isPush(_config.replicatorType), _config.continuous),
        .pull = mkmode(isPull(_config.replicatorType), _config.continuous),
        .pushFilter = filter(_config.pushFilter, true),
        .validationFunc = filter(_config.pullFilter, false),
        .optionsDictFleece = {optionsFleece.buf, optionsFleece.size},
        .onStatusChanged = &statusChanged,
        .onDocumentEnded = &onDocEnded,
        .callbackContext = (__bridge void*)self,
        .socketFactory = &socketFactory,
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
        
    #if TARGET_OS_IPHONE
        if (!_config.allowReplicatingInBackground)
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
    return type == kCBLReplicatorTypePushAndPull || type == kCBLReplicatorTypePush;
}


static BOOL isPull(CBLReplicatorType type) {
    return type == kCBLReplicatorTypePushAndPull || type == kCBLReplicatorTypePull;
}


static C4ReplicatorValidationFunction filter(CBLReplicationFilter filter, bool isPush) {
    return filter != nil ? (isPush ? &pushFilter : &pullFilter) : NULL;
}


- (void) stop {
    CBL_LOCK(self) {
        _isStopping = YES;
        _suspended = NO;
        _isSuspending = NO;
        [self _stop];
    }
}


- (void) _stop {
    if (_repl)
        c4repl_stop(_repl);     // this is async; status will change when repl actually stops
    else if (_rawStatus.level == kC4Offline)
        [self c4StatusChanged: {.level = kC4Stopped}];
    else if (_isStopping)
        _isStopping = NO;
    [self stopReachabilityObserver];
}


- (void) startReachabilityObserver {
    if (!_allowReachability || _reachability)
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


- (void) stopReachabilityObserver {
    [_reachability stop];
    _reachability = nil;
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


- (void) resetCheckpoint {
    CBL_LOCK(self) {
        if (_rawStatus.level != kC4Stopped) {
            [NSException raise: NSInternalInconsistencyException
                        format: @"Replicator is not stopped. Resetting checkpoint"
                                 "is only allowed when the replicator is in the stopped state."];
        }
        _resetCheckpoint = YES;
    }
}


- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLReplicatorChange*))listener {
    return [self addChangeListenerWithQueue: nil listener: listener];
}


- (id<CBLListenerToken>) addChangeListenerWithQueue: (dispatch_queue_t)queue
                                           listener: (void (^)(CBLReplicatorChange*))listener
{
    return [_changeNotifier addChangeListenerWithQueue: queue listener: listener];
}


- (id<CBLListenerToken>) addDocumentReplicationListener: (void (^)(CBLDocumentReplication*))listener {
    return [self addDocumentReplicationListenerWithQueue: nil listener: listener];
}


- (id<CBLListenerToken>) addDocumentReplicationListenerWithQueue: (nullable dispatch_queue_t)queue
                                                        listener: (void (^)(CBLDocumentReplication*))listener
{
    CBL_LOCK(self) {
        _progressLevel = kCBLProgressLevelDocument;
        return [_docReplicationNotifier addChangeListenerWithQueue: queue listener: listener];
    }
}


- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    [_changeNotifier removeChangeListenerWithToken: token];
    
    CBL_LOCK(self) {
        if ([_docReplicationNotifier removeChangeListenerWithToken: token] == 0)
            _progressLevel = kCBLProgressLevelBasic;
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
        if (c4Status.level == kC4Stopped && !_isStopping) {
            if (_isSuspending || [self handleError: c4Status.error]) {
                // Change c4Status to offline, so my state will reflect that, and proceed:
                c4Status.level = kC4Offline;
            }
        } else if (c4Status.level > kC4Connecting) {
            _retryCount = 0;
            [self stopReachabilityObserver];
        }
        
        // Prevent self to get released when removing from the active replications:
        CBLReplicator* repl = self;
        if (c4Status.level == kC4Stopped) {
            CBL_LOCK(_config.database) {
                // Remove from the active replications before posting change:
                [_config.database.activeReplications removeObject: repl];
            }
        }
        
        // Update my properties:
        [self updateStateProperties: c4Status];
        
        // Post change
        [_changeNotifier postChange: [[CBLReplicatorChange alloc] initWithReplicator: self
                                                                              status: self.status]];
        
        // Clear replicator:
        if (c4Status.level == kC4Offline && _isSuspending) {
            _isSuspending = NO;
            [self clearRepl];
            if (!_suspended) {
                _retryCount = 0;
                [self retry];
            }
        } else if (c4Status.level == kC4Stopped) {
            _isStopping = NO;
            [self clearRepl];
        #if TARGET_OS_IPHONE
            [self endBackgrounding];
        #endif
        }
        
    #if TARGET_OS_IPHONE
        //  End the current background task when the replicator is idle:
        if (c4Status.level == kC4Idle)
            [self endCurrentBackgroundTask];
    #endif
    }
}


- (bool) handleError: (C4Error)c4err {
    // If this is a transient error, or if I'm continuous and the error might go away with a change
    // in network (i.e. network down, hostname unknown), then go offline and retry later.
    bool transient = c4error_mayBeTransient(c4err) ||
        (c4err.domain == WebSocketDomain && c4err.code == kCBLWebSocketCloseUserTransient);
    if (!transient && !(_config.continuous && c4error_mayBeNetworkDependent(c4err)))
        return false;   // nope, this is permanent
    if (!_config.continuous && _retryCount >= kMaxOneShotRetryCount)
        return false;   // too many retries

    [self clearRepl];
    NSError *error = nil;
    convertError(c4err, &error);
    
    // Transient error or maybe still reachable:
    if (transient || _reachability.reachable) {
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
    self.status = [[CBLReplicatorStatus alloc] initWithStatus: c4Status];
    CBLLog(Sync, @"%@ is %s, progress %llu/%llu, error: %@",
           self, kC4ReplicatorActivityLevelNames[c4Status.level],
           c4Status.progress.unitsCompleted, c4Status.progress.unitsTotal, self.status.error);
}


#pragma mark - DOCUMENT-LEVEL ERRORS:


static void onDocEnded(C4Replicator *repl,
                       bool pushing,
                       C4HeapString docID,
                       C4HeapString revID,
                       C4RevisionFlags flags,
                       C4Error error,
                       bool errorIsTransient,
                       void *context)
{
    NSString* docIDStr = slice2string(docID);
    auto replicator = (__bridge CBLReplicator*)context;
    dispatch_async(replicator->_dispatchQueue, ^{
        CBL_LOCK(replicator) {
            if (repl == replicator->_repl) {
                if (error.code)
                    [replicator onDocError: error pushing: pushing docID: docIDStr
                               isTransient: errorIsTransient];
                else
                    [replicator onDocEnded: docIDStr pushing: pushing error: nil];
            }
        }
    });
}


- (void) onDocError: (C4Error)c4err
            pushing: (bool)pushing
              docID: (NSString*)docID
        isTransient: (bool)isTransient
{
    NSError* error;
    
    if (!pushing && c4err.domain == LiteCoreDomain && c4err.code == kC4ErrorConflict) {
        // Conflict pulling a document -- the revision was added but app needs to resolve it:
        CBLLog(Sync, @"%@: pulled conflicting version of '%@'", self, docID);
        if (![_config.database resolveConflictInDocument: docID error: &error])
            CBLWarn(Sync, @"%@: Conflict resolution of '%@' failed: %@", self, docID, error);
    } else
        convertError(c4err, &error);
    
    CBLLog(Sync, @"%@: %serror %s '%@': %@",
           self,
           (isTransient ? "transient " : ""),
           (pushing ? "pushing" : "pulling"),
           docID, error);
    
    [self onDocEnded: docID pushing: pushing error: error];
}


- (void) onDocEnded: (NSString*)docID pushing: (bool)pushing error: (nullable NSError*)error {
    [_docReplicationNotifier postChange: [[CBLDocumentReplication alloc] initWithReplicator: self
                                                                                     isPush: pushing
                                                                                 documentID: docID
                                                                                      error: nil]];
}


#pragma mark - Push/Pull Filter


static bool pushFilter(C4String docID, C4RevisionFlags flags, FLDict flbody, void *context) {
    auto replicator = (__bridge CBLReplicator*)context;
    return [replicator filterDocument: docID flags: flags body: flbody pushing: true];
}


static bool pullFilter(C4String docID, C4RevisionFlags flags, FLDict flbody, void *context) {
    auto replicator = (__bridge CBLReplicator*)context;
    return [replicator filterDocument: docID flags: flags body: flbody pushing: false];
}


- (bool) filterDocument: (C4String)docID
                  flags: (C4RevisionFlags)flags
                   body: (FLDict)body
                pushing: (bool)pushing
{
    auto doc = [[CBLDocument alloc] initWithDatabase: _config.database
                                          documentID: slice2string(docID)
                                                body: body];
    bool isDeleted = (flags & kRevDeleted) != 0;
    return pushing ? _config.pushFilter(doc, isDeleted) : _config.pullFilter(doc, isDeleted);
}


#pragma mark - BACKGROUNDING SUPPORT


- (BOOL) active {
    CBL_LOCK(self) {
        return (_rawStatus.level == kC4Connecting || _rawStatus.level == kC4Busy);
    }
}


- (BOOL) suspended {
    CBL_LOCK(self) {
        return _suspended;
    }
}


- (void) setSuspended: (BOOL)suspended {
    CBL_LOCK(self) {
        if (_isStopping || _rawStatus.level == kC4Stopped) {
            CBLLog(Sync, @"%@: Ignore setting suspended = %d (%@)",
                   self, suspended, (_isStopping ? @"stopping" : @"stoppped"));
            return;
        }
        
        if (_suspended != suspended) {
            CBLLog(Sync, @"%@: Set suspended = %d (suspending = %d)",
                   self, suspended, _isSuspending);
            
            _suspended = suspended;
            
            if (_isSuspending)
                return;
            
            if (_suspended) {
                _isSuspending = YES;
                [self _stop];
            } else {
                _retryCount = 0;
                [self retry];
            }
        }
    }
}


@end


#pragma mark - CBLReplicatorStatus


@implementation CBLReplicatorStatus

@synthesize activity=_activity, progress=_progress, error=_error;

- (instancetype) initWithStatus: (C4ReplicatorStatus)c4Status {
    self = [super init];
    if (self) {
        // Note: c4Status.level is current matched with CBLReplicatorActivityLevel:
        _activity = (CBLReplicatorActivityLevel)c4Status.level;
        _progress = { c4Status.progress.unitsCompleted, c4Status.progress.unitsTotal };
        if (c4Status.error.code) {
            NSError* error;
            convertError(c4Status.error, &error);
            _error = error;
            
        }
    }
    return self;
}

@end

