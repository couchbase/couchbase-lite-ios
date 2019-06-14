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

// Replicator progress level types:
typedef enum {
    kCBLProgressLevelBasic = 0,
    kCBLProgressLevelDocument
} CBLReplicatorProgressLevel;

// For controlling async start, stop, and suspend:
typedef enum {
    kCBLStateStopped = 0,       ///< The replicator was stopped.
    kCBLStateStopping,          ///< The replicator was asked to stop but in progress.
    kCBLStateSuspended,         ///< The replicator was suspended; replicator's status is offline.
    kCBLStateSuspending,        ///< The replicator was asked to suspend but in progress.
    kCBLStateOffline,           ///< The replicator is offline due to a transient or network error.
    kCBLStateRunning,           ///< The replicator is running which is either idle or busy.
    kCBLStateStarting           ///< The replicator was asked to start but in progress.
} CBLReplicatorState;

@interface CBLReplicator ()
@property (readwrite, atomic) CBLReplicatorStatus* status;
@end


@implementation CBLReplicator
{
    dispatch_queue_t _dispatchQueue;
    dispatch_queue_t _conflictQueue;
    C4Replicator* _repl;
    NSString* _desc;
    CBLReplicatorState _state;
    C4ReplicatorStatus _rawStatus;
    unsigned _retryCount;
    BOOL _allowReachability;
    CBLReachability* _reachability;
    CBLReplicatorProgressLevel _progressLevel;
    CBLChangeNotifier<CBLReplicatorChange*>* _changeNotifier;
    CBLChangeNotifier<CBLDocumentReplication*>* _docReplicationNotifier;
    BOOL _resetCheckpoint;          // Reset the replicator checkpoint
    BOOL _cancelSuspending;         // Cancel the current suspending request
    unsigned _conflictCount;        // Current number of conflict resolving tasks
    BOOL _deferStoppedNotification; // Defer the stopped until finishing all conflict resolving tasks
}

@synthesize config=_config;
@synthesize status=_status;
@synthesize bgMonitor=_bgMonitor;
@synthesize dispatchQueue=_dispatchQueue;


- (instancetype) initWithConfig: (CBLReplicatorConfiguration *)config {
    CBLAssertNotNil(config);
    
    self = [super init];
    if (self) {
        NSParameterAssert(config.database != nil && config.target != nil);
        _config = [[CBLReplicatorConfiguration alloc] initWithConfig: config readonly: YES];
        _progressLevel = kCBLProgressLevelBasic;
        _changeNotifier = [CBLChangeNotifier new];
        _docReplicationNotifier = [CBLChangeNotifier new];
        _status = [[CBLReplicatorStatus alloc] initWithStatus: {kC4Stopped, {}, {}}];
        
        NSString* qName = self.description;
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        NSString* cqName = $sprintf(@"%@ : Conflicts", qName);
        _conflictQueue = dispatch_queue_create(cqName.UTF8String, DISPATCH_QUEUE_CONCURRENT);
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
    if (!_desc)
        _desc = [NSString stringWithFormat: @"%@[%s%s%s %@]",
                 self.class,
                 (isPull(_config.replicatorType) ? "<" : ""),
                 (_config.continuous ? "*" : "-"),
                 (isPush(_config.replicatorType)  ? ">" : ""),
                 _config.target];
    return _desc;
}


- (void) clearRepl {
    c4repl_free(_repl);
    _repl = nullptr;
}


- (void) start {
    CBL_LOCK(self) {
        CBLLogInfo(Sync, @"%@: Starting...", self);
        if (_state != kCBLStateStopped && _state != kCBLStateSuspended) {
            CBLWarn(Sync, @"%@ has already started (state = %d, status = %d); ignored.",
                    self,  _state, _rawStatus.level);
            return;
        }
        Assert(!_repl);
        _retryCount = 0;
        [self _start];
    }
}


- (void) retry: (BOOL)reset {
    CBL_LOCK(self) {
        CBLLogInfo(Sync, @"%@: Retrying...", self);
        if (reset)
            _retryCount = 0;
        if (_repl || _state <= kCBLStateStopping) {
            CBLLogInfo(Sync, @"%@: Ignore retrying (state = %d, status = %d)",
                       self, _state, _rawStatus.level);
            return;
        }
        [self _start];
    }
}


- (void) _start {
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
        .onDocumentsEnded = &onDocsEnded,
        .callbackContext = (__bridge void*)self,
        .socketFactory = &socketFactory,
    };
    
    _state = kCBLStateStarting;
    _cancelSuspending = NO;
    
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
        if (_state <= kCBLStateStopping) {
            CBLWarn(Sync, @"%@ has stopped or is stopping (state = %d, status = %d); ignore stop.",
                    self,  _state, _rawStatus.level);
            return;
        }
        
        CBLLogInfo(Sync, @"%@: Stopping...", self);
        _state = kCBLStateStopping;
        [self _stop];
    }
}


- (void) _stop {
    if (_repl) {
        // Stop the replicator:
        c4repl_stop(_repl); // Async calls, status will change when repl actually stops.
    } else if (_rawStatus.level == kC4Offline) {
        // Switch the offline status to stoppped:
        dispatch_async(_dispatchQueue, ^{
            [self stopReachabilityObserver];
            [self c4StatusChanged: {.level = kC4Stopped}];
        });
    }
}


- (void) stopped {
    CBL_LOCK(self) {
        Assert(_rawStatus.level == kC4Stopped);
        // Update state:
        _state = kCBLStateStopped;
        _deferStoppedNotification = NO;
        
        // Prevent self to get released when removing from the active replications:
        CBLReplicator* repl = self;
        CBL_LOCK(_config.database) {
            [_config.database.activeReplications removeObject: repl];
        }
        
        // Post status update:
        [self updateAndPostStatus];
    }
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

// Should be called from _dispatchQueue
- (void) stopReachabilityObserver {
    [_reachability stop];
    _reachability = nil;
}


- (void) reachabilityChanged {
    CBL_LOCK(self) {
        bool reachable = _reachability.reachable;
        if (reachable && _state == kCBLStateOffline) {
            CBLLogInfo(Sync, @"%@: Server may now be reachable; retrying...", self);
            [self retry: YES];
        }
    }
}


- (void) resetCheckpoint {
    CBL_LOCK(self) {
        if (_state != kCBLStateStopped) {
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


// Should be called from the dispatch queue
- (void) c4StatusChanged: (C4ReplicatorStatus)c4Status {
    CBL_LOCK(self) {
        // Convert stopped to offline if suspending or having a transient/network error:
        if (c4Status.level == kC4Stopped && _state > kCBLStateStopping) {
            if (_state == kCBLStateSuspending || [self handleError: c4Status.error])
                c4Status.level = kC4Offline;
        }
        
        // Record raw status:
        _rawStatus = c4Status;
        
        // Running; idle or busy:
        if (c4Status.level > kC4Connecting) {
            if (_state == kCBLStateStarting) {
                _state = kCBLStateRunning;
            }
            _retryCount = 0;
            [self stopReachabilityObserver];
        }
        
        // Offline / suspending:
        BOOL resume = NO;
        if (c4Status.level == kC4Offline) {
            [self clearRepl];
            if (_state == kCBLStateSuspending) {
                _state = kCBLStateSuspended;
                resume = _cancelSuspending;
            } else
                _state = kCBLStateOffline;
        }
        
        // Stopped:
        if (c4Status.level == kC4Stopped) {
            [self clearRepl];
        #if TARGET_OS_IPHONE
            [self endBackgrounding];
        #endif
            if (_conflictCount > 0) {
                CBLLogInfo(Sync, @"%@: Stopped but waiting for conflict resolution (pending = %d) "
                                  "to finish before notifying.", self, _conflictCount);
                _deferStoppedNotification = YES;
                _state = kCBLStateStopping; // Will be stopped after all conflicts are resolved
            } else
                [self stopped];
        } else
            [self updateAndPostStatus];
        
        if (resume)
            [self retry: YES];
        
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
        CBLLogInfo(Sync, @"%@: Transient error (%@); will retry in %.0f sec...",
                   self, error.localizedDescription, delay);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       _dispatchQueue, ^{
                           CBL_LOCK(self) {
                               // Retry if still in offline state:
                               if (_state == kCBLStateOffline)
                                   [self retry: NO];
                           }
                       });
    } else {
        CBLLogInfo(Sync, @"%@: Network error (%@); will retry when network changes...",
                   self, error.localizedDescription);
    }
    // Also retry when the network changes:
    [self startReachabilityObserver];
    return true;
}


- (void) updateAndPostStatus {
    NSError *error = nil;
    if (_rawStatus.error.code)
        convertError(_rawStatus.error, &error);
    
    self.status = [[CBLReplicatorStatus alloc] initWithStatus: _rawStatus];
    
    CBLLogInfo(Sync, @"%@ is %s, progress %llu/%llu, error: %@",
               self, kC4ReplicatorActivityLevelNames[_rawStatus.level],
               _rawStatus.progress.unitsCompleted, _rawStatus.progress.unitsTotal, self.status.error);
    
    [_changeNotifier postChange: [[CBLReplicatorChange alloc] initWithReplicator: self
                                                                          status: self.status]];
}


#pragma mark - DOCUMENT-LEVEL ERRORS:


static void onDocsEnded(C4Replicator *repl,
                        bool pushing,
                        size_t nDocs,
                        const C4DocumentEnded* docEnds[],
                        void *context)
{
    auto replicator = (__bridge CBLReplicator*)context;
    
    NSMutableArray* docs = [NSMutableArray new];
    for (size_t i = 0; i < nDocs; ++i) {
        [docs addObject: [[CBLReplicatedDocument alloc] initWithC4DocumentEnded: docEnds[i]]];
    }
   
    dispatch_async(replicator->_dispatchQueue, ^{
        CBL_LOCK(replicator) {
            if (repl == replicator->_repl) {
                [replicator onDocsEnded: docs pushing: pushing];
            }
        }
    });
}


- (void) onDocsEnded: (NSArray<CBLReplicatedDocument*>*)docs pushing: (BOOL)pushing {
    NSMutableArray* posts = [NSMutableArray array];
    for (CBLReplicatedDocument *doc in docs) {
        C4Error c4err = doc.c4Error;
        if (!pushing && c4err.domain == LiteCoreDomain && c4err.code == kC4ErrorConflict) {
            [self resolveConflict: doc];
        } else {
            [posts addObject: doc];
            [self logErrorOnDocument: doc pushing: pushing];
        }
    }
    if (posts.count > 0)
        [self postDocumentReplications: posts pushing: pushing];
}


- (void) resolveConflict: (CBLReplicatedDocument*)doc {
    _conflictCount++;
    dispatch_async(_conflictQueue, ^{
        [self _resolveConflict: doc];
        CBL_LOCK(self) {
            if (--_conflictCount == 0 && _deferStoppedNotification) {
                Assert(_rawStatus.level == kC4Stopped);
                Assert(_state == kCBLStateStopping);
                [self stopped];
            }
        }
    });
}


- (void) _resolveConflict: (CBLReplicatedDocument*)doc {
    CBLLogInfo(Sync, @"%@: Resolve conflicting version of '%@'", self, doc.id);
    NSError* error;
    if ([_config.database resolveConflictInDocument: doc.id
                               withConflictResolver: _config.conflictResolver
                                              error: &error])
        [doc resetError];
    else {
        CBLWarn(Sync, @"%@: Conflict resolution of '%@' failed: %@", self, doc.id, error);
        [doc updateError: error];
    }
    [self logErrorOnDocument: doc pushing: NO];
    [self postDocumentReplications: @[doc] pushing: NO];
}


- (void) postDocumentReplications: (NSArray<CBLReplicatedDocument*>*)docs pushing: (BOOL)pushing {
    id replication = [[CBLDocumentReplication alloc] initWithReplicator: self
                                                                 isPush: pushing
                                                              documents: docs];
    [_docReplicationNotifier postChange: replication];
}


- (void) logErrorOnDocument: (CBLReplicatedDocument*)doc pushing: (BOOL)pushing {
    C4Error c4err = doc.c4Error;
    if (doc.c4Error.code)
        CBLLogInfo(Sync, @"%@: %serror %s '%@': %d/%d", self, (doc.isTransientError ? "transient " : ""),
                   (pushing ? "pushing" : "pulling"), doc.id, c4err.domain, c4err.code);
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
    
    CBLDocumentFlags docFlags = 0;
    if ((flags & kRevDeleted) == kRevDeleted)
        docFlags |= kCBLDocumentFlagsDeleted;
    
    if ((flags & kRevPurged) == kRevPurged)
        docFlags |= kCBLDocumentFlagsAccessRemoved;
    
    return pushing ? _config.pushFilter(doc, docFlags) : _config.pullFilter(doc, docFlags);
}


#pragma mark - BACKGROUNDING SUPPORT


- (BOOL) active {
    CBL_LOCK(self) {
        return (_rawStatus.level == kC4Connecting || _rawStatus.level == kC4Busy);
    }
}


- (void) setSuspended: (BOOL)suspended {
    CBL_LOCK(self) {
        if (_state <= kCBLStateStopping) {
            CBLLogInfo(Sync, @"%@: Ignore suspended = %d (state = %d, status = %d)",
                       self, suspended, _state, _rawStatus.level);
            return;
        }
        
        BOOL changed = suspended != (_state == kCBLStateSuspended || _state == kCBLStateSuspending);
        if (changed) {
            CBLLogInfo(Sync, @"%@: Set suspended = %d (state = %d, status = %d)",
                       self, suspended, _state, _rawStatus.level);
            if (_state == kCBLStateSuspending) {
                _cancelSuspending = !suspended;
                return;
            }
            
            if (suspended) {
                _state = kCBLStateSuspending;
                [self _stop];
            } else
                [self retry: YES];
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

