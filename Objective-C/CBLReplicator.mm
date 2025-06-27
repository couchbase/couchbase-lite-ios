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

#import "CBLReplicator.h"
#import "CBLReplicator+Backgrounding.h"
#import "CBLReplicator+Internal.h"
#import "CBLCollectionConfiguration+Internal.h"
#import "CBLCollection+Internal.h"
#import "CBLDocumentReplication+Internal.h"
#import "CBLReplicatorChange+Internal.h"
#import "CBLReplicatorConfiguration.h"
#import "CBLReplicatorStatus+Internal.h"
#import "CBLScope.h"
#import "CBLURLEndpoint.h"
#import "fleece/Expert.hh"              // for AllocedDict

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
#import "CBLErrorMessage.h"
#import "CBLLockable.h"
#import "CBLScope.h"
#import "CBLWebSocket.h"

#import "c4Replicator.h"
#import "c4Socket.h"
#import "fleece/Fleece.hh"

#import <algorithm>
#import <vector>

using namespace std;
using namespace fleece;


// Replicator progress level types:
typedef enum {
    kCBLProgressLevelOverall = 0,
    kCBLProgressLevelPerDocument,
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

@interface CBLReplicator () <CBLLockable, CBLRemovableListenerToken, CBLWebSocketContext>
@property (readwrite, atomic) CBLReplicatorStatus* status;
@end

@implementation CBLReplicator
{
    dispatch_queue_t _dispatchQueue;
    dispatch_queue_t _conflictQueue;
    C4Replicator* _repl;
    NSString* _replicatorID;
    NSString* _desc;
    CBLReplicatorState _state;
    C4ReplicatorStatus _rawStatus;
    NSURL* _reachabilityURL;
    CBLReachability* _reachability;
    CBLReplicatorProgressLevel _progressLevel;
    CBLChangeNotifier<CBLReplicatorChange*>* _changeNotifier;
    CBLChangeNotifier<CBLDocumentReplication*>* _docReplicationNotifier;
    BOOL _resetCheckpoint;          // Reset the replicator checkpoint
    BOOL _conflictResolutionSuspended;
    NSMutableArray<dispatch_block_t>* _pendingConflicts;
    BOOL _deferChangeNotification;  // Defer change notification until finishing all conflict resolving tasks
    SecCertificateRef _serverCertificate;
    NSDictionary* _collectionMap;   // [scopeName.collectionName : CBLCollection]
}

@synthesize config=_config;
@synthesize status=_status;
@synthesize bgMonitor=_bgMonitor;
@synthesize dispatchQueue=_dispatchQueue;

// Too many deprecated config.database usage, hence declared on top!
// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (instancetype) initWithConfig: (CBLReplicatorConfiguration *)config {
    CBLAssertNotNil(config);
    
    self = [super init];
    if (self) {
        NSParameterAssert(config.target != nil);
        
        if (config.collections.count == 0)
            [NSException raise: NSInvalidArgumentException
                        format: @"Attempt to initiate replicator with empty collection"];
        
        _config = [[CBLReplicatorConfiguration alloc] initWithConfig: config readonly: YES];
        _replicatorID = $sprintf(@"CBLRepl@%p", self);
        _progressLevel = kCBLProgressLevelOverall;
        _changeNotifier = [CBLChangeNotifier new];
        _docReplicationNotifier = [CBLChangeNotifier new];
        _pendingConflicts = [NSMutableArray array];
        _status = [[CBLReplicatorStatus alloc] initWithStatus: {kC4Stopped, {}, {}}];
        
        NSString* qName = self.description;
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        NSString* cqName = $sprintf(@"%@ : Conflicts", qName);
        _conflictQueue = dispatch_queue_create(cqName.UTF8String, DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void) dealloc {
    [self stopReachability];
    
    // Free C4Replicator:
    c4repl_free(_repl);
    
    // Release server cert if available:
    self.serverCertificate = NULL;
}

- (NSString*) description {
    if (!_desc) {
        BOOL isPull = _config.replicatorType == kCBLReplicatorTypePull || 
                      _config.replicatorType == kCBLReplicatorTypePushAndPull;
        BOOL isPush = _config.replicatorType == kCBLReplicatorTypePush ||
                      _config.replicatorType == kCBLReplicatorTypePushAndPull;
        
        _desc = [NSString stringWithFormat: @"CBLReplicator[%@ (%@%@%@) %@]",
                 _replicatorID,
                 isPull ? @"<" : @"",
                 _config.continuous ? @"*" : @"o",
                 isPush ? @">" : @"",
                 _config.target.description
        ];
    }
    return _desc;
}

- (void) start {
    [self startWithReset: NO];
}

- (void) startWithReset: (BOOL)reset {
    CBL_LOCK(self) {
        CBLLogInfo(Sync, @"%@ Collections[%@] Starting...", self, _config.collections);
        if (_state != kCBLStateStopped && _state != kCBLStateSuspended) {
            CBLWarn(Sync, @"%@ Replicator has already been started (state = %d, status = %d); ignored.",
                    self,  _state, _rawStatus.level);
            return;
        }
        
        C4ReplicatorStatus status;
        C4Error err;
        if ([self _setupC4Replicator: &err]) {
            // Start the C4Replicator:
            self.serverCertificate = NULL;
            _state = kCBLStateStarting;
            [self setConflictResolutionSuspended: NO];
            c4repl_start(_repl, reset);
            status = c4repl_getStatus(_repl);
            [_config.database registerActiveService: self];
            
#if TARGET_OS_IPHONE
            if (!_config.allowReplicatingInBackground)
                [self startBackgroundingMonitor];
#endif
        } else {
            // Failed to create C4Replicator:
            NSError *error = nil;
            convertError(err, &error);
            CBLWarnError(Sync, @"%@ Replicator cannot be created: %@", self, error.localizedDescription);
            status = {kC4Stopped, {}, err};
        }
        [self setProgressLevel: _progressLevel];
        
        // Post an initial notification:
        statusChanged(_repl, status, (__bridge void*)self);
    }
}

// Initializes _repl with a new C4Replicator the first time it's called.
// On subsequent calls, just updates the options.
- (bool) _setupC4Replicator: (C4Error*)outErr {
    if (_repl) {
        // If _repl exists, just update the options dict, in case -resetCheckpoint has been called:
        c4repl_setOptions(_repl, [self encodedOptions: _config.effectiveOptions]);
        return true;
    }

    // Address:
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
        addr = {
            .scheme = scheme,
            .hostname = host,
            .port = remoteURL.port.unsignedShortValue,
            .path = path
        };
    } else {
#ifdef COUCHBASE_ENTERPRISE
        otherDB = $castIf(CBLDatabaseEndpoint, endpoint).database;
#else
        Assert(remoteURL, @"Endpoint has no URL");
#endif
    }
    CBLStringBytes replicatorID(_replicatorID);

    // Socket factory:
    C4SocketFactory socketFactory = { };
    _reachabilityURL = nil;
#ifdef COUCHBASE_ENTERPRISE
    auto messageEndpoint = $castIf(CBLMessageEndpoint, endpoint);
    if (messageEndpoint) {
        socketFactory = messageEndpoint.socketFactory;
        addr.scheme = C4STR("x-msg-endpt"); // put something in the address so it's not illegal
    } else
#endif
    {
        if (remoteURL) {
            socketFactory = CBLWebSocket.socketFactory;
            NSString* hostname = remoteURL.host;
            if (hostname.length > 0 && ![hostname isEqualToString: @"localhost"]
                                    && ![hostname isEqualToString: @"127.0.0.1"]) {
                _reachabilityURL = remoteURL;
            }
        }
    }
    socketFactory.context = (__bridge void*)self;

    // Parameters:
    alloc_slice optionsFleece = [self encodedOptions: _config.effectiveOptions];
    C4ReplicatorParameters params = {
        .optionsDictFleece = optionsFleece,
        .onStatusChanged = &statusChanged,
        .onDocumentsEnded = &onDocsEnded,
        .callbackContext = (__bridge void*)self,
        .socketFactory = &socketFactory,
    };
    
    // Collections:
    std::vector<C4ReplicationCollection> cols;
    std::vector<alloc_slice> optionDicts;
    
    for (CBLCollection* col in _config.collectionConfigs) {
        CBLCollectionConfiguration* colConfig = _config.collectionConfigs[col];
        
        alloc_slice dict = [self encodedOptions: colConfig.effectiveOptions];
        optionDicts.push_back(dict);
        
        C4ReplicationCollection c = {
            .collection = col.c4spec,
            .push = mkmode(isPush(_config.replicatorType), _config.continuous),
            .pull = mkmode(isPull(_config.replicatorType), _config.continuous),
            .pushFilter = filter(colConfig.pushFilter, true),
            .pullFilter = filter(colConfig.pullFilter, false),
            .callbackContext    = (__bridge void*)self,
            .optionsDictFleece  = dict,
        };
        
        cols.push_back(c);
    }
    
    params.collections = cols.data();
    params.collectionCount = cols.size();
    
    [self createCollectionMap];
    
    [self initReachability: _reachabilityURL];
    
    // Create a C4Replicator:
    [_config.database safeBlock: ^{
        [self->_config.database mustBeOpenLocked];
        
        if (remoteURL || !otherDB)
            self->_repl = c4repl_new(self->_config.database.c4db, addr, dbName, params, replicatorID, outErr);
        else  {
#ifdef COUCHBASE_ENTERPRISE
            if (otherDB) {
                [otherDB safeBlock: ^{
                    [otherDB mustBeOpenLocked];
                    self->_repl = c4repl_newLocal(self->_config.database.c4db, otherDB.c4db, params, replicatorID, outErr);
                }];
            }
#else
            Assert(remoteURL, @"Endpoint has no URL");
#endif
        }
    }];

    return (_repl != nullptr);
}

- (alloc_slice) encodedOptions: (NSDictionary*)config {
    NSMutableDictionary* mdict = [config mutableCopy];
    Encoder enc;
    enc << mdict;
    return enc.finish();
}

- (void) createCollectionMap {
    NSArray* collections = _config.collections;
    NSMutableDictionary* mdict = [NSMutableDictionary dictionaryWithCapacity: collections.count];
    for (CBLCollection* col in collections)
        [mdict setObject: col forKey: $sprintf(@"%@.%@", col.scope.name, col.name)];
    
    _collectionMap = [NSDictionary dictionaryWithDictionary: mdict];
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
            CBLWarn(Sync, @"%@ Replicator has been stopped or is stopping (state = %d, status = %d); ignore stop.",
                    self,  _state, _rawStatus.level);
            return;
        }
        
        CBLLogInfo(Sync, @"%@ Stopping...", self);
        _state = kCBLStateStopping;
        
        Assert(_repl);
        c4repl_stop(_repl); // Async calls, status will change when repl actually stops.
    }
}

// Always being called inside the lock
- (void) stopped {
    Assert(_rawStatus.level == kC4Stopped);
    // Update state:
    _state = kCBLStateStopped;
    
    // Prevent self to get released when removing from the active replications:
    CBLReplicator* repl = self;
    [_config.database unregisterActiveService: repl];
    
#if TARGET_OS_IPHONE
    [self endBackgroundingMonitor];
#endif

    CBLLogInfo(Sync, @"%@ Replicator is now stopped.", self);
}

- (void) safeBlock:(void (^)())block {
    CBL_LOCK(self) {
        block();
    }
}

// Always being called inside the lock
- (void) idled {
    Assert(_rawStatus.level == kC4Idle);
#if TARGET_OS_IPHONE
    [self endCurrentBackgroundTask];
#endif
    CBLLogInfo(Sync, @"%@ Replicator is now idled.", self);
}

#pragma mark - CBLWebSocketContext

- (nullable id<CBLCookieStore>) cookieStoreForWebsocket: (CBLWebSocket*)websocket {
    return _config.database;
}

- (nullable NSURL*) cookieURLForWebSocket: (CBLWebSocket*)websocket {
    return $castIf(CBLURLEndpoint, _config.target).url;
}

- (nullable NSString*) networkInterfaceForWebsocket: (CBLWebSocket*)websocket {
    return _config.networkInterface;
}

- (void)webSocket: (CBLWebSocket*)websocket didReceiveServerCert: (SecCertificateRef)cert {
    CBL_LOCK(self) {
        self.serverCertificate = cert;
    }
}

#pragma mark - Server Certificate

- (SecCertificateRef) serverCertificate {
    CBL_LOCK(self) {
        if (_serverCertificate != NULL) {
            CFDataRef data = SecCertificateCopyData(_serverCertificate);
            CFAutorelease(data);
            return SecCertificateCreateWithData(NULL, data);
        }
        return _serverCertificate;
    }
}

- (void) setServerCertificate: (SecCertificateRef)serverCertificate {
    CBL_LOCK(self) {
        SecCertificateRef oldCert = _serverCertificate;
        if (serverCertificate)
            _serverCertificate = (SecCertificateRef) CFRetain(serverCertificate);
        else
            _serverCertificate = NULL;
        if (oldCert)
            CFAutorelease(oldCert);
    }
}

#pragma mark - CHANGE NOTIFIERS:

- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLReplicatorChange*))listener {
    return [self addChangeListenerWithQueue: nil listener: listener];
}

- (id<CBLListenerToken>) addChangeListenerWithQueue: (dispatch_queue_t)queue
                                           listener: (void (^)(CBLReplicatorChange*))listener
{
    return [_changeNotifier addChangeListenerWithQueue: queue listener: listener delegate: self];
}

- (id<CBLListenerToken>) addDocumentReplicationListener: (void (^)(CBLDocumentReplication*))listener {
    return [self addDocumentReplicationListenerWithQueue: nil listener: listener];
}

- (id<CBLListenerToken>) addDocumentReplicationListenerWithQueue: (nullable dispatch_queue_t)queue
                                                        listener: (void (^)(CBLDocumentReplication*))listener
{
    CBL_LOCK(self) {
        [self setProgressLevel: kCBLProgressLevelPerDocument];
        return [_docReplicationNotifier addChangeListenerWithQueue: queue listener: listener delegate: self];
    }
}

- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    [_changeNotifier removeChangeListenerWithToken: token];
    
    CBL_LOCK(self) {
        if ([_docReplicationNotifier removeChangeListenerWithToken: token] == 0)
            [self setProgressLevel: kCBLProgressLevelOverall];
    }
}

#pragma mark delegate(CBLRemovableListenerToken)

- (void) removeToken: (id)token {
    [self removeChangeListenerWithToken: token];
}

- (void) setProgressLevel: (CBLReplicatorProgressLevel)level {
    _progressLevel = level;
    if (_repl) {
        BOOL success = c4repl_setProgressLevel(_repl, (C4ReplicatorProgressLevel)level, nullptr);
        assert(success);
        CBLLogVerbose(Sync, @"%@ Set ProgressLevel to LiteCore; level = %d, status = %d", self, level, success);
    }
}

#pragma mark -- Pending docIDs

- (NSSet<NSString*>*) pendingDocumentIDsForCollection: (CBLCollection *)collection
                                                error: (NSError**)error {
    CBLAssertNotNil(collection);
    
    if (_config.replicatorType > 1) {
        if (error)
            *error = [NSError errorWithDomain: CBLErrorDomain
                                         code: CBLErrorUnsupported
                                     userInfo: @{NSLocalizedDescriptionKey: kCBLErrorMessagePullOnlyPendingDocIDs}];
        return nil;
    }
    
    CBL_LOCK(self) {
        C4Error err = {};
        if (![self _setupC4Replicator: &err]) {
            convertError(err, error);
            CBLWarnError(Sync, @"%@ Replicator cannot be created: %d/%d", self, err.domain, err.code);
            return nil;
        }
    }
    
    C4Error err = {};
    C4SliceResult result = c4repl_getPendingDocIDs(_repl, collection.c4spec, &err);
    if (err.code > 0) {
        convertError(err, error);
        CBLWarnError(Sync, @"%@ Error while fetching pending documentIds: %d/%d", self, err.domain, err.code);
        return nil;
    }

    if (result.size <= 0)
        return [NSSet set];

    FLDoc doc = FLDoc_FromResultData(result, kFLTrusted, nullptr, nullslice);
    FLSliceResult_Release(result);
    
    NSArray<NSString*>* list = FLValue_GetNSObject(FLDoc_GetRoot(doc), nullptr);
    FLDoc_Release(doc);
    
    return [NSSet setWithArray: list];
}

- (NSSet<NSString*>*) pendingDocumentIDs: (NSError**)error {
    return [_config.database withDefaultCollectionForObjectAndError: error block:
                 ^id(CBLCollection* collection, NSError** err) {
        return [self pendingDocumentIDsForCollection: collection error: err];
    }];
}

- (BOOL) isDocumentPending: (NSString *)documentID
                collection: (CBLCollection *)collection
                     error: (NSError**)error {
    CBLAssertNotNil(documentID);
    CBLAssertNotNil(collection);
    
    if (_config.replicatorType > 1) {
        if (error)
            *error = [NSError errorWithDomain: CBLErrorDomain
                code: CBLErrorUnsupported
            userInfo: @{NSLocalizedDescriptionKey: kCBLErrorMessagePullOnlyPendingDocIDs}];
        return NO;
    }

    CBL_LOCK(self) {
        C4Error err = {};
        if (![self _setupC4Replicator: &err]) {
            convertError(err, error);
            CBLWarnError(Sync, @"%@ Replicator cannot be created: %d/%d", self, err.domain, err.code);
            return NO;
        }
    }
    
    C4Error err = {};
    CBLStringBytes docID(documentID);
    BOOL isPending = c4repl_isDocumentPending(_repl, docID, collection.c4spec, &err);
    if (err.code > 0) {
        convertError(err, error);
        CBLWarnError(Sync, @"%@ Error getting document pending status: %d/%d", self, err.domain, err.code);
        return false;
    }

    return isPending;
}

- (BOOL) isDocumentPending: (NSString*)documentID error: (NSError**)error {
    CBLAssertNotNil(documentID);
    
    return [_config.database withDefaultCollectionAndError: error block: ^BOOL(CBLCollection* collection, NSError** err) {
        return [self isDocumentPending: documentID collection: collection error: err];
    }];
}

#pragma mark - REACHABILITY:

- (void) initReachability: (NSURL*)remoteURL {
    if (!remoteURL || _reachability)
        return;
    
    CBLLogInfo(Sync, @"%@ Initialize reachability", self);
    NSString* hostname = remoteURL.host;
    if ([hostname isEqualToString: @"localhost"] || [hostname isEqualToString: @"127.0.0.1"])
        return;
    
    _reachability = [[CBLReachability alloc] initWithURL: remoteURL];
    __weak auto weakSelf = self;
    _reachability.onChange = ^{ [weakSelf reachabilityChanged]; };
}


- (void) startReachability {
    Assert(_state > kCBLStateStopping);
    [_reachability startOnQueue: _dispatchQueue];
}

// Should be called from _dispatchQueue
- (void) stopReachability {
    if (_reachability.isMonitoring) {
        CBLLogInfo(Sync, @"%@ Stopping Reachability ...", self);
        [_reachability stop];
    }
}

// Callback from reachability observer
- (void) reachabilityChanged {
    CBL_LOCK(self) {
        if (_reachability.isMonitoring && _reachability.reachable) {
            CBLLogInfo(Sync, @"%@ Reachability reported server may now be reachable ...", self);
            c4repl_setHostReachable(_repl, _reachability.reachable);
        }
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

// Called from statusChanged(), on the dispatch queue
- (void) c4StatusChanged: (C4ReplicatorStatus)c4Status {
    CBL_LOCK(self) {
        CBLDebug(Sync, @"%@ Received C4ReplicatorStatus Changed, status = %d (state = %d)",
                 self, c4Status.level, _state);
        
        // Record raw status:
        _rawStatus = c4Status;
        
        // Reset to notify for now:
        _deferChangeNotification = NO;
        
        if (c4Status.level == kC4Offline) {
            // When the replicator is offline, it could be either that :
            // 1. The replicator is offline as the remote server is not reachable.
            // 2. (iOS Only) The replicator is suspended as the app was backgrounding
            //    or lost the access to the database file due to the file protection
            //    level set when the screen was lock.
            // When the app went offline, start the reachability monitor to observe the
            // network changes and retry when the remote server is reachable again.
            // No reachability is started when the replicator is suspended.
            if (_state == kCBLStateSuspending) {
                _state = kCBLStateSuspended;
            } else if (_state > kCBLStateStopping) {
                _state = kCBLStateOffline;
                [self startReachability];
            }
        } else {
            // Stop the reachability monitor as the replicator is not offline anymore.
            [self stopReachability];
            
            if (c4Status.level == kC4Stopped) {
                // When the replicator is stopped, check if there are any pending conflicts
                // to be resolved. If none, the replicator will go into the stopped state,
                // and the change listeners will be notified about the stopped status.
                // Otherwise, the stopped status will be defered to notify until all pending
                // conflicts are resolved.
                if ([self hasPendingConflicts]) {
                    _state = kCBLStateStopping;
                    _deferChangeNotification = YES;
                } else {
                    [self stopped];
                }
            } else if (c4Status.level == kC4Idle) {
                // When the replicator is idle, check if there are any pending conflicts
                // to be resolved. If none, the change listeners will be notified about
                // the idle status. Otherwise, the idle status will be defered to notify
                // until all pending conflicts are resolved.
                _state = kCBLStateRunning;
                if ([self hasPendingConflicts]) {
                    _deferChangeNotification = YES;
                } else {
                    [self idled];
                }
            } else if (c4Status.level == kC4Busy) {
                _state = kCBLStateRunning;
            }
        }
        
        if (!_deferChangeNotification) {
            [self postChangeNotification];
        }
    }
}

- (void) postChangeNotification {
    NSError* error = nil;
    if (_rawStatus.error.code)
        convertError(_rawStatus.error, &error);

    CBLLogInfo(Sync, @"%@ is %s, progress %llu/%llu, error: %@",
               self, kC4ReplicatorActivityLevelNames[_rawStatus.level],
               _rawStatus.progress.unitsCompleted, _rawStatus.progress.unitsTotal, error);

    // This calls KV observers:
    self.status = [[CBLReplicatorStatus alloc] initWithStatus: _rawStatus];
    
    // This calls listeners:
    [_changeNotifier postChange: [[CBLReplicatorChange alloc] initWithReplicator: self
                                                                          status: self.status]];
}

#pragma mark - DOCUMENT REPLICATION EVENT HANDLER:

static void onDocsEnded(C4Replicator* repl,
                        bool pushing,
                        size_t nDocs,
                        const C4DocumentEnded* docEnds[],
                        void* context)
{
    auto replicator = (__bridge CBLReplicator*)context;
    
    NSMutableArray* docs = [NSMutableArray new];
    for (size_t i = 0; i < nDocs; ++i) {
        [docs addObject: [[CBLReplicatedDocument alloc] initWithC4DocumentEnded: docEnds[i]]];
    }
   
    dispatch_async(replicator->_dispatchQueue, ^{
        [replicator safeBlock:^{
            if (repl == replicator->_repl) {
                [replicator onDocsEnded: docs pushing: pushing];
            }
        }];
    });
}

// Called inside the lock
- (void) onDocsEnded: (NSArray<CBLReplicatedDocument*>*)docs pushing: (BOOL)pushing {
    NSMutableArray* posts = [NSMutableArray array];
    for (CBLReplicatedDocument *doc in docs) {
        C4Error c4err = doc.c4Error;
        if (!pushing && c4err.domain == LiteCoreDomain && c4err.code == kC4ErrorConflict) {
            [self scheduleConflictResolutionForDocument: doc];
        } else {
            [posts addObject: doc];
            [self logErrorOnDocument: doc pushing: pushing];
        }
    }
    if (posts.count > 0)
        [self postDocumentReplications: posts pushing: pushing];
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
        CBLLogInfo(Sync, @"%@ %serror %s '%@': %d/%d", self, (doc.isTransientError ? "transient " : ""),
                   (pushing ? "pushing" : "pulling"), doc.id, c4err.domain, c4err.code);
}

#pragma mark - CONFLICT RESOLUTION:

// Called inside the lock
- (void) scheduleConflictResolutionForDocument: (CBLReplicatedDocument*)doc {
    if (_conflictResolutionSuspended || _state == kCBLStateStopped) {
        return;
    }
    
    dispatch_block_t resolution = dispatch_block_create(DISPATCH_BLOCK_ASSIGN_CURRENT, ^{
        [self _resolveConflict: doc];
    });
    
    dispatch_block_notify(resolution, _dispatchQueue, ^{
        // Called when the resolution was either successful or cancelled:
        [self didFinishConflictResolution: resolution];
    });
    
    [_pendingConflicts addObject: resolution];
    
    dispatch_async(_conflictQueue, resolution);
}

// Called inside conflict resolution queue:
- (void) _resolveConflict: (CBLReplicatedDocument*)doc {
    CBL_LOCK(self) {
        if (_conflictResolutionSuspended) {
            return;
        }
    }
    
    CBLLogInfo(Sync, @"%@ Resolve conflicting version of '%@'", self, doc.id);
    
    CBLCollection* c = [_collectionMap objectForKey: $sprintf(@"%@.%@", doc.scope, doc.collection)];
    Assert(c, kCBLErrorMessageCollectionNotFoundDuringConflict);
    
    CBLCollectionConfiguration* colConfig = [_config collectionConfig: c];
    Assert(colConfig, kCBLErrorMessageConfigNotFoundDuringConflict);
    
    NSError* error = nil;
    if (![c resolveConflictInDocument: doc.id
                 withConflictResolver: colConfig.conflictResolver
                                error: &error]) {
        CBLWarn(Sync, @"%@ Conflict resolution of '%@' failed: %@", self, doc.id, error);
    }
    
    [doc updateError: error];
    [self logErrorOnDocument: doc pushing: NO];
    [self postDocumentReplications: @[doc] pushing: NO];
}

- (void) didFinishConflictResolution: (dispatch_block_t)resolution {
    CBL_LOCK(self) {
        [_pendingConflicts removeObject: resolution];
        
        if (_pendingConflicts.count == 0) {
            if (_rawStatus.level == kC4Stopped && _state == kCBLStateStopping) {
                [self stopped];
            } else if (_rawStatus.level == kC4Idle) {
                [self idled];
            }
            if (_deferChangeNotification) {
                _deferChangeNotification = NO;
                [self postChangeNotification];
            }
        }
    }
}

// Called inside the lock
- (BOOL) hasPendingConflicts {
    return _pendingConflicts.count > 0;
}

// For test to get number of pending conflicts
- (NSUInteger) pendingConflictCount {
    CBL_LOCK(self) {
        return _pendingConflicts.count > 0;
    }
}

// Called inside the lock
- (void) setConflictResolutionSuspended: (BOOL)suspended {
    _conflictResolutionSuspended = suspended;
    if (suspended) {
        // Note: All cancelled resolutions will be notified and queued again when
        // the replicator is resumed or restarted.
        for (dispatch_block_t resolution in _pendingConflicts) {
            dispatch_block_cancel(resolution);
        }
    }
}

// For test to check the suspended status
- (BOOL) conflictResolutionSuspended {
    CBL_LOCK(self) {
        return _conflictResolutionSuspended;
    }
}

#pragma mark - PUSH/PULL FILTER:

static bool pushFilter(C4CollectionSpec collectionSpec,
                       C4String docID, C4String revID, C4RevisionFlags flags,
                       FLDict flbody, void *context) {
    auto replicator = (__bridge CBLReplicator*)context;
    return [replicator filterDocument: collectionSpec docID: docID revID: revID
                                flags: flags body: flbody pushing: true];
}

static bool pullFilter(C4CollectionSpec collectionSpec,
                       C4String docID, C4String revID, C4RevisionFlags flags,
                       FLDict flbody, void *context) {
    auto replicator = (__bridge CBLReplicator*)context;
    return [replicator filterDocument: collectionSpec docID: docID revID: revID
                                flags: flags body: flbody pushing: false];
}

- (bool) filterDocument: (C4CollectionSpec)c4spec
                  docID: (C4String)docID
                  revID: (C4String)revID
                  flags: (C4RevisionFlags)flags
                   body: (FLDict)body
                pushing: (bool)pushing
{
    NSString* name = slice2string(c4spec.name);
    NSString* scopeName = slice2string(c4spec.scope);
    CBLCollection* c = [_collectionMap objectForKey: $sprintf(@"%@.%@", scopeName, name)];
    Assert(c, kCBLErrorMessageCollectionNotFoundInFilter);
    
    auto doc = [[CBLDocument alloc] initWithCollection: c
                                            documentID: slice2string(docID)
                                            revisionID: slice2string(revID)
                                                  body: body];
    CBLDocumentFlags docFlags = 0;
    if ((flags & kRevDeleted) == kRevDeleted)
        docFlags |= kCBLDocumentFlagsDeleted;
    
    if ((flags & kRevPurged) == kRevPurged)
        docFlags |= kCBLDocumentFlagsAccessRemoved;
    
    CBLCollectionConfiguration* colConfig = [_config collectionConfig: c];
    Assert(colConfig, @"Collection config is not found in the replicator config when " \
           "calling the filter function.");
    return pushing ? colConfig.pushFilter(doc, docFlags) : colConfig.pullFilter(doc, docFlags);
}

#pragma mark - BACKGROUNDING SUPPORT:

- (BOOL) active {
    CBL_LOCK(self) {
        return (_rawStatus.level == kC4Connecting || _rawStatus.level == kC4Busy || [self hasPendingConflicts]);
    }
}

- (void) setSuspended: (BOOL)suspended {
    // (iOS Only) The replicator could be suspended by the backgrounding
    // monitor either when :
    // 1. The app was in the background && the replicator was caught up
    //    (IDLE) or the background task for the replicator was expired.
    // 2. The app lost access to the database files under the lock screen
    //    as the file protection level as set to "Complete" or
    //    "Complete Unless Open".
    //
    // When the replicator is suspended, the internal replicator at
    // the LiteCore level will be stopped and the replicator status
    // will be OFFLINE (instead of stopped). Any pending conflict
    // resolution will be cancelled as best effort as any being-excuted
    // conflict resolution cannot be cancelled.
    //
    // All cancelled conflict resolutions will be notified, and put into the queue 
    // again when the replicator is resumed or is restarted.
    CBL_LOCK(self) {
        if (suspended && _state > kCBLStateSuspending) {
            // Currently not in any suspend* or stop* state:
            _state = kCBLStateSuspending;
        }
        c4repl_setSuspended(_repl, suspended);
        [self setConflictResolutionSuspended: suspended];
    }
}

@end

#pragma clang diagnostic pop
