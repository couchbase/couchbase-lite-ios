//
//  TDReplicator.m
//  TouchDB
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDReplicator.h"
#import "TDPusher.h"
#import "TDPuller.h"
#import "TDDatabase.h"
#import "TDInternal.h"



#define kProcessDelay 0.5
#define kInboxCapacity 100


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
    }
    return self;
}


- (void)dealloc {
    [self stop];
    [_db release];
    [_remote release];
    [_lastSequence release];
    [_inbox release];
    [_sessionID release];
    [super dealloc];
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _remote.absoluteString);
}


@synthesize db=_db, remote=_remote, running=_running, active=_active, sessionID=_sessionID;


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


- (void) start {
    static int sLastSessionID = 0;
    [_lastSequence release];
    _lastSequence = [[_db lastSequenceWithRemoteURL: _remote push: self.isPush] copy];
    _sessionID = [$sprintf(@"repl%03d", ++sLastSessionID) copy];
    LogTo(Sync, @"%@ STARTING from sequence %@", self, _lastSequence);
    self.running = YES;
}


- (void) stop {
    LogTo(Sync, @"%@ STOPPING", self);
    if (_inbox) {
        [_inbox release];
        _inbox = nil;
        [NSObject cancelPreviousPerformRequestsWithTarget: self
                                                 selector: @selector(flushInbox) object: nil];
    }
    self.running = NO;
    [_db replicatorDidStop: self];
}


- (void) addToInbox: (TDRevision*)rev {
    Assert(_running);
    if (!_inbox) {
        _inbox = [[TDRevisionList alloc] init];
        [self performSelector: @selector(flushInbox) withObject: nil afterDelay: kProcessDelay];
        self.active = YES;
    } else if (_inbox.count >= kInboxCapacity) {
        [self flushInbox];
        _inbox = [[TDRevisionList alloc] init];
    }
    [_inbox addRev: rev];
    LogTo(SyncVerbose, @"%@: Received #%lld (%@)",
          self, rev.sequence, rev.docID);
}


- (void) processInbox: (NSArray*)inbox {
}


- (void) flushInbox {
    if (_inbox.count == 0)
        return;
    
    LogTo(Sync, @"*** %@: BEGIN processInbox (%i sequences)", self, _inbox.count);
    TDRevisionList* inbox = [_inbox autorelease];
    _inbox = nil;
    [self processInbox: inbox];
    LogTo(Sync, @"*** %@: END processInbox (lastSequence=%@)", self, _lastSequence);
    self.active = NO;
}


- (id) sendRequest: (NSString*)method path: (NSString*)relativePath body: (id)body
{
    LogTo(SyncVerbose, @"%@: %@ .%@", self, method, relativePath);
    NSString* urlStr = [_remote.absoluteString stringByAppendingString: relativePath];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: urlStr]];
    request.HTTPMethod = method;
    if (body) {
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject: body options: 0 error: nil];
        [request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    }
    
    NSHTTPURLResponse* response;
    NSError* error = nil;
    NSData* data = [NSURLConnection sendSynchronousRequest: request
                                         returningResponse: (NSURLResponse**)&response
                                                     error: &error];
    if (!data || error || response.statusCode >= 300) {
        Warn(@"%@: %@ .%@ failed (%@)", self, method, relativePath, 
             (error ? error : $object(response.statusCode)));
        return nil;
    }
    
    NSDictionary* results = [NSJSONSerialization JSONObjectWithData: data options: 0 error:nil];
    if (!results)
        Warn(@"%@: %@ %@ returned unparseable data '%@'",
             self, method, relativePath, [data my_UTF8ToString]);
    return results;
}

@end
