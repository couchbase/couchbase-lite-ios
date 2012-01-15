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
#import "TDDatabase.h"
#import "TDRemoteRequest.h"
#import "TDBatcher.h"
#import "TDInternal.h"
#import "TDMisc.h"


#define kProcessDelay 0.5
#define kInboxCapacity 100


NSString* TDReplicatorProgressChangedNotification = @"TDReplicatorProgressChanged";


@interface TDReplicator ()
@property (readwrite) BOOL running, active;
@property (readwrite, copy) NSDictionary* remoteCheckpoint;
- (void) fetchRemoteCheckpointDoc;
- (void) saveLastSequence;
@end


@implementation TDReplicator

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
        _db = [db retain];
        _remote = [remote retain];
        _continuous = continuous;
        Assert(push == self.isPush);
        
        _batcher = [[TDBatcher alloc] initWithCapacity: kInboxCapacity delay: kProcessDelay
                     processor:^(NSArray *inbox) {
                         LogTo(Sync, @"*** %@: BEGIN processInbox (%i sequences)",
                               self, inbox.count);
                         TDRevisionList* revs = [[TDRevisionList alloc] initWithArray: inbox];
                         [self processInbox: revs];
                         [revs release];
                         LogTo(Sync, @"*** %@: END processInbox (lastSequence=%@)", self, _lastSequence);
                         self.active = NO;
                     }
                    ];
    }
    return self;
}


- (void)dealloc {
    [self stop];
    [_db release];
    [_remote release];
    [_lastSequence release];
    [_remoteCheckpoint release];
    [_batcher release];
    [_sessionID release];
    [_error release];
    [super dealloc];
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _remote.absoluteString);
}


@synthesize db=_db, remote=_remote;
@synthesize running=_running, active=_active, error=_error, sessionID=_sessionID;
@synthesize changesProcessed=_changesProcessed, changesTotal=_changesTotal;
@synthesize remoteCheckpoint=_remoteCheckpoint;


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
            [self performSelector: @selector(saveLastSequence) withObject: nil afterDelay: 2.0];
        }
    }
}


- (void) setChangesProcessed: (NSUInteger)processed {
    _changesProcessed = processed;
    [[NSNotificationCenter defaultCenter]
            postNotificationName: TDReplicatorProgressChangedNotification object: self];
}

- (void) setChangesTotal: (NSUInteger)total {
    _changesTotal = total;
    [[NSNotificationCenter defaultCenter]
            postNotificationName: TDReplicatorProgressChangedNotification object: self];
}


- (void) start {
    if (_running)
        return;
    static int sLastSessionID = 0;
    _sessionID = [$sprintf(@"repl%03d", ++sLastSessionID) copy];
    LogTo(Sync, @"%@ STARTING from sequence %@", self, _lastSequence);
    self.running = YES;
    [_lastSequence release];
    _lastSequence = nil;

    [self fetchRemoteCheckpointDoc];
}


- (void) beginReplicating {
    // Subclasses implement this
}


- (void) stop {
    if (!_running)
        return;
    LogTo(Sync, @"%@ STOPPING...", self);
    [_batcher flush];
    if (_asyncTaskCount == 0)
        [self stopped];
}


- (void) stopped {
    LogTo(Sync, @"%@ STOPPED", self);
    [_db replicatorDidStop: self];
    self.running = NO;
    self.changesProcessed = self.changesTotal = 0;
}


- (void) asyncTaskStarted {
    ++_asyncTaskCount;
}


- (void) asyncTasksFinished: (NSUInteger)numTasks {
    _asyncTaskCount -= numTasks;
    Assert(_asyncTaskCount >= 0);
    if (_asyncTaskCount == 0) {
        [self stopped];
    }
}


- (void) addToInbox: (TDRevision*)rev {
    Assert(_running);
    if (_batcher.count == 0)
        self.active = YES;
    [_batcher queueObject: rev];
    LogTo(SyncVerbose, @"%@: Received #%lld %@", self, rev.sequence, rev);
}


- (void) processInbox: (NSArray*)inbox {
}


- (void) sendAsyncRequest: (NSString*)method path: (NSString*)relativePath body: (id)body
             onCompletion: (TDRemoteRequestCompletionBlock)onCompletion
{
    LogTo(SyncVerbose, @"%@: %@ .%@", self, method, relativePath);
    NSString* urlStr = [_remote.absoluteString stringByAppendingString: relativePath];
    NSURL* url = [NSURL URLWithString: urlStr];
    TDRemoteRequest* request = [[TDRemoteRequest alloc] initWithMethod: method
                                                                   URL: url
                                                                  body: body
                                                          onCompletion: onCompletion];
    [request autorelease];
}


#pragma mark - CHECKPOINT STORAGE:


/** This is the _local document ID stored on the remote server to keep track of state.
    Its ID is based on the local database ID (the private one, to make the result unguessable)
    and the remote database's URL. */
- (NSString*) remoteCheckpointDocID {
    NSString* input = $sprintf(@"%@\n%@\n%i", _db.privateUUID, _remote.absoluteString, self.isPush);
    return TDHexSHA1Digest([input dataUsingEncoding: NSUTF8StringEncoding]);
}


- (void) fetchRemoteCheckpointDoc {
    _lastSequenceChanged = NO;
    NSString* localLastSequence = [_db lastSequenceWithRemoteURL: _remote push: self.isPush];
    if (!localLastSequence) {
        [self beginReplicating];
        return;
    }
    
    [self asyncTaskStarted];
    [self sendAsyncRequest: @"GET"
                      path: [@"/_local/" stringByAppendingString: self.remoteCheckpointDocID]
                      body: nil
              onCompletion: ^(id response, NSError* error) {
                  // Got the response:
                  if (error && error.code != 404) {
                      self.error = error;
                  } else {
                      response = $castIf(NSDictionary, response);
                      self.remoteCheckpoint = response;
                      NSString* remoteLastSequence = $castIf(NSString,
                                                        [response objectForKey: @"lastSequence"]);

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
}


- (void) saveLastSequence {
    if (!_lastSequenceChanged)
        return;
    _lastSequenceChanged = NO;
    
    LogTo(Sync, @"%@ checkpointing sequence=%@", self, _lastSequence);
    NSMutableDictionary* body = [_remoteCheckpoint mutableCopy] ?: $mdict();
    [body setObject: _lastSequence forKey: @"lastSequence"];
    
    [self sendAsyncRequest: @"PUT"
                      path: [@"/_local/" stringByAppendingString: self.remoteCheckpointDocID]
                      body: body
              onCompletion: ^(id response, NSError* error) {
                  if (error) {
                      LogTo(Sync, @"%@: Unable to save remote checkpoint: %@", self, error);
                      // TODO: If error is 401 or 403, and this is a pull, remember that remote is read-only and don't attempt to read its checkpoint next time.
                  } else {
                      [body setObject: [response objectForKey: @"rev"] forKey: @"_rev"];
                      self.remoteCheckpoint = body;
                  }
              }
     ];
    [_db setLastSequence: _lastSequence withRemoteURL: _remote push: self.isPush];
}


@end
