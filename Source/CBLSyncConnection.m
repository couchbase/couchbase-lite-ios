//
//  CBLSyncConnection.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/1/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "CBLSyncConnection_Internal.h"
#import "CBLBlipReplicator.h"
#import "MYBlockUtils.h"


UsingLogDomain(Sync);


NSString* const kSyncNestedProgressKey = @"CBLChildren";


@implementation CBLSyncConnection


@synthesize syncQueue=_syncQueue, peerURL=_peerURL, state=_state, error=_error;
@synthesize pullProgress=_pullProgress, nestedPullProgress=_nestedPullProgress;
@synthesize pushProgress=_pushProgress, nestedPushProgress=_nestedPushProgress;
@synthesize remoteCheckpointDocID=_remoteCheckpointDocID, replicator=_replicator;
@synthesize onSyncAccessCheck=_onSyncAccessCheck;
#if DEBUG
@synthesize savingCheckpoint=_savingCheckpoint;  // for unit tests
#endif


- (instancetype) initWithDatabase: (CBLDatabase*)db
                       connection: (BLIPConnection*)connection
                            queue: (dispatch_queue_t)queue
{
    NSParameterAssert(db != nil);
    NSParameterAssert(queue != nil);
    self = [super init];
    if (self) {
        _syncQueue = queue;
        _db = db;
        _dbQueue = db.manager.dispatchQueue;
        Assert(_dbQueue, @"CBLManager must be on a dispatch queue");
        if (connection) {
            _connection = connection;
            [_connection setDelegate: self queue: _syncQueue];
            [_connection registerDelegateActions: @{
                @"getCheckpoint":   @"handleGetCheckpoint:",
                @"setCheckpoint":   @"handleSetCheckpoint:",
                @"subChanges":      @"handleSubscribeToChanges:",
                @"changes":         @"handleIncomingChanges:",
                @"rev":             @"handleIncomingRevision:",
                @"getAttachment":   @"handleGetAttachment:",
                @"proveAttachment": @"handleProveAttachment:"
            }];
            _peerURL = connection.URL;
            LogVerbose(Sync, @"%@ connected to socket", self);
            [self updateState: kSyncConnecting];
        }
        _changesBatchSize = kDefaultChangeBatchSize;
        _pullProgress = [NSProgress progressWithTotalUnitCount: -1]; // indeterminate
        _pushProgress = [NSProgress progressWithTotalUnitCount: -1]; // indeterminate
        __weak CBLSyncConnection* weakSelf = self;
        _updateStateSoon = MYBatchedBlock(kProgressUpdateInterval, _syncQueue,
                                           ^{[weakSelf updateState];});
        [_connection addObserver: self forKeyPath: @"active" options: 0 context: (void*)1];
    }
    return self;
}


- (void)dealloc {
    LogVerbose(Sync, @"DEALLOC %@", self);
    [_connection removeObserver: self forKeyPath: @"active"];
}


- (NSString*) description {
    NSString* verb = _pushing ? @"push" : (_pulling ? @"pull": @"from");
    return [NSString stringWithFormat: @"%@[%@ %@%@]",
            self.class, verb, _peerURL.host, _peerURL.path];
}


- (void) push: (BOOL)push pull: (BOOL)pull continuously: (BOOL)continuously {
    _pushing = push;
    _pulling = pull;
    _pushContinuousChanges = push && continuously;
    _pullContinuousChanges = pull && continuously;
}


- (void) setPushFilter: (CBLFilterBlock)filter params: (NSDictionary*)params {
    _pushFilter = filter;
    _pushFilterParams = [params copy];
}


- (void) setPullFilter: (NSString*)filterName params: (NSDictionary*)params {
    _pullFilterName = [filterName copy];
    _pullFilterParams = [params copy];
}


- (void) close {
    if (_connected && [self updateCheckpoint]) {
        _closeAfterSave = YES;      // -updateCheckpoint will close _connection after it saves
    } else {
        [_connection close];
    }
}


// If no error, returns NO. If error, closes connection and returns YES.
- (BOOL) gotError: (BLIPResponse*)response {
    NSError* error = response.error;
    if (!error)
        return NO;
    LogTo(Sync, @"Received error in %@: %@", response, error.my_compactDescription);
    self.error = error;
    [self close];
    return YES;
}


- (void) onSyncQueue: (void(^)())block {
    dispatch_async(_syncQueue, block);
}


- (void) onDatabaseQueue: (void(^)())block {
#ifdef TIME_DB_QUEUE
    CFAbsoluteTime scheduleTime = CFAbsoluteTimeGetCurrent();
    dispatch_async(_dbQueue, ^{
        CFAbsoluteTime enterTime = CFAbsoluteTimeGetCurrent();
        if (enterTime - scheduleTime > 0.01) {
            LogTo(Sync, @"** Waited %.4f sec to get onto db queue", enterTime - scheduleTime);
        }
        if (_dbQueueTime > 0) {
            NSTimeInterval idle = enterTime - _dbQueueTime;
            _dbQueueTotalIdleTime += idle;
            if (idle > 0.01)
                LogDebug(Sync, @"** DB queue was idle %.4f sec (total %.4f)",
                         idle, _dbQueueTotalIdleTime);
        }

        block();

        _dbQueueTime = CFAbsoluteTimeGetCurrent();
        _dbQueueTotalBusyTime += _dbQueueTime - enterTime;
    });
#else
    dispatch_async(_dbQueue, block);
#endif
}


// Unless specified, all the methods below must be called on the _syncQueue.


#pragma mark - STATUS & PROGRESS:


#if DEBUG
- (BOOL) active {
    return _state == kSyncActive || _state == kSyncConnecting;
}

- (id) lastSequence {
    return _pushing ? @(_localCheckpointSequence) : _remoteCheckpointSequence;
}
#endif


- (void) updateState {
    SyncState state;
    if (_revsToInsert != nil || _insertingRevs > 0)
        state = kSyncActive;
    else if (!_connection)
        state = kSyncStopped;
    else if (!_connected)
        state = kSyncConnecting;
    else if (_pullCatchingUp
                || _awaitingRevs > 0
                || _changeListsInFlight > 0
                || _connection.active)
        state = kSyncActive;
    else
        state = kSyncIdle;
#if 0
    LogTo(Sync, @"_pullCatchingUp=%d, _revsToInsert=%lu, _insertingRevs=%lu, _awaitingRevs=%lu, _changeListsInFlight=%lu, _connection.active=%d",
          _pullCatchingUp, _revsToInsert.count, _insertingRevs, _awaitingRevs, _changeListsInFlight, _connection.active);
#endif
    [self updateState: state];
}

- (void) updateState: (SyncState)state {
    __unused static const char* kStateNames[] = {"Stopped", "Connecting", "Idle", "Active"};
    if (state != self.state) {
        LogTo(Sync, @"SyncConnection.state = kSync%s", kStateNames[state]);
#ifdef TIME_DB_QUEUE
        if (state == kSyncIdle) {
            Log(@"** DB queue was busy %.3f sec (inserting %.3f sec), idle %.3f sec, total %.3f sec **",
                  _dbQueueTotalBusyTime, _dbQueueTotalInsertTime, _dbQueueTotalIdleTime,
                  _dbQueueTotalBusyTime+_dbQueueTotalIdleTime);
        }
#endif
        self.state = state;
    }
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    if (context == (void*)1) {  // _connection.active changed
        _updateStateSoon();
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


- (NSProgress*) addAttachmentProgressWithName: (NSString*)name
                                       length: (uint64_t)length
                                      pulling: (BOOL)pulling
{
    NSDictionary* userInfo = @{
        NSProgressFileOperationKindKey: (pulling ?NSProgressFileOperationKindDownloading
                                                     :NSProgressFileOperationKindCopying),
        NSProgressFileTotalCountKey: @1,
        NSProgressFileURLKey: [NSURL fileURLWithPath: name]
    };
    NSProgress* parent = pulling ? _pullProgress : _pushProgress;
    NSProgress* attProgress = [[NSProgress alloc] initWithParent: parent
                                                        userInfo: userInfo];
    attProgress.totalUnitCount = length;
    attProgress.kind = NSProgressKindFile;

    NSUInteger nFiles = [parent.userInfo[NSProgressFileTotalCountKey] unsignedIntegerValue];
    [parent setUserInfoObject: @(nFiles+1) forKey: NSProgressFileTotalCountKey];
    NSArray* children = parent.userInfo[kSyncNestedProgressKey];
    children = children ? [children arrayByAddingObject: attProgress] : @[attProgress];
    [parent setUserInfoObject: children forKey: kSyncNestedProgressKey];

    if (pulling)
        self.nestedPullProgress = children;
    else
        self.nestedPushProgress = children;
    return attProgress;
}


- (void) removeAttachmentProgress: (NSProgress*)attProgress
                          pulling: (BOOL)pulling
{
    attProgress.completedUnitCount = attProgress.totalUnitCount;
    NSUInteger nFiles = [_pullProgress.userInfo[NSProgressFileCompletedCountKey] unsignedIntegerValue];
    [_pullProgress setUserInfoObject: @(nFiles+1) forKey: NSProgressFileCompletedCountKey];

    NSProgress* parent = pulling ? _pullProgress : _pushProgress;
    NSMutableArray* children = [parent.userInfo[kSyncNestedProgressKey] mutableCopy];
    [children removeObjectIdenticalTo: attProgress];
    if (pulling)
        self.nestedPullProgress = children;
    else
        self.nestedPushProgress = children;
    [parent setUserInfoObject: children forKey: kSyncNestedProgressKey];
}


- (BOOL) accessCheckForRequest: (BLIPRequest*)request {
    if (self.onSyncAccessCheck) {
        CBLStatus status = self.onSyncAccessCheck(request);
        if (CBLStatusIsError(status)) {
            NSString* message;
            int code = CBLStatusToHTTPStatus(status, &message);
            [request respondWithErrorCode: code message: message];
            return NO;
        }
    }
    return YES;
}


#pragma mark - BLIP WEB SOCKET DELEGATE:


- (BOOL)blipConnection: (BLIPConnection*)connection
   validateServerTrust: (SecTrustRef)trust
{
    return [_replicator validateServerTrust: trust];
}


- (void)blipConnectionDidOpen:(BLIPConnection*)connection {
    LogTo(Sync, @"OPENED %@", connection);
    _connected = YES;
    // If in active mode, start off by getting the remote checkpoint:
    if (_pushing || _pulling)
        [self getCheckpoint];
    [self updateState];
}


- (void)blipConnection: (BLIPConnection*)connection didFailWithError:(NSError *)error {
    LogTo(Sync, @"FAILED %@: %@", connection, error.my_compactDescription);
    self.error = error;
    [self closed];
}


- (void)blipConnection: (BLIPConnection*)connection
    didCloseWithError: (NSError*)error
{
    if (error) {
        LogTo(Sync, @"CLOSED %@ (%@)", connection, error.my_compactDescription);
        self.error = error;
    } else {
        LogTo(Sync, @"CLOSED %@", connection);
    }
    [self closed];
}


- (void) closed {
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: kCBLDatabaseChangeNotification
                                                  object: _db];
    [_connection removeObserver: self forKeyPath: @"active"];
    _connected = NO;
    _connection = nil;

#if PARALLEL_INSERTS
    if (_insertDB && _insertDB != _db) {
        [_insertDB.manager close];
        _insertDB = nil;
        _insertDBQueue = nil;
    }
#endif

    [self updateState];
}


@end
