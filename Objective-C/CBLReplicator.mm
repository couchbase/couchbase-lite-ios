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
#import "CBLCollectionConfiguration+Internal.h"
#import "CBLCollection+Internal.h"
#import "CBLDocumentReplication+Internal.h"
#import "CBLReplicator+Internal.h"
#import "CBLReplicatorChange+Internal.h"
#import "CBLReplicatorConfiguration.h"
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

#import "c4Replicator.h"
#import "c4Socket.h"
#import "CBLWebSocket.h"
#import "fleece/Fleece.hh"
#import <algorithm>

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

@interface CBLReplicator () <CBLLockable, CBLRemovableListenerToken>
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
    NSURL* _reachabilityURL;
    CBLReachability* _reachability;
    CBLReplicatorProgressLevel _progressLevel;
    CBLChangeNotifier<CBLReplicatorChange*>* _changeNotifier;
    CBLChangeNotifier<CBLDocumentReplication*>* _docReplicationNotifier;
    BOOL _resetCheckpoint;          // Reset the replicator checkpoint
    unsigned _conflictCount;        // Current number of conflict resolving tasks
    BOOL _deferReplicatorNotification; // Defer replicator notification until finishing all conflict resolving tasks
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
        NSParameterAssert(config.database != nil && config.target != nil);
        _config = [[CBLReplicatorConfiguration alloc] initWithConfig: config readonly: YES];
        _progressLevel = kCBLProgressLevelOverall;
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

- (void) dealloc {
    [self stopReachability];
    
    // Free C4Replicator:
    c4repl_free(_repl);
    
    // Release server cert if available:
    self.serverCertificate = NULL;
}

- (NSString*) description {
    if (!_desc)
        _desc = $sprintf(@"%@[%s%s%s %@]",
                         self.class,
                         (isPull(_config.replicatorType) ? "<" : ""),
                         (_config.continuous ? "*" : "-"),
                         (isPush(_config.replicatorType)  ? ">" : ""),
                         _config.target);
    return _desc;
}

- (void) start {
    [self startWithReset: NO];
}

- (void) startWithReset: (BOOL)reset {
    CBL_LOCK(self) {
        CBLLogInfo(Sync, @"%@: Starting ...", self);
        if (_state != kCBLStateStopped && _state != kCBLStateSuspended) {
            CBLWarn(Sync, @"%@: Replicaator has already been started (state = %d, status = %d); ignored.",
                    self,  _state, _rawStatus.level);
            return;
        }
        
        C4ReplicatorStatus status;
        C4Error err;
        if ([self _setupC4Replicator: &err]) {
            // Start the C4Replicator:
            self.serverCertificate = NULL;
            _state = kCBLStateStarting;
            c4repl_start(_repl, reset);
            status = c4repl_getStatus(_repl);
            [_config.database addActiveStoppable: self];
            
#if TARGET_OS_IPHONE
            if (!_config.allowReplicatingInBackground)
                [self setupBackgrounding];
#endif
        } else {
            // Failed to create C4Replicator:
            NSError *error = nil;
            convertError(err, &error);
            CBLWarnError(Sync, @"%@: Replicator cannot be created: %@",
                         self, error.localizedDescription);
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
        c4repl_setOptions(_repl, self._encodedOptions);
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
    alloc_slice optionsFleece = self._encodedOptions;
    C4ReplicatorParameters params = {
// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        .pushFilter = filter(_config.pushFilter, true),
        .validationFunc = filter(_config.pullFilter, false),
#pragma clang diagnostic pop
        
        .optionsDictFleece = optionsFleece,
        .onStatusChanged = &statusChanged,
        .onDocumentsEnded = &onDocsEnded,
        .callbackContext = (__bridge void*)self,
        .socketFactory = &socketFactory,
    };
    
    NSUInteger collectionCount = _config.collectionConfigs.count;
    C4ReplicationCollection cols[collectionCount];
    NSUInteger i = 0;
    for (CBLCollection* col in _config.collectionConfigs) {
        CBLCollectionConfiguration* colConfig = _config.collectionConfigs[col];
        AllocedDict dict = [self encodedCollectionOptions: colConfig];
        C4ReplicationCollection c = {
            .collection = col.c4spec,
            .push = mkmode(isPush(_config.replicatorType), _config.continuous),
            .pull = mkmode(isPull(_config.replicatorType), _config.continuous),
            .pushFilter = filter(_config.pushFilter, true),
            .pullFilter = filter(_config.pullFilter, false),
            .callbackContext    = (__bridge void*)col,
            .optionsDictFleece  = dict.toString(),
        };
        cols[i++] = c;
    }
    params.collectionCount = collectionCount;
    params.collections = cols;
    
    [self initReachability: _reachabilityURL];
    
    [self createCollectionMap];

    // Create a C4Replicator:
    [_config.database safeBlock: ^{
        [_config.database mustBeOpenLocked];
        
        if (remoteURL || !otherDB)
            _repl = c4repl_new(_config.database.c4db, addr, dbName, params, outErr);
        else  {
#ifdef COUCHBASE_ENTERPRISE
            if (otherDB) {
                [otherDB safeBlock: ^{
                    [otherDB mustBeOpenLocked];
                    
                    _repl = c4repl_newLocal(_config.database.c4db, otherDB.c4db, params, outErr);
                }];
            }
#else
            Assert(remoteURL, @"Endpoint has no URL");
#endif
        }
    }];

    return (_repl != nullptr);
}

- (AllocedDict) encodedCollectionOptions: (CBLCollectionConfiguration*)config {
    NSMutableDictionary* mdict = [config.effectiveOptions mutableCopy];
    Encoder enc;
    enc << mdict;
    return AllocedDict(enc.finish());
}

- (alloc_slice) _encodedOptions {
    NSMutableDictionary* options = [_config.effectiveOptions mutableCopy];
    Encoder enc;
    enc << options;
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
            CBLWarn(Sync, @"%@: Replicator has been stopped or is stopping (state = %d, status = %d); ignore stop.",
                    self,  _state, _rawStatus.level);
            return;
        }
        
        CBLLogInfo(Sync, @"%@: Stopping...", self);
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
    [_config.database removeActiveStoppable: repl];
    
    CBLLogInfo(Sync, @"%@: Replicator is now stopped.", self);
}

- (void) safeBlock:(void (^)())block {
    CBL_LOCK(self) {
        block();
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
    return [_changeNotifier addChangeListenerWithQueue: queue listener: listener delegate: nil];
}

- (id<CBLListenerToken>) addDocumentReplicationListener: (void (^)(CBLDocumentReplication*))listener {
    return [self addDocumentReplicationListenerWithQueue: nil listener: listener];
}

- (id<CBLListenerToken>) addDocumentReplicationListenerWithQueue: (nullable dispatch_queue_t)queue
                                                        listener: (void (^)(CBLDocumentReplication*))listener
{
    CBL_LOCK(self) {
        [self setProgressLevel: kCBLProgressLevelPerDocument];
        return [_docReplicationNotifier addChangeListenerWithQueue: queue listener: listener delegate: nil];
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
        CBLLogVerbose(Sync, @"%@: setProgressLevel to LiteCore; level = %d, status = %d", self, level, success);
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
            CBLWarnError(Sync, @"%@: Replicator cannot be created: %d/%d", self, err.domain, err.code);
            return nil;
        }
    }
    
    C4Error err = {};
    C4SliceResult result = c4repl_getPendingDocIDs(_repl, collection.c4spec, &err);
    if (err.code > 0) {
        convertError(err, error);
        CBLWarnError(Sync, @"Error while fetching pending documentIds: %d/%d", err.domain, err.code);
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
    return [self pendingDocumentIDsForCollection: [_config.database defaultCollectionOrThrow]
                                           error: error];
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
            CBLWarnError(Sync, @"%@: Replicator cannot be created: %d/%d", self, err.domain, err.code);
            return NO;
        }
    }
    
    C4Error err = {};
    CBLStringBytes docID(documentID);
    BOOL isPending = c4repl_isDocumentPending(_repl, docID, collection.c4spec, &err);
    if (err.code > 0) {
        convertError(err, error);
        CBLWarnError(Sync, @"Error getting document pending status: %d/%d", err.domain, err.code);
        return false;
    }

    return isPending;
}

- (BOOL) isDocumentPending: (NSString*)documentID error: (NSError**)error {
    CBLAssertNotNil(documentID);
    
    return [self isDocumentPending: documentID
                        collection: [_config.database defaultCollectionOrThrow]
                             error: error];
}

#pragma mark - REACHABILITY:

- (void) initReachability: (NSURL*)remoteURL {
    if (!remoteURL || _reachability)
        return;
    
    CBLLogInfo(Sync, @"%@: Initialize reachability", self);
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
        CBLLogInfo(Sync, @"%@: Stopping Reachability ...", self);
        [_reachability stop];
    }
}

// Callback from reachability observer
- (void) reachabilityChanged {
    CBL_LOCK(self) {
        if (_reachability.isMonitoring && _reachability.reachable) {
            CBLLogInfo(Sync, @"%@: Reachability reported server may now be reachable ...", self);
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
        CBLDebug(Sync, @"%@: Received C4ReplicatorStatus Changed, status = %d (state = %d)",
                 self, c4Status.level, _state);
        
        // Record raw status:
        _rawStatus = c4Status;
        
        // Running; idle or busy:
        if (c4Status.level > kC4Connecting) {
            if (_state == kCBLStateStarting) {
                _state = kCBLStateRunning;
            }
            [self stopReachability];
        }
        
        // Offline / suspending:
        if (c4Status.level == kC4Offline) {
            if (_state == kCBLStateSuspending) {
                _state = kCBLStateSuspended;
            } else if (_state > kCBLStateStopping) {
                _state = kCBLStateOffline;
                [self startReachability];
            }
        }
        
        // Stopped:
        if (c4Status.level == kC4Stopped) {
            [self stopReachability];
        #if TARGET_OS_IPHONE
            [self endBackgrounding];
        #endif
            
            if (_conflictCount == 0)
                [self stopped];
        }

        // replicator status callback
        /// stopped and idle state, we will defer status callback till conflicts finish resolving
        if (_conflictCount > 0 && (c4Status.level == kC4Stopped || c4Status.level == kC4Idle)) {
            CBLLogInfo(Sync, @"%@: Status = %d, but waiting for conflict resolution (pending = %d) "
            "to finish before notifying.", self, c4Status.level, _conflictCount);
            
            _deferReplicatorNotification = YES;
            if (c4Status.level == kC4Stopped)
                _state = kCBLStateStopping;
        } else
            _deferReplicatorNotification = NO;
        
        if (!_deferReplicatorNotification)
            [self updateAndPostStatus];

    #if TARGET_OS_IPHONE
        //  End the current background task when the replicator is idle:
        if (c4Status.level == kC4Idle)
            [self endCurrentBackgroundTask];
    #endif
    }
}

- (void) updateAndPostStatus {
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

#pragma mark - DOCUMENT-LEVEL 0:

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
            if (--_conflictCount == 0 && _deferReplicatorNotification) {
                if (_rawStatus.level == kC4Stopped) {
                    Assert(_state == kCBLStateStopping);
                    [self stopped];
                }
                
                _deferReplicatorNotification = NO;
                [self updateAndPostStatus];
            }
        }
    });
}

- (void) _resolveConflict: (CBLReplicatedDocument*)doc {
    CBLLogInfo(Sync, @"%@: Resolve conflicting version of '%@'", self, doc.id);
    NSError* error = nil;
    CBLCollection* collection = nil;
    if (doc.collection) {
        collection = [_collectionMap objectForKey: $sprintf(@"%@.%@", doc.scope, doc.collection)];
        if (!collection) {
            CBLWarn(Sync, @"%@ Cannot retrieve collection=%@.%@ error=%@ docID=%@", self,
                    doc.scope, doc.collection, error, doc.id);
            return;
        }
    } else {
        collection = [_config.database defaultCollectionOrThrow];
    }
    
    if (![collection resolveConflictInDocument: doc.id
                          withConflictResolver: _config.conflictResolver
                                         error: &error]) {
        CBLWarn(Sync, @"%@: Conflict resolution of '%@' failed: %@", self, doc.id, error);
    }
    
    [doc updateError: error];
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
    CBLCollection* collection = nil;
    if (c4spec.name.buf) {
        NSError* error = nil;
        NSString* name = slice2string(c4spec.name);
        NSString* scopeName = slice2string(c4spec.scope);
        collection = [_collectionMap objectForKey: $sprintf(@"%@.%@", scopeName, name)];
        if (!collection) {
            CBLWarn(Sync, @"%@ Filter(push=%d) cannot retrieve collection=%@.%@ error=%@ doc=%@",
                    self, pushing, scopeName, name, error, slice2string(docID));
            return NO;
        }
    } else {
        collection = [_config.database defaultCollectionOrThrow];
    }
    
    auto doc = [[CBLDocument alloc] initWithCollection: collection
                                            documentID: slice2string(docID)
                                            revisionID: slice2string(revID)
                                                  body: body];
    CBLDocumentFlags docFlags = 0;
    if ((flags & kRevDeleted) == kRevDeleted)
        docFlags |= kCBLDocumentFlagsDeleted;
    
    if ((flags & kRevPurged) == kRevPurged)
        docFlags |= kCBLDocumentFlagsAccessRemoved;

// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return pushing ? _config.pushFilter(doc, docFlags) : _config.pullFilter(doc, docFlags);
#pragma clang diagnostic pop

}

#pragma mark - BACKGROUNDING SUPPORT:

- (BOOL) active {
    CBL_LOCK(self) {
        return (_rawStatus.level == kC4Connecting || _rawStatus.level == kC4Busy);
    }
}

- (void) setSuspended: (BOOL)suspended {
    CBL_LOCK(self) {
        c4repl_setSuspended(_repl, suspended);
    }
}

@end

#pragma mark - CBLReplicatorStatus:

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

#pragma clang diagnostic pop
