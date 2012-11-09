//
//  TouchReplication.m
//  TouchDB
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDReplication.h"
#import "TouchDBPrivate.h"

#import "TDPusher.h"
#import "TD_Database+Replication.h"
#import "TD_DatabaseManager.h"
#import "TD_Server.h"
#import "MYBlockUtils.h"


#undef RUN_IN_BACKGROUND


NSString* const kTDReplicationChangeNotification = @"TouchReplicationChange";


@interface TDReplication ()
@property (copy) id source, target;  // document properties

@property (nonatomic, readwrite) bool running;
@property (nonatomic, readwrite) TDReplicationMode mode;
@property (nonatomic, readwrite) unsigned completed, total;
@property (nonatomic, readwrite, retain) NSError* error;
@end


@implementation TDReplication
{
    NSURL* _remoteURL;
    bool _pull;
    NSThread* _mainThread;
    bool _started;
    bool _running;
    unsigned _completed, _total;
    TDReplicationMode _mode;
    NSError* _error;

    TDReplicator* _bg_replicator;       // ONLY used on the server thread
    TD_Database* _bg_serverDatabase;     // ONLY used on the server thread
}


// Instantiate a new non-persistent replication
- (id) initWithDatabase: (TDDatabase*)database
                 remote: (NSURL*)remote
                   pull: (BOOL)pull
{
    NSParameterAssert(database);
    NSParameterAssert(remote);
    self = [super initWithNewDocumentInDatabase: database];
    if (self) {
        _remoteURL = remote;
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


// Instantiate a persistent replication from an existing document in the _replicator db
- (id) initWithDocument:(TDDocument *)document {
    self = [super initWithDocument: document];
    if (self) {
        self.autosaves = YES;  // turn on autosave for all persistent replications
        
        NSString* urlStr = self.sourceURLStr;
        if (isLocalDBName(urlStr))
            urlStr = self.targetURLStr;
        else
            _pull = YES;
        _remoteURL = [[NSURL alloc] initWithString: urlStr];
        _mainThread = [NSThread currentThread];

#if RUN_IN_BACKGROUND
        [self.database.manager.tdServer tellDatabaseNamed: self.localDatabase.name
                                                       to: ^(TD_Database* tddb) {
            _bg_serverDatabase = tddb;
        }];
#else
        _bg_serverDatabase = self.localDatabase.tddb;
#endif
        // Observe *all* replication changes:
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(bg_replicationProgressChanged:)
                                                     name: TDReplicatorProgressChangedNotification
                                                   object: nil];
    }
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
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


- (TDDatabase*) localDatabase {
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


- (void) tellDatabaseManager: (void (^)(TD_DatabaseManager*))block {
#if RUN_IN_BACKGROUND
    [self.database.manager.tdServer tellDatabaseManager: block];
#else
    block(self.database.manager.tdManager);
#endif
}


// This is only for non-persistent replications. Persistent ones are started by
// the TDReplicatorManager.
- (void) start {
    if (_started || self.persistent)
        return;
    _started = YES;
    _mainThread = [NSThread currentThread];

    [self tellDatabaseManager:^(TD_DatabaseManager* dbmgr) {
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
    [self tellDatabaseManager:^(TD_DatabaseManager* dbmgr) {
        // This runs on the server thread:
        [_bg_replicator stop];
    }];
}


@synthesize running = _running, completed=_completed, total=_total, error = _error, mode=_mode;


- (void) updateMode: (TDReplicationMode)mode
              error: (NSError*)error
          processed: (NSUInteger)changesProcessed
            ofTotal: (NSUInteger)changesTotal
{
    BOOL changed = NO;
    if (mode != _mode) {
        self.mode = mode;
        changed = YES;
    }
    BOOL running = (mode > kTDReplicationStopped);
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
                        postNotificationName: kTDReplicationChangeNotification object: self];
    }
}


#pragma mark - BACKGROUND OPERATIONS:


// CAREFUL: This is called on the server's background thread!
- (void) bg_startReplicator: (TD_DatabaseManager*)server_dbmgr
                     dbName: (NSString*)dbName
                     remote: (NSURL*)remote
                       pull: (bool)pull
               createTarget: (bool)createTarget
                 continuous: (bool)continuous
                    options: (NSDictionary*)options
{
    // The setup should use parameters, not ivars, because the ivars may change on the main thread.
    _bg_serverDatabase = [server_dbmgr databaseNamed: dbName];
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
    
    _bg_replicator = repl;
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
        // Persistent replications get this notification for every TDReplicator,
        // so quickly weed out non-matching ones:
        tdReplicator = n.object;
        if (tdReplicator.db != _bg_serverDatabase)
            return;
        if (!$equal(tdReplicator.remote, _remoteURL) || tdReplicator.isPush == _pull)
            return;
    }
    
    // OK, this is my replication, so get its state:
    TDReplicationMode mode;
    if (!tdReplicator.running)
        mode = kTDReplicationStopped;
    else if (!tdReplicator.online)
        mode = kTDReplicationOffline;
    else
        mode = tdReplicator.active ? kTDReplicationActive : kTDReplicationIdle;
    
    // Communicate its state back to the main thread:
    MYOnThread(_mainThread, ^{
        [self updateMode: mode
                   error: tdReplicator.error
               processed: tdReplicator.changesProcessed
                 ofTotal: tdReplicator.changesTotal];
    });
    
    if (_bg_replicator && mode == kTDReplicationStopped) {
        [[NSNotificationCenter defaultCenter] removeObserver: self name: nil object: _bg_replicator];
        _bg_replicator = nil;
    }
}


@end
