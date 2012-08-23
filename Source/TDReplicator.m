//
//  TDReplicator.m
//  TouchDB
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDReplicator.h"
#import "TDPusher.h"
#import "TDPuller.h"
#import <TouchDB/TDDatabase.h>
#import "TDRemoteRequest.h"
#import "TDAuthorizer.h"
#import "TDBatcher.h"
#import "TDReachability.h"
#import "TDInternal.h"
#import "TDMisc.h"
#import "TDBase64.h"
#import "TDCanonicalJSON.h"
#import "MYBlockUtils.h"
#import "MYURLUtils.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif


#define kProcessDelay 0.5
#define kInboxCapacity 100


NSString* TDReplicatorProgressChangedNotification = @"TDReplicatorProgressChanged";
NSString* TDReplicatorStoppedNotification = @"TDReplicatorStopped";


@interface TDReplicator ()
@property (readwrite, nonatomic) BOOL running, active;
@property (readwrite, copy) NSDictionary* remoteCheckpoint;
- (void) updateActive;
- (void) fetchRemoteCheckpointDoc;
- (void) saveLastSequence;
@end


@implementation TDReplicator

+ (NSString *)progressChangedNotification
{
    return TDReplicatorProgressChangedNotification;
}

+ (NSString *)stoppedNotification
{
    return TDReplicatorStoppedNotification;
}


- (id) initWithDB: (TDDatabase*)db
           remote: (NSURL*)remote
             push: (BOOL)push
       continuous: (BOOL)continuous
{
    NSParameterAssert(db);
    NSParameterAssert(remote);
    
    // TDReplicator is an abstract class; instantiating one actually instantiates a subclass.
    if ([self class] == [TDReplicator class]) {
        [self release];
        Class klass = push ? [TDPusher class] : [TDPuller class];
        return [[klass alloc] initWithDB: db remote: remote push: push continuous: continuous];
    }
    
    self = [super init];
    if (self) {
        _thread = [NSThread currentThread];
        _db = db;
        _remote = [remote retain];
        _continuous = continuous;
        Assert(push == self.isPush);

        static int sLastSessionID = 0;
        _sessionID = [$sprintf(@"repl%03d", ++sLastSessionID) copy];
    }
    return self;
}


- (void)dealloc {
    [self stop];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_remote release];
    [_host stop];
    [_host release];
    [_filterName release];
    [_filterParameters release];
    [_lastSequence release];
    [_remoteCheckpoint release];
    [_batcher release];
    [_sessionID release];
    [_error release];
    [_authorizer release];
    [_options release];
    [_requestHeaders release];
    [_remoteRequests release];
    [super dealloc];
}


- (void) databaseClosing {
    [self saveLastSequence];
    [self stop];
    _db = nil;
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _remote.absoluteString);
}


@synthesize db=_db, remote=_remote, filterName=_filterName, filterParameters=_filterParameters;
@synthesize running=_running, online=_online, active=_active, continuous=_continuous;
@synthesize error=_error, sessionID=_sessionID, options=_options;
@synthesize changesProcessed=_changesProcessed, changesTotal=_changesTotal;
@synthesize remoteCheckpoint=_remoteCheckpoint;
@synthesize authorizer=_authorizer;
@synthesize requestHeaders = _requestHeaders;


- (BOOL) isPush {
    return NO;  // guess who overrides this?
}


- (NSString*) lastSequence {
    return _lastSequence;
}

- (void) setLastSequence:(NSString*)lastSequence {
    if (!$equal(lastSequence, _lastSequence)) {
        LogTo(SyncVerbose, @"%@: Setting lastSequence to %@ (from %@)",
              self, lastSequence, _lastSequence);
        [_lastSequence release];
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
    NSNotification* n = [NSNotification notificationWithName: TDReplicatorProgressChangedNotification
                                                      object: self];
    [[NSNotificationQueue defaultQueue] enqueueNotification: n
                                               postingStyle: NSPostWhenIdle
                                               coalesceMask: NSNotificationCoalescingOnSender |
                                                             NSNotificationCoalescingOnName
                                                   forModes: nil];
}


- (void) setChangesProcessed: (NSUInteger)processed {
    _changesProcessed = processed;
    [self postProgressChanged];
}

- (void) setChangesTotal: (NSUInteger)total {
    _changesTotal = total;
    [self postProgressChanged];
}

- (void) updateActive {
    BOOL active = _batcher.count > 0 || _asyncTaskCount > 0;
    if (active != _active) {
        self.active = active;
        [self postProgressChanged];
    }
}

- (void) setError:(NSError *)error {
    if (error.code == NSURLErrorCancelled && $equal(error.domain, NSURLErrorDomain))
        return;
    
    if (ifSetObj(&_error, error))
        [self postProgressChanged];
}


- (void) start {
    if (_running)
        return;
    Assert(_db, @"Can't restart an already stopped TDReplicator");
    LogTo(Sync, @"%@ STARTING ...", self);

    // Note: This is actually a ref cycle, because the block has a (retained) reference to 'self',
    // and _batcher retains the block, and of course I retain _batcher.
    // The cycle is broken in -stopped when I release _batcher.
    _batcher = [[TDBatcher alloc] initWithCapacity: kInboxCapacity delay: kProcessDelay
                 processor:^(NSArray *inbox) {
                     LogTo(SyncVerbose, @"*** %@: BEGIN processInbox (%u sequences)",
                           self, (unsigned)inbox.count);
                     TDRevisionList* revs = [[TDRevisionList alloc] initWithArray: inbox];
                     [self processInbox: revs];
                     [revs release];
                     LogTo(SyncVerbose, @"*** %@: END processInbox (lastSequence=%@)", self, _lastSequence);
                     [self updateActive];
                 }
                ];

    self.running = YES;
    _startTime = CFAbsoluteTimeGetCurrent();
    
#if TARGET_OS_IPHONE
    // Register for foreground/background transition notifications, on iOS:
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(appBackgrounding:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
#endif
    
    // Start reachability checks. (This creates another ref cycle, because
    // the block also retains a ref to self. Cycle is also broken in -stopped.)
    _online = NO;
    _host = [[TDReachability alloc] initWithHostName: _remote.host];
    _host.onChange = ^{[self reachabilityChanged: _host];};
    [_host start];
    [self reachabilityChanged: _host];
}


- (void) beginReplicating {
    // Subclasses implement this
}


- (void) stop {
    if (!_running)
        return;
    LogTo(Sync, @"%@ STOPPING...", self);
    [_batcher flushAll];
    _continuous = NO;
#if TARGET_OS_IPHONE
    // Unregister for background transition notifications, on iOS:
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
#endif
    [self stopRemoteRequests];
    if (_running && _asyncTaskCount == 0)
        [self stopped];
}


- (void) stopped {
    LogTo(Sync, @"%@ STOPPED", self);
    Log(@"Replication: %@ took %.3f sec; error=%@",
        self, CFAbsoluteTimeGetCurrent()-_startTime, _error);
    self.running = NO;
    self.changesProcessed = self.changesTotal = 0;
    [[NSNotificationCenter defaultCenter]
        postNotificationName: TDReplicatorStoppedNotification object: self];
    [self saveLastSequence];
    setObj(&_batcher, nil);
    [_host stop];
    setObj(&_host, nil);
    _db = nil;  // _db no longer tracks me so it won't notify me when it closes; clear ref now
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
        [_lastSequence release];
        _lastSequence = nil;
        self.error = nil;

        [self fetchRemoteCheckpointDoc];
        [self postProgressChanged];
    }
    return YES;
}


- (void) reachabilityChanged: (TDReachability*)host {
    LogTo(Sync, @"%@: Reachability state = %@ (%02X)", self, host, host.reachabilityFlags);

    if (host.reachable)
        [self goOnline];
    else if (host.reachabilityKnown)
        [self goOffline];
}


#if TARGET_OS_IPHONE
- (void) appBackgrounding: (NSNotification*)n {
    // Danger: This is called on the main thread!
    MYOnThread(_thread, ^{
        LogTo(Sync, @"%@: App going into background", self);
        [self stop];
    });
}
#endif


- (void) asyncTaskStarted {
    if (_asyncTaskCount++ == 0)
        [self updateActive];
}


- (void) asyncTasksFinished: (NSUInteger)numTasks {
    _asyncTaskCount -= numTasks;
    Assert(_asyncTaskCount >= 0);
    if (_asyncTaskCount == 0) {
        [self updateActive];
        if (!_continuous)
            [self stopped];
    }
}


- (void) addToInbox: (TDRevision*)rev {
    Assert(_running);
    LogTo(SyncVerbose, @"%@: Received #%lld %@", self, rev.sequence, rev);
    [_batcher queueObject: rev];
    [self updateActive];
}


- (void) addRevsToInbox: (TDRevisionList*)revs {
    Assert(_running);
    LogTo(SyncVerbose, @"%@: Received %llu revs", self, (UInt64)revs.count);
    [_batcher queueObjects: revs.allRevisions];
    [self updateActive];
}


- (void) processInbox: (NSArray*)inbox {
}


#pragma mark - HTTP REQUESTS:


- (TDRemoteJSONRequest*) sendAsyncRequest: (NSString*)method
                                     path: (NSString*)relativePath
                                     body: (id)body
                             onCompletion: (TDRemoteRequestCompletionBlock)onCompletion
{
    LogTo(SyncVerbose, @"%@: %@ .%@", self, method, relativePath);
    NSString* urlStr = [_remote.absoluteString stringByAppendingString: relativePath];
    NSURL* url = [NSURL URLWithString: urlStr];
    onCompletion = [[onCompletion copy] autorelease];
    __block TDRemoteJSONRequest *req = [[TDRemoteJSONRequest alloc] initWithMethod: method
                                                                        URL: url
                                                                       body: body
                                                             requestHeaders: self.requestHeaders 
                                                              onCompletion:
                                ^(id result, NSError* error) {
                                    [self removeRemoteRequest: req];
                                    onCompletion(result, error);
                                }];
    req.authorizer = _authorizer;
    [self addRemoteRequest: req];
    [req start];
    return [req autorelease];
}


- (void) addRemoteRequest: (TDRemoteRequest*)request {
    if (!_remoteRequests)
        _remoteRequests = [[NSMutableArray alloc] init];
    [_remoteRequests addObject: request];
}

- (void) removeRemoteRequest: (TDRemoteRequest*)request {
    [_remoteRequests removeObjectIdenticalTo: request];
}


- (void) stopRemoteRequests {
    if (!_remoteRequests)
        return;
    LogTo(Sync, @"Stopping %u remote requests", (unsigned)_remoteRequests.count);
    // Clear _remoteRequests before iterating, to ensure that re-entrant calls to this won't
    // try to re-stop any of the requests. (Re-entrant calls are possible due to replicator
    // error handling when it receives the 'canceled' errors from the requests I'm stopping.)
    NSArray* requests = [_remoteRequests autorelease];
    _remoteRequests = nil;
    [requests makeObjectsPerformSelector: @selector(stop)];
}


- (NSArray*) activeRequestsStatus {
    return [_remoteRequests my_map: ^id(TDRemoteRequest* request) {
        return request.statusInfo;
    }];
}


#pragma mark - CHECKPOINT STORAGE:


- (void) maybeCreateRemoteDB {
    // TDPusher overrides this to implement the .createTarget option
}


/** This is the _local document ID stored on the remote server to keep track of state.
    It's based on the local database UUID (the private one, to make the result unguessable),
    the remote database's URL, and the filter name and parameters (if any). */
- (NSString*) remoteCheckpointDocID {
    NSMutableDictionary* spec = $mdict({@"localUUID", _db.privateUUID},
                                       {@"remoteURL", _remote.absoluteString},
                                       {@"push", @(self.isPush)},
                                       {@"filter", _filterName},
                                       {@"filterParams", _filterParameters});
    return TDHexSHA1Digest([TDCanonicalJSON canonicalData: spec]);
}


- (void) fetchRemoteCheckpointDoc {
    _lastSequenceChanged = NO;
    NSString* checkpointID = self.remoteCheckpointDocID;
    NSString* localLastSequence = [_db lastSequenceWithCheckpointID: checkpointID];
    
    [self asyncTaskStarted];
    TDRemoteJSONRequest* request = 
        [self sendAsyncRequest: @"GET"
                          path: [@"/_local/" stringByAppendingString: checkpointID]
                          body: nil
                  onCompletion: ^(id response, NSError* error) {
                  // Got the response:
                  if (error && error.code != kTDStatusNotFound) {
                      self.error = error;
                  } else {
                      if (error.code == kTDStatusNotFound)
                          [self maybeCreateRemoteDB];
                      response = $castIf(NSDictionary, response);
                      self.remoteCheckpoint = response;
                      NSString* remoteLastSequence = $castIf(NSString,
                                                        response[@"lastSequence"]);

                      if ($equal(remoteLastSequence, localLastSequence)) {
                          _lastSequence = [localLastSequence retain];
                          LogTo(Sync, @"%@: Replicating from lastSequence=%@", self, _lastSequence);
                      } else {
                          LogTo(Sync, @"%@: lastSequence mismatch: I had %@, remote had %@",
                                self, localLastSequence, remoteLastSequence);
                      }
                      [self beginReplicating];
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
    
    LogTo(Sync, @"%@ checkpointing sequence=%@", self, _lastSequence);
    NSMutableDictionary* body = [[_remoteCheckpoint mutableCopy] autorelease];
    if (!body)
        body = $mdict();
    [body setValue: _lastSequence forKey: @"lastSequence"];
    
    _savingCheckpoint = YES;
    NSString* checkpointID = self.remoteCheckpointDocID;
    [self sendAsyncRequest: @"PUT"
                      path: [@"/_local/" stringByAppendingString: checkpointID]
                      body: body
              onCompletion: ^(id response, NSError* error) {
                  _savingCheckpoint = NO;
                  if (!_db)
                      return;   // db already closed
                  if (error) {
                      Warn(@"%@: Unable to save remote checkpoint: %@", self, error);
                      // TODO: If error is 401 or 403, and this is a pull, remember that remote is read-only and don't attempt to read its checkpoint next time.
                  } else {
                      id rev = response[@"rev"];
                      if (rev)
                          body[@"_rev"] = rev;
                      self.remoteCheckpoint = body;
                      [_db setLastSequence: _lastSequence withCheckpointID: checkpointID];
                  }
                  if (_overdueForSave)
                      [self saveLastSequence];      // start a save that was waiting on me
              }
     ];
}


@end
