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



#define kProcessDelay 0.5
#define kInboxCapacity 100


NSString* TDReplicatorProgressChangedNotification = @"TDReplicatorProgressChanged";


@interface TDReplicator ()
@property (readwrite) BOOL running, active;
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
    [_batcher release];
    [_sessionID release];
    [super dealloc];
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _remote.absoluteString);
}


@synthesize db=_db, remote=_remote, running=_running, active=_active, sessionID=_sessionID;
@synthesize changesProcessed=_changesProcessed, changesTotal=_changesTotal;


- (BOOL) isPush {
    return NO;  // guess who overrides this?
}


- (NSString*) lastSequence {
    return _lastSequence;
}

- (void) setLastSequence:(NSString*)lastSequence {
    if (!$equal(lastSequence, _lastSequence)) {
        [_lastSequence release];
        _lastSequence = [lastSequence copy];
        LogTo(Sync, @"%@ checkpointing sequence=%@", self, lastSequence);
        [_db setLastSequence: lastSequence withRemoteURL: _remote push: self.isPush];
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
    [_lastSequence release];
    _lastSequence = [[_db lastSequenceWithRemoteURL: _remote push: self.isPush] copy];
    _sessionID = [$sprintf(@"repl%03d", ++sLastSessionID) copy];
    LogTo(Sync, @"%@ STARTING from sequence %@", self, _lastSequence);
    self.running = YES;
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


@end
