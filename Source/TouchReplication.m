//
//  TouchReplication.m
//  TouchDB
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchReplication.h"
#import "TouchDBPrivate.h"

#import "TDPusher.h"
#import "TDDatabase+Replication.h"
#import "TDDatabaseManager.h"
#import "TDServer.h"
#import "MYBlockUtils.h"


NSString* const kTouchReplicationChangeNotification = @"TouchReplicationChange";


@interface TouchReplication ()
@property (copy) id source, target;  // document properties

@property (nonatomic, readwrite) bool running;
@property (nonatomic, readwrite) TouchReplicationMode mode;
@property (nonatomic, readwrite) unsigned completed, total;
@property (nonatomic, readwrite, retain) NSError* error;
@end


@implementation TouchReplication


// Instantiate a new non-persistent replication
- (id) initWithDatabase: (TouchDatabase*)database
                 remote: (NSURL*)remote
                   pull: (BOOL)pull
{
    NSParameterAssert(database);
    NSParameterAssert(remote);
    self = [super initWithNewDocumentInDatabase: database];
    if (self) {
        _remoteURL = [remote retain];
        _pull = pull;
        self.autosaves = NO;
        self.source = pull ? remote.absoluteString : database.name;
        self.target = pull ? database.name : remote.absoluteString;
        // Give the caller a chance to customize parameters like .filter before calling -start,
        // but make sure -start will be run even if the caller doesn't call it.
        [self performSelector: @selector(start) withObject: nil afterDelay: 0.0];
    }
    return self;
}


// Instantiate a persistent replication from an existing document
- (id) initWithDocument:(TouchDocument *)document {
    self = [super initWithDocument: document];
    if (self) {
        self.autosaves = YES;  // turn on autosave for all persistent replications
        
        NSString* urlStr = self.sourceURLStr;
        if (isLocalDBName(urlStr))
            urlStr = self.targetURLStr;
        else
            _pull = YES;
        _remoteURL = [[NSURL alloc] initWithString: urlStr];

        // Observe all replication changes:
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(bg_replicationProgressChanged:)
                                                     name: TDReplicatorProgressChangedNotification
                                                   object: _bg_replicator];
    }
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_remoteURL release];
    [_bg_serverDatabase release];
    [super dealloc];
}


// These are the JSON properties in the replication document:
@dynamic source, target, create_target, continuous, filter, query_params, doc_ids;

@synthesize remoteURL=_remoteURL, pull=_pull;


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@ %@]",
                self.class, (self.pull ? @"from" : @"to"), self.remoteURL];
}


static inline BOOL isLocalDBName(NSString* url) {
    return [url rangeOfString: @":"].length == 0;
}


- (bool) persistent {
    return self.document != nil;
}

- (void) setPersistent:(bool)persistent {
    if (persistent == self.persistent)
        return;
    bool ok;
    NSError* error;
    if (persistent)
        ok = [self save: &error];
    else
        ok = [self deleteDocument: &error];
    if (ok)
        self.autosaves = persistent;
    else 
        Warn(@"Error changing persistence of %@: %@", self, error);
}


- (NSString*) sourceURLStr {
    id source = self.source;
    if ([source isKindOfClass: [NSDictionary class]])
        source = source[@"url"];
    return $castIf(NSString, source);
}


- (NSString*) targetURLStr {
    id target = self.target;
    if ([target isKindOfClass: [NSDictionary class]])
        target = target[@"url"];
    return $castIf(NSString, target);
}


- (TouchDatabase*) localDatabase {
    NSString* name = self.sourceURLStr;
    if (!isLocalDBName(name))
        name = self.targetURLStr;
    return [self.database.manager databaseNamed: name];
}


// The 'source' or 'target' dictionary, whichever is remote, if it's a dictionary not a string
- (NSDictionary*) remoteDictionary {
    id source = self.source;
    if ([source isKindOfClass: [NSDictionary class]] 
            && !isLocalDBName(source[@"url"]))
        return source;
    id target = self.target;
    if ([target isKindOfClass: [NSDictionary class]] 
            && !isLocalDBName(target[@"url"]))
        return target;
    return nil;
}


- (void) setRemoteDictionaryValue: (id)value forKey: (NSString*)key {
    BOOL isPull = self.pull;
    id remote = isPull ? self.source : self.target;
    if ([remote isKindOfClass: [NSString class]])
        remote = [NSMutableDictionary dictionaryWithObject: remote forKey: @"url"];
    else
        remote = [NSMutableDictionary dictionaryWithDictionary: remote];
    [remote setValue: value forKey: key];
    if (isPull)
        self.source = remote;
    else
        self.target = remote;
}


- (NSDictionary*) headers {
    return (self.remoteDictionary)[@"headers"];
}

- (void) setHeaders: (NSDictionary*)headers {
    [self setRemoteDictionaryValue: headers forKey: @"headers"];
}

- (NSDictionary*) OAuth {
    NSDictionary* auth = $castIf(NSDictionary, (self.remoteDictionary)[@"auth"]);
    return auth[@"oauth"];
}

- (void) setOAuth: (NSDictionary*)oauth {
    NSDictionary* auth = oauth ? @{@"oauth": oauth} : nil;
    [self setRemoteDictionaryValue: auth forKey: @"auth"];
}


#pragma mark - START/STOP:


// This is only for non-persistent replications. Persistent ones are started by
// the TDReplicatorManager.
- (void) start {
    if (_started || self.persistent)
        return;
    _started = YES;
    _mainThread = [NSThread currentThread];

    [self.database.manager.tdServer tellDatabaseManager:^(TDDatabaseManager* dbmgr) {
        // This runs on the server thread:
        [self bg_startReplicator: dbmgr
                          dbName: self.localDatabase.name
                          remote: self.remoteURL
                            pull: self.pull
                    createTarget: self.create_target
                      continuous: self.continuous
                         options: self.currentProperties];
    }];
}


- (void) stop {
    if (self.persistent)
        return;
    [self.database.manager.tdServer tellDatabaseManager:^(TDDatabaseManager* dbmgr) {
        // This runs on the server thread:
        [_bg_replicator stop];
    }];
}


@synthesize running = _running, completed=_completed, total=_total, error = _error, mode=_mode;


- (void) updateMode: (TouchReplicationMode)mode
              error: (NSError*)error
          processed: (NSUInteger)changesProcessed
            ofTotal: (NSUInteger)changesTotal
{
    BOOL changed = NO;
    if (mode != _mode) {
        self.mode = mode;
        changed = YES;
    }
    BOOL running = (mode > kTouchReplicationStopped);
    if (running != _running) {
        self.running = running;
        changed = YES;
    }
    if (!$equal(error, _error)) {
        self.error = error;
        changed = YES;
    }
    if (changesProcessed != _completed) {
        self.completed = changesProcessed;
        changed = YES;
    }
    if (changesTotal != _total) {
        self.total = changesTotal;
        changed = YES;
    }
    if (changed) {
        [[NSNotificationCenter defaultCenter]
                        postNotificationName: kTouchReplicationChangeNotification object: self];
    }
}


#pragma mark - BACKGROUND OPERATIONS:


// CAREFUL: This is called on the server's background thread!
- (void) bg_startReplicator: (TDDatabaseManager*)server_dbmgr
                     dbName: (NSString*)dbName
                     remote: (NSURL*)remote
                       pull: (bool)pull
               createTarget: (bool)createTarget
                 continuous: (bool)continuous
                    options: (NSDictionary*)options
{
    // The setup should use parameters, not ivars, because the ivars may change on the main thread.
    _bg_serverDatabase = [[server_dbmgr databaseNamed: dbName] retain];
    TDReplicator* repl = [_bg_serverDatabase replicatorWithRemoteURL: remote
                                                             push: !pull
                                                       continuous: continuous];
    if (!repl)
        return;
    repl.filterName = options[@"filter"];
    repl.filterParameters = options[@"query_params"];
    repl.options = options;
    repl.requestHeaders = options[@"headers"];
    if (!pull)
        ((TDPusher*)repl).createTarget = createTarget;
    [repl start];
    
    _bg_replicator = [repl retain];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(bg_replicationProgressChanged:)
                                                 name: TDReplicatorProgressChangedNotification
                                               object: _bg_replicator];
    [self bg_replicationProgressChanged: nil];
}


// CAREFUL: This is called on the server's background thread!
- (void) bg_replicationProgressChanged: (NSNotification*)n
{
    TDReplicator* tdReplicator;
    if (_bg_replicator) {
        tdReplicator = _bg_replicator;
    } else {
        // I get this notification for every TDReplicator, so quickly weed out non-matching ones:
        tdReplicator = n.object;
        if (tdReplicator.db != _bg_serverDatabase)
            return;
        if (!$equal(tdReplicator.remote, _remoteURL) || tdReplicator.isPush == _pull)
            return;
    }
    
    // OK, this is my replication, so get its state:
    TouchReplicationMode mode;
    if (!tdReplicator.running)
        mode = kTouchReplicationStopped;
    else if (!tdReplicator.online)
        mode = kTouchReplicationOffline;
    else
        mode = tdReplicator.active ? kTouchReplicationActive : kTouchReplicationIdle;
    
    // Communicate its state back to the main thread:
    MYOnThread(_mainThread, ^{
        [self updateMode: mode
                   error: tdReplicator.error
               processed: tdReplicator.changesProcessed
                 ofTotal: tdReplicator.changesTotal];
    });
    
    if (_bg_replicator && mode == kTouchReplicationStopped) {
        [[NSNotificationCenter defaultCenter] removeObserver: self name: nil object: _bg_replicator];
        setObj(&_bg_replicator, nil);
    }
}


@end
