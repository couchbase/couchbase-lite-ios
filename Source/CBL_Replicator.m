//
//  CBL_Replicator.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_Replicator.h"
#import "CBL_Pusher.h"
#import "CBL_Puller.h"
#import "CBLDatabase+Replication.h"
#import "CBLRemoteRequest.h"
#import "CBLAuthorizer.h"
#import "CBLBatcher.h"
#import "CBLReachability.h"
#import "CBL_URLProtocol.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "CBLMisc.h"
#import "CBLBase64.h"
#import "CBJSONEncoder.h"
#import "CBLCookieStorage.h"
#import "MYBlockUtils.h"
#import "MYURLUtils.h"
#import "MYAnonymousIdentity.h"


#define kProcessDelay 0.5
#define kInboxCapacity 100

#define kRetryDelay 60.0

#define kDefaultRequestTimeout 60.0


NSString* CBL_ReplicatorProgressChangedNotification = @"CBL_ReplicatorProgressChanged";
NSString* CBL_ReplicatorStoppedNotification = @"CBL_ReplicatorStopped";


#if TARGET_OS_IPHONE
@interface CBL_Replicator (Backgrounding)
- (void) setupBackgrounding;
- (void) endBackgrounding;
- (void) okToEndBackgrounding;
@end
#endif


@interface CBL_Replicator () <CBLRemoteRequestDelegate>
@property (readwrite, nonatomic) BOOL running, active;
@property (readwrite, copy) NSDictionary* remoteCheckpoint;
- (void) updateActive;
- (void) fetchRemoteCheckpointDoc;
- (void) saveLastSequence;
@end


@implementation CBL_Replicator
{
    BOOL _running, _online, _active;
    BOOL _lastSequenceChanged;
    NSString* _sessionID;
    unsigned _revisionsFailed;
    NSError* _error;
    NSThread* _thread;
    NSString* _remoteCheckpointDocID;
    NSDictionary* _remoteCheckpoint;
    BOOL _savingCheckpoint, _overdueForSave;
    NSMutableArray* _remoteRequests;
    int _asyncTaskCount;
    NSUInteger _changesProcessed, _changesTotal;
    CFAbsoluteTime _startTime;
    CBLReachability* _host;
    BOOL _suspended;
    SecCertificateRef _serverCert;
    NSData* _pinnedCertData;
}

@synthesize revisionBodyTransformationBlock=_revisionBodyTransformationBlock;

+ (NSString *)progressChangedNotification
{
    return CBL_ReplicatorProgressChangedNotification;
}

+ (NSString *)stoppedNotification
{
    return CBL_ReplicatorStoppedNotification;
}


- (instancetype) initWithDB: (CBLDatabase*)db
                     remote: (NSURL*)remote
                       push: (BOOL)push
                 continuous: (BOOL)continuous
{
    NSParameterAssert(db);
    NSParameterAssert(remote);
    
    // CBL_Replicator is an abstract class; instantiating one actually instantiates a subclass.
    if ([self class] == [CBL_Replicator class]) {
        Class klass = push ? [CBL_Pusher class] : [CBL_Puller class];
        return [[klass alloc] initWithDB: db remote: remote push: push continuous: continuous];
    }
    
    self = [super init];
    if (self) {
        _db = db;
        _remote = remote;
        _continuous = continuous;
        Assert(push == self.isPush);

        _cookieStorage = [[CBLCookieStorage alloc] initWithDB: db
                                                   storageKey: self.remoteCheckpointDocID];

        static int sLastSessionID = 0;
        _sessionID = [$sprintf(@"repl%03d", ++sLastSessionID) copy];
#if TARGET_OS_IPHONE
        // Keeps static analyzer from complaining this ivar is unused:
        _bgTask = 0;
#endif
    }
    return self;
}


- (void)dealloc {
    [self stop];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_host stop];
    cfrelease(_serverCert);
}


- (void) clearDbRef {
    // If we're in the middle of saving the checkpoint and waiting for a response, by the time the
    // response arrives _db will be nil, so there won't be any way to save the checkpoint locally.
    // To avoid that, pre-emptively save the local checkpoint now.
    if (_savingCheckpoint && _lastSequence)
        [_db setLastSequence: _lastSequence.description withCheckpointID: self.remoteCheckpointDocID];
    _db = nil;
}


- (void) clearCookieStorageRef {
    // Explicitly clear the reference to the storage to ensure that the cookie storage will
    // get dealloc and the database referenced inside the storage will get cleared as well.
    _cookieStorage = nil;
}


- (void) databaseClosing {
    [self saveLastSequence];
    [self stop];
    [self clearDbRef];
    [self clearCookieStorageRef];
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _remote.my_sanitizedString);
}


@synthesize db=_db, remote=_remote, filterName=_filterName, filterParameters=_filterParameters, docIDs = _docIDs;
@synthesize running=_running, online=_online, active=_active, continuous=_continuous;
@synthesize error=_error, sessionID=_sessionID, options=_options;
@synthesize changesProcessed=_changesProcessed, changesTotal=_changesTotal;
@synthesize remoteCheckpoint=_remoteCheckpoint;
@synthesize authorizer=_authorizer;
@synthesize requestHeaders = _requestHeaders;
@synthesize serverCert=_serverCert;
@synthesize cookieStorage = _cookieStorage;


- (BOOL) isPush {
    return NO;  // guess who overrides this?
}


- (bool) hasSameSettingsAs: (CBL_Replicator*)other {
    // Needs to be consistent with -remoteCheckpointDocID:
    // If a.remoteCheckpointID == b.remoteCheckpointID then [a hasSameSettingsAs: b]
    return _db == other->_db && $equal(_remote, other->_remote) && self.isPush == other.isPush
        && $equal(self.remoteCheckpointDocID, other.remoteCheckpointDocID);
}


- (NSString*) lastSequence {
    return _lastSequence;
}

- (void) setLastSequence:(NSString*)lastSequence {
    if (!$equal(lastSequence, _lastSequence)) {
        LogTo(SyncVerbose, @"%@: Setting lastSequence to %@ (from %@)",
              self, lastSequence, _lastSequence);
        _lastSequence = [lastSequence copy];
        if (!_lastSequenceChanged) {
            _lastSequenceChanged = YES;
            [self performSelector: @selector(saveLastSequence) withObject: nil afterDelay: 5.0];
        }
    }
}


- (void) postProgressChanged {
    LogTo(SyncVerbose, @"%@: postProgressChanged (%u/%u, active=%d (batch=%u, net=%u), online=%d)",
          self, (unsigned)_changesProcessed, (unsigned)_changesTotal,
          _active, (unsigned)_batcher.count, _asyncTaskCount, _online);
    NSNotification* n = [NSNotification notificationWithName: CBL_ReplicatorProgressChangedNotification
                                                      object: self];
    [[NSNotificationQueue defaultQueue] enqueueNotification: n
                                               postingStyle: NSPostASAP
                                               coalesceMask: NSNotificationCoalescingOnSender |
                                                             NSNotificationCoalescingOnName
                                                   forModes: nil];
}


- (NSDictionary*) activeTaskInfo {
    // For schema, see http://wiki.apache.org/couchdb/HttpGetActiveTasks
    NSString* source = self.remote.absoluteString;
    NSString* target = _db.name;
    if (self.isPush) {
        NSString* temp = source;
        source = target;
        target = temp;
    }
    NSString* status;
    id progress = nil;
    if (!self.running) {
        status = @"Stopped";
    } else if (!self.online) {
        status = @"Offline";        // nonstandard
    } else if (!self.active) {
        status = @"Idle";           // nonstandard
    } else {
        NSUInteger processed = self.changesProcessed;
        NSUInteger total = self.changesTotal;
        status = $sprintf(@"Processed %u / %u changes",
                          (unsigned)processed, (unsigned)total);
        progress = (total>0) ? @(lroundf(100*(processed / (float)total))) : nil;
    }
    NSArray* error = nil;
    NSError* errorObj = self.error;
    if (errorObj)
        error = @[@(errorObj.code), errorObj.localizedDescription];

    NSArray* activeRequests = [_remoteRequests my_map: ^id(CBLRemoteRequest* request) {
        return request.statusInfo;
    }];
    
    return $dict({@"type", @"Replication"},
                 {@"task", self.sessionID},
                 {@"source", source},
                 {@"target", target},
                 {@"continuous", (self.continuous ? $true : nil)},
                 {@"status", status},
                 {@"progress", progress},
                 {@"x_active_requests", activeRequests},
                 {@"error", error});
}


- (void) setChangesProcessed: (NSUInteger)processed {
    if (WillLogTo(Sync)) {
        if (processed/100 != _changesProcessed/100
                    || (processed == _changesTotal && _changesTotal > 0))
            LogTo(Sync, @"%@ Progress: %lu / %lu",
                  self, (unsigned long)processed, (unsigned long)_changesTotal);
    }
    if ((NSInteger)processed < 0)
        Warn(@"Suspicious changesProcessed value: %llu", (UInt64)processed);
    _changesProcessed = processed;
    [self postProgressChanged];
}

- (void) setChangesTotal: (NSUInteger)total {
    if (WillLogTo(Sync) && total/100 != _changesTotal/100) {
        LogTo(Sync, @"%@ Progress: %lu / %lu",
              self, (unsigned long)_changesProcessed, (unsigned long)total);
    }
    if ((NSInteger)total < 0)
        Warn(@"Suspicious changesTotal value: %llu", (UInt64)total);
    _changesTotal = total;
    [self postProgressChanged];
}

- (void) setError:(NSError *)error {
    if (error.code == NSURLErrorCancelled && $equal(error.domain, NSURLErrorDomain))
        return;
    
    if (_error != error)
    {
        LogTo(Sync, @"%@ Progress: set error = %@", self, error.localizedDescription);
        _error = error;
        if (CBLIsPermanentError(error))
            [self stop];
        else
            [self postProgressChanged];
    }
}


- (void) start {
    if (_running)
        return;
    CBLDatabase* db = _db;
    Assert(db, @"Can't restart an already stopped CBL_Replicator");
    LogTo(Sync, @"%@ STARTING ...", self);

    [db addActiveReplicator: self];

    // Did client request a reset (i.e. starting over from first sequence?)
    if (_options[kCBLReplicatorOption_Reset] != nil) {
        [db setLastSequence: nil withCheckpointID: self.remoteCheckpointDocID];
    }

    id digest = _options[kCBLReplicatorOption_PinnedCert];
    if (digest) {
        if ([digest isKindOfClass: [NSData class]])
            _pinnedCertData = digest;
        else if ([digest isKindOfClass: [NSString class]])
            _pinnedCertData = CBLDataFromHex(digest);
        if (_pinnedCertData.length != 20)
            Warn(@"Invalid replicator %@ property value \"%@\"",
                 kCBLReplicatorOption_PinnedCert, digest);
    }

    // Note: This is actually a ref cycle, because the block has a (retained) reference to 'self',
    // and _batcher retains the block, and of course I retain _batcher.
    // The cycle is broken in -stopped when I release _batcher.
    _batcher = [[CBLBatcher alloc] initWithCapacity: kInboxCapacity delay: kProcessDelay
                 processor:^(NSArray *inbox) {
                     LogTo(SyncVerbose, @"*** %@: BEGIN processInbox (%u sequences)",
                           self, (unsigned)inbox.count);
                     CBL_RevisionList* revs = [[CBL_RevisionList alloc] initWithArray: inbox];
                     [self processInbox: revs];
                     LogTo(SyncVerbose, @"*** %@: END processInbox (lastSequence=%@)", self, _lastSequence);
                     [self updateActive];
                 }
                ];

    // If client didn't set an authorizer, use basic auth if credential is available:
    if (!_authorizer) {
        _authorizer = [[CBLBasicAuthorizer alloc] initWithURL: _remote];
        if (_authorizer)
            LogTo(SyncVerbose, @"%@: Found credential, using %@", self, _authorizer);
    }

    self.running = YES;
    _startTime = CFAbsoluteTimeGetCurrent();
    
#if TARGET_OS_IPHONE
    [self setupBackgrounding];
#endif
    
    _online = NO;
    if (!_continuous || [NSClassFromString(@"CBL_URLProtocol") handlesURL: _remote]) {
        [self goOnline];    // non-continuous or local-to-local replication
    } else {
        // Start reachability checks. (This creates another ref cycle, because
        // the block also retains a ref to self. Cycle is also broken in -stopped.)
        _host = [[CBLReachability alloc] initWithHostName: _remote.host];
        
        __weak id weakSelf = self;
        _host.onChange = ^{
            CBL_Replicator *strongSelf = weakSelf;
            [strongSelf reachabilityChanged:strongSelf->_host];
        };
        [_host start];
        [self reachabilityChanged: _host];
    }
}


- (void) beginReplicating {
    // Subclasses implement this
}


- (void) stop {
    if (!_running)
        return;
    [_batcher clear];   // no sense processing any pending changes
    _continuous = NO;
    [self stopRemoteRequests];
    [NSObject cancelPreviousPerformRequestsWithTarget: self
                                             selector: @selector(retryIfReady) object: nil];
    if (_running && _asyncTaskCount == 0)
        [self stopped];
}


- (void) stopped {
    LogTo(Sync, @"%@ STOPPED", self);
    Log(@"Replication: %@ took %.3f sec; error=%@",
        self, CFAbsoluteTimeGetCurrent()-_startTime, _error);
#if TARGET_OS_IPHONE
    [self endBackgrounding];
#endif
    self.running = NO;
    [[NSNotificationCenter defaultCenter]
        postNotificationName: CBL_ReplicatorStoppedNotification object: self];
    [self saveLastSequence];
    
    _batcher = nil;
    [_host stop];
    _host = nil;
    _suspended = NO;
    self.revisionBodyTransformationBlock = nil;
    [self clearDbRef];  // _db no longer tracks me so it won't notify me when it closes; clear ref now
}


// Called after a continuous replication has gone idle, but it failed to transfer some revisions
// and so wants to try again in a minute. Can be overridden by subclasses.
- (void) retry {
    self.error = nil;
    [self checkSession];
}

- (void) retryIfReady {
    if (!_running)
        return;

    if (_online) {
        LogTo(Sync, @"%@ RETRYING, to transfer missed revisions...", self);
        _revisionsFailed = 0;
        [NSObject cancelPreviousPerformRequestsWithTarget: self
                                                 selector: @selector(retryIfReady) object: nil];
        [self retry];
    } else {
        [self performSelector: @selector(retryIfReady) withObject: nil afterDelay: kRetryDelay];
    }
}


- (BOOL) goOffline {
    if (!_online)
        return NO;
    LogTo(Sync, @"%@: Going offline", self);
    _online = NO;
    [self stopRemoteRequests];
    [self postProgressChanged];
    return YES;
}


- (BOOL) goOnline {
    if (_online)
        return NO;
    LogTo(Sync, @"%@: Going online", self);
    _online = YES;

    if (_running) {
        _lastSequence = nil;
        self.error = nil;

        [self checkSession];
        [self postProgressChanged];
    }
    return YES;
}


- (void) reachabilityChanged: (CBLReachability*)host {
    LogTo(Sync, @"%@: Reachability state = %@ (%02X), suspended=%d",
          self, host, host.reachabilityFlags, _suspended);

    BOOL reachable = host.reachable && !_suspended;
    if (reachable) {
    // Parse "network" option. Could be nil or "WiFi" or "!Wifi" or "cell" or "!cell".
    NSString* network = [$castIf(NSString, _options[kCBLReplicatorOption_Network])
                              lowercaseString];
        if (network) {
            BOOL wifi = host.reachableByWiFi;
            if ($equal(network, @"wifi") || $equal(network, @"!cell"))
                reachable = wifi;
            else if ($equal(network, @"cell") || $equal(network, @"!wifi"))
                reachable = !wifi;
            else
                Warn(@"Unrecognized replication option \"network\"=\"%@\"", network);
        }
    }

    if (reachable)
        [self goOnline];
    else if (host.reachabilityKnown || _suspended)
        [self goOffline];
}

- (BOOL) suspended {
    return _suspended;
}

// When suspended, the replicator acts as though it's offline, stopping all network activity.
// This is used by the iOS backgrounding support (see CBLReplication+Backgrounding.m)
- (void) setSuspended: (BOOL)suspended {
    if (suspended != _suspended) {
        _suspended = suspended;
        [self reachabilityChanged: _host];
    }
}


- (void) updateActive {
    BOOL active = _batcher.count > 0 || _asyncTaskCount > 0;
    if (active != _active) {
        LogTo(Sync, @"%@ Progress: set active = %d", self, active);
        self.active = active;
        [self postProgressChanged];
        if (!_active) {
            // Replicator is now idle. If it's not continuous, stop.
#if TARGET_OS_IPHONE
            [self okToEndBackgrounding];
#endif
            if (!_continuous) {
                [self stopped];
            } else if (_error) /*(_revisionsFailed > 0)*/ {
                LogTo(Sync, @"%@: Failed to xfer %u revisions; will retry in %g sec",
                      self, _revisionsFailed, kRetryDelay);
                [NSObject cancelPreviousPerformRequestsWithTarget: self
                                                         selector: @selector(retryIfReady)
                                                           object: nil];
                [self performSelector: @selector(retryIfReady)
                           withObject: nil afterDelay: kRetryDelay];
            }
        }
    }
}


- (void) asyncTaskStarted {
    if (_asyncTaskCount++ == 0)
        [self updateActive];
}


- (void) asyncTasksFinished: (NSUInteger)numTasks {
    _asyncTaskCount -= numTasks;
    Assert(_asyncTaskCount >= 0);
    if (_asyncTaskCount == 0) {
        [self updateActive];
    }
}


- (void) addToInbox: (CBL_Revision*)rev {
    Assert(_running);
    [_batcher queueObject: rev];
    [self updateActive];
}


- (void) addRevsToInbox: (CBL_RevisionList*)revs {
    Assert(_running);
    LogTo(SyncVerbose, @"%@: Received %llu revs", self, (UInt64)revs.count);
    [_batcher queueObjects: revs.allRevisions];
    [self updateActive];
}


- (void) processInbox: (CBL_RevisionList*)inbox {
}


- (void) revisionFailed {
    // Remember that some revisions failed to transfer, so we can later retry.
    ++_revisionsFailed;
}


- (CBL_Revision *) transformRevision:(CBL_Revision *)rev {
    if(_revisionBodyTransformationBlock) {
        @try {
            CBL_Revision* xformed = _revisionBodyTransformationBlock(rev);
            if (xformed == nil)
                return nil;
            if (xformed != rev) {
                AssertEqual(xformed.docID, rev.docID);
                AssertEqual(xformed.revID, rev.revID);
                AssertEqual(xformed[@"_revisions"], rev[@"_revisions"]);
                if (xformed[@"_attachments"]) {
                    // Insert 'revpos' properties into any attachments added by the callback:
                    CBL_MutableRevision* mx = xformed.mutableCopy;
                    xformed = mx;
                    [mx mutateAttachments: ^NSDictionary *(NSString *name, NSDictionary *info) {
                        if (info[@"revpos"])
                            return info;
                        Assert(info[@"data"], @"Transformer added attachment without adding data");
                        NSMutableDictionary* nuInfo = info.mutableCopy;
                        nuInfo[@"revpos"] = @(rev.generation);
                        return nuInfo;
                    }];
                }
                rev = xformed;
            }
        }@catch (NSException* x) {
            Warn(@"%@: Exception transforming a revision of doc '%@': %@", self, rev.docID, x);
        }
    }
    return rev;
}

// Before doing anything else, determine whether we have an active login session.
- (void) checkSession {
    if (![_authorizer respondsToSelector: @selector(loginParametersForSite:)]) {
        [self fetchRemoteCheckpointDoc];
        return;
    }
    // Sync Gateway session API is at /db/_session; try that first
    [self checkSessionAtPath: @"_session"];
}

- (void) checkSessionAtPath: (NSString*)sessionPath {
    // First check whether a session exists
    [self asyncTaskStarted];
    [self sendAsyncRequest: @"GET"
                      path: sessionPath
                      body: nil
              onCompletion: ^(id result, NSError *error) {
                  if (error) {
                      // If not at /db/_session, try CouchDB location /_session
                      if (error.code == kCBLStatusNotFound && $equal(sessionPath, @"_session")) {
                          [self checkSessionAtPath: @"/_session"];
                          return;
                      }
                      LogTo(Sync, @"%@: Session check failed: %@", self, error);
                      self.error = error;
                  } else {
                      NSString* username = $castIf(NSString, result[@"userCtx"][@"name"]);
                      if (username) {
                          LogTo(Sync, @"%@: Active session, logged in as '%@'", self, username);
                          [self fetchRemoteCheckpointDoc];
                      } else {
                          [self login];
                      }
                  }
                  [self asyncTasksFinished: 1];
              }
     ];
}


// If there is no login session, attempt to log in, if the authorizer knows the parameters.
- (void) login {
    NSDictionary* loginParameters = [_authorizer loginParametersForSite: _remote];
    if (loginParameters == nil) {
        LogTo(Sync, @"%@: %@ has no login parameters, so skipping login", self, _authorizer);
        [self fetchRemoteCheckpointDoc];
        return;
    }

    NSString* loginPath = [_authorizer loginPathForSite: _remote];
    LogTo(Sync, @"%@: Logging in with %@ at %@ ...", self, _authorizer.class, loginPath);
    [self asyncTaskStarted];
    [self sendAsyncRequest: @"POST"
                      path: loginPath
                      body: loginParameters
              onCompletion: ^(id result, NSError *error) {
                  if (error) {
                      LogTo(Sync, @"%@: Login failed!", self);
                      self.error = error;
                  } else {
                      LogTo(Sync, @"%@: Successfully logged in!", self);
                      [self fetchRemoteCheckpointDoc];
                  }
                  [self asyncTasksFinished: 1];
              }
     ];
}


#pragma mark - HTTP REQUESTS:


- (NSTimeInterval) requestTimeout {
    id timeoutObj = _options[kCBLReplicatorOption_Timeout];
    if (!timeoutObj)
        return kDefaultRequestTimeout;
    NSTimeInterval timeout = [timeoutObj doubleValue] / 1000.0;
    return timeout > 0.0 ? timeout : kDefaultRequestTimeout;
}


- (BOOL) serverIsSyncGatewayVersion: (NSString*)minVersion {
    return [_serverType hasPrefix: @"Couchbase Sync Gateway/"]
        && [[_serverType substringFromIndex: 23] compare: minVersion] >= 0;
}


- (BOOL) canSendCompressedRequests {
    return [self serverIsSyncGatewayVersion: @"0.92"];
}


- (CBLRemoteJSONRequest*) sendAsyncRequest: (NSString*)method
                                     path: (NSString*)path
                                     body: (id)body
                             onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    LogTo(SyncVerbose, @"%@: %@ %@", self, method, path);
    NSURL* url;
    if ([path hasPrefix: @"/"]) {
        url = [[NSURL URLWithString: path relativeToURL: _remote] absoluteURL];
    } else {
        url = CBLAppendToURL(_remote, path);
    }
    onCompletion = [onCompletion copy];
    
    // under ARC, using variable req used directly inside the block results in a compiler error (it could have undefined value).
    __weak CBL_Replicator *weakSelf = self;
    __block CBLRemoteJSONRequest *req = nil;
    req = [[CBLRemoteJSONRequest alloc] initWithMethod: method
                                                  URL: url
                                                 body: body
                                       requestHeaders: self.requestHeaders
                                         onCompletion: ^(id result, NSError* error) {
        CBL_Replicator *strongSelf = weakSelf;
        [strongSelf removeRemoteRequest: req];
        id<CBLAuthorizer> auth = req.authorizer;
        if (auth && auth != _authorizer && error.code != 401) {
            LogTo(SyncVerbose, @"%@: Updated to %@", self, auth);
            _authorizer = auth;
        }
        onCompletion(result, error);
    }];

    if (self.canSendCompressedRequests)
        [req compressBody];

    [self addRemoteRequest: req];
    [req start];
    return req;
}


- (void) addRemoteRequest: (CBLRemoteRequest*)request {
    request.delegate = self;
    request.timeoutInterval = self.requestTimeout;
    request.authorizer = _authorizer;
    request.cookieStorage = _cookieStorage;

    if (!_remoteRequests)
        _remoteRequests = [[NSMutableArray alloc] init];
    [_remoteRequests addObject: request];
}

- (void) removeRemoteRequest: (CBLRemoteRequest*)request {
    if (!_serverType)
        _serverType = request.responseHeaders[@"Server"];
    [_remoteRequests removeObjectIdenticalTo: request];
}


- (void) stopRemoteRequests {
    if (!_remoteRequests)
        return;
    LogTo(Sync, @"Stopping %u remote requests", (unsigned)_remoteRequests.count);
    // Clear _remoteRequests before iterating, to ensure that re-entrant calls to this won't
    // try to re-stop any of the requests. (Re-entrant calls are possible due to replicator
    // error handling when it receives the 'canceled' errors from the requests I'm stopping.)
    NSArray* requests = _remoteRequests;
    _remoteRequests = nil;
    [requests makeObjectsPerformSelector: @selector(stop)];
}


static NSArray* sAnchorCerts; // TODO: Add API to set these
static BOOL sOnlyTrustAnchorCerts;


+ (void) setAnchorCerts: (NSArray*)certs onlyThese: (BOOL)onlyThese {
    @synchronized(self) {
        sAnchorCerts = certs.copy;
        sOnlyTrustAnchorCerts = onlyThese;
    }
}

- (BOOL) checkSSLServerTrust: (SecTrustRef)trust
                     forHost: (NSString*)host port: (UInt16)port
{
    SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust, 0);
    if (_pinnedCertData) {
        if (_pinnedCertData.length == CC_SHA1_DIGEST_LENGTH) {
            NSData* certDigest = MYGetCertificateDigest(cert);
            if (![certDigest isEqual: _pinnedCertData]) {
                Warn(@"%@: SSL cert digest %@ doesn't match pinnedCert %@",
                     self, certDigest, _pinnedCertData);
                return NO;
            }
        } else {
            NSData* certData = CFBridgingRelease(SecCertificateCopyData(cert));
            if (![certData isEqual: _pinnedCertData]) {
                Warn(@"%@: SSL cert does not equal pinnedCert", self);
                return NO;
            }
        }
    } else {
        @synchronized([self class]) {
            if (sAnchorCerts.count > 0) {
                SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)sAnchorCerts);
                SecTrustSetAnchorCertificatesOnly(trust, sOnlyTrustAnchorCerts);
            }
        }
        SecTrustResultType result;
        OSStatus err = SecTrustEvaluate(trust, &result);
        if (err) {
            Warn(@"%@: SecTrustEvaluate failed with err %d", self, (int)err);
            return NO;
        }
        if (result != kSecTrustResultProceed && result != kSecTrustResultUnspecified) {
            Warn(@"%@: SSL cert is not trustworthy (result=%d)", self, result);
            return NO;
        }
    }

    // Server is trusted. Record its cert in case the client wants to pin it:
    cfSetObj(&_serverCert, cert);
    return YES;
}


// From CBLRemoteRequestDelegate protocol
- (BOOL) checkSSLServerTrust: (NSURLProtectionSpace*)protectionSpace {
    return [self checkSSLServerTrust: protectionSpace.serverTrust
                             forHost: protectionSpace.host
                                port: (UInt16)protectionSpace.port];
}


#pragma mark - CHECKPOINT STORAGE:


- (void) maybeCreateRemoteDB {
    // CBL_Pusher overrides this to implement the .createTarget option
}


/** This is the _local document ID stored on the remote server to keep track of state.
    It's based on the local database UUID (the private one, to make the result unguessable),
    the remote database's URL, and the filter name and parameters (if any). */
- (NSString*) remoteCheckpointDocIDForLocalUUID: (NSString*)localUUID {
    // Needs to be consistent with -hasSameSettingsAs: --
    // If a.remoteCheckpointID == b.remoteCheckpointID then [a hasSameSettingsAs: b]
    NSMutableDictionary* spec = $mdict({@"localUUID", localUUID},
                                       {@"remoteURL", _remote.absoluteString},
                                       {@"push", @(self.isPush)},
                                       {@"continuous", (self.continuous ? nil : $false)},
                                       {@"filter", _filterName},
                                       {@"filterParams", _filterParameters},
                                       //{@"headers", _requestHeaders}, (removed; see #143)
                                       {@"docids", _docIDs});
    NSError *error;
    NSString *remoteCheckpointDocID = CBLHexSHA1Digest([CBJSONEncoder canonicalEncoding: spec
                                                                         error: &error]);
    Assert(!error);
    return remoteCheckpointDocID;
}


- (NSString*) remoteCheckpointDocID {
    if (!_remoteCheckpointDocID) {
        _remoteCheckpointDocID = [self remoteCheckpointDocIDForLocalUUID:_db.privateUUID];
    }
    return _remoteCheckpointDocID;
}


- (NSString*) getLastSequenceFromLocalCheckpointDocument {
    CBLDatabase* strongDb = _db;
    NSDictionary* doc = [strongDb getLocalCheckpointDocument];
    if (doc) {
        NSString* checkpointID = [self remoteCheckpointDocIDForLocalUUID:
                                  doc[kCBLDatabaseLocalCheckpoint_LocalUUID]];
        return [strongDb lastSequenceWithCheckpointID: checkpointID];
    }
    return nil;
}


- (void) fetchRemoteCheckpointDoc {
    _lastSequenceChanged = NO;
    NSString* checkpointID = self.remoteCheckpointDocID;
    NSString* localLastSequence = [_db lastSequenceWithCheckpointID: checkpointID];
    
    [self asyncTaskStarted];
    CBLRemoteJSONRequest* request = 
        [self sendAsyncRequest: @"GET"
                          path: [@"_local/" stringByAppendingString: checkpointID]
                          body: nil
                  onCompletion: ^(id response, NSError* error) {
                  // Got the response:
                  if (error && error.code != kCBLStatusNotFound) {
                      LogTo(Sync, @"%@: Error fetching last sequence: %@",
                            self, error.localizedDescription);
                      self.error = error;
                  } else {
                      if (error.code == kCBLStatusNotFound)
                          [self maybeCreateRemoteDB];
                      response = $castIf(NSDictionary, response);
                      self.remoteCheckpoint = response;
                      NSString* remoteLastSequence = response[@"lastSequence"];

                      if ($equal(remoteLastSequence, localLastSequence)) {
                          _lastSequence = localLastSequence;
                          if (!_lastSequence) {
                              // Try to get the last sequence from the local checkpoint document
                              // created only when importing a database. This allows the
                              // replicator to continue replicating from the current local checkpoint
                              // of the imported database after importing.
                              _lastSequence = [self getLastSequenceFromLocalCheckpointDocument];
                          }
                          LogTo(Sync, @"%@: Replicating from lastSequence=%@", self, _lastSequence);
                      } else {
                          LogTo(Sync, @"%@: lastSequence mismatch: I had %@, remote had %@ (response = %@)",
                                self, localLastSequence, remoteLastSequence, response);
                      }
                      [self beginReplicating];
                  }
                  [self asyncTasksFinished: 1];
          }
     ];
    [request dontLog404];
}


// Variant of -fetchRemoveCheckpointDoc that's used while replication is running, to reload the
// checkpoint to get its current revision number, if there was an error saving it.
- (void) refreshRemoteCheckpointDoc {
    LogTo(Sync, @"%@Refreshing remote checkpoint to get its _rev...", self);
    _savingCheckpoint = YES; // Disable any other save attempts till we finish reloading
    [self asyncTaskStarted];
    CBLRemoteJSONRequest* request =
    [self sendAsyncRequest: @"GET"
                      path: [@"_local/" stringByAppendingString: self.remoteCheckpointDocID]
                      body: nil
              onCompletion: ^(id response, NSError* error) {
                  if (!_db)
                      return;
                  _savingCheckpoint = NO;
                  if (error && error.code != kCBLStatusNotFound) {
                      LogTo(Sync, @"%@: Error refreshing remote checkpoint: %@",
                            self, error.localizedDescription);
                  } else {
                      LogTo(Sync, @"%@ Refreshed remote checkpoint: %@", self, response);
                      self.remoteCheckpoint = $castIf(NSDictionary, response);
                      _lastSequenceChanged = YES;
                      [self saveLastSequence]; // try saving again
                  }
                  [self asyncTasksFinished: 1];
              }
     ];
    [request dontLog404];
}


#if DEBUG
@synthesize savingCheckpoint=_savingCheckpoint;  // for unit tests
#endif


- (void) saveLastSequence {
    if (!_lastSequenceChanged)
        return;
    if (_savingCheckpoint) {
        // If a save is already in progress, don't do anything. (The completion block will trigger
        // another save after the first one finishes.)
        _overdueForSave = YES;
        return;
    }
    _lastSequenceChanged = _overdueForSave = NO;

    id lastSequence = _lastSequence;
    LogTo(Sync, @"%@ checkpointing sequence=%@", self, lastSequence);
    NSMutableDictionary* body = [_remoteCheckpoint mutableCopy];
    if (!body)
        body = $mdict();
    [body setValue: [lastSequence description] forKey: @"lastSequence"]; // always save as a string
    
    _savingCheckpoint = YES;
    NSString* checkpointID = self.remoteCheckpointDocID;
    CBLRemoteRequest* request =
        [self sendAsyncRequest: @"PUT"
                          path: [@"_local/" stringByAppendingString: checkpointID]
                          body: body
                  onCompletion: ^(id response, NSError* error) {
                      _savingCheckpoint = NO;
                      if (error)
                          Warn(@"%@: Unable to save remote checkpoint: %@", self, error);
                      CBLDatabase* db = _db;
                      if (!db)
                          return;
                      if (error) {
                          // Failed to save checkpoint:
                          switch(CBLStatusFromNSError(error, 0)) {
                              case kCBLStatusNotFound:
                                  self.remoteCheckpoint = nil; // doc deleted or db reset
                                  _overdueForSave = YES; // try saving again
                                  break;
                              case kCBLStatusConflict:
                                  [self refreshRemoteCheckpointDoc];
                                  break;
                              default:
                                  break;
                                  // TODO: On 401 or 403, and this is a pull, remember that remote
                                  // is read-only & don't attempt to read its checkpoint next time.
                          }
                      } else {
                          // Saved checkpoint:
                          id rev = response[@"rev"];
                          if (rev)
                              body[@"_rev"] = rev;
                          self.remoteCheckpoint = body;
                          [db setLastSequence: [lastSequence description]
                             withCheckpointID: checkpointID];
                          LogTo(Sync, @"%@ saved remote checkpoint '%@' (_rev=%@)",
                                self, lastSequence, rev);
                      }
                      if (_overdueForSave)
                          [self saveLastSequence];      // start a save that was waiting on me
                  }
         ];
    // This request should not be canceled when the replication is told to stop:
    [_remoteRequests removeObject: request];
}


@end
