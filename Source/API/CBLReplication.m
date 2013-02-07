//
//  CBLReplication.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBLReplication.h"
#import "CouchbaseLitePrivate.h"

#import "CBL_Pusher.h"
#import "CBL_Database+Replication.h"
#import "CBLManager+Internal.h"
#import "CBL_Server.h"
#import "CBLBrowserIDAuthorizer.h"
#import "MYBlockUtils.h"
#import "MYURLUtils.h"


#undef RUN_IN_BACKGROUND


NSString* const kCBLReplicationChangeNotification = @"CBLReplicationChange";


@interface CBLReplication ()
@property (copy) id source, target;  // document properties

@property (nonatomic, readwrite) bool running;
@property (nonatomic, readwrite) CBLReplicationMode mode;
@property (nonatomic, readwrite) unsigned completed, total;
@property (nonatomic, readwrite, retain) NSError* error;
@end


@implementation CBLReplication
{
    NSURL* _remoteURL;
    bool _pull;
    NSThread* _mainThread;
    bool _started;
    bool _running;
    unsigned _completed, _total;
    CBLReplicationMode _mode;
    NSError* _error;

    CBL_Replicator* _bg_replicator;       // ONLY used on the server thread
    CBL_Database* _bg_serverDatabase;    // ONLY used on the server thread
    NSString* _bg_documentID;           // ONLY used on the server thread
}


// Instantiate a new replication; it is not persistent yet
- (instancetype) initWithDatabase: (CBLDatabase*)database
                           remote: (NSURL*)remote
                             pull: (BOOL)pull
{
    NSParameterAssert(database);
    NSParameterAssert(remote);
    CBLDatabase* replicatorDB = [database.manager databaseNamed: @"_replicator"];
    self = [super initWithNewDocumentInDatabase: replicatorDB];
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
- (instancetype) initWithDocument:(CBLDocument *)document {
    self = [super initWithDocument: document];
    if (self) {
        if (!self.isNew) {
            // This is a persistent replication being loaded from the database:
            self.autosaves = YES;  // turn on autosave for all persistent replications
            NSString* urlStr = self.sourceURLStr;
            if (isLocalDBName(urlStr))
                urlStr = self.targetURLStr;
            else
                _pull = YES;
            Assert(urlStr);
            _remoteURL = [[NSURL alloc] initWithString: urlStr];
            Assert(_remoteURL);
            
            [self observeReplicatorManager];
        }
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
    return !self.isNew;  // i.e. if it's been saved to the database, it's persistent
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
    if (!ok) {
        Warn(@"Error changing persistence of %@: %@", self, error);
        return;
    }
    self.autosaves = persistent;
    if (persistent)
        [self observeReplicatorManager];
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


- (CBLDatabase*) localDatabase {
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


- (void) setRemote: (id)remote {
    if (self.pull)
        self.source = remote;
    else
        self.target = remote;
}


- (void) setRemoteDictionaryValue: (id)value forKey: (NSString*)key {
    id oldRemote = self.pull ? self.source : self.target;
    NSMutableDictionary* remote;
    if ([oldRemote isKindOfClass: [NSString class]])
        remote = [NSMutableDictionary dictionaryWithObject: oldRemote forKey: @"url"];
    else
        remote = [NSMutableDictionary dictionaryWithDictionary: oldRemote];
    [remote setValue: value forKey: key];
    if (!$equal(remote, oldRemote)) {
        [self setRemote: remote];
        [self restart];
    }
}


- (NSDictionary*) headers {
    return (self.remoteDictionary)[@"headers"];
}

- (void) setHeaders: (NSDictionary*)headers {
    [self setRemoteDictionaryValue: headers forKey: @"headers"];
}


#pragma mark - AUTHENTICATION:


- (NSURLCredential*) credential {
    return [self.remoteURL my_credentialForRealm: nil
                            authenticationMethod: NSURLAuthenticationMethodDefault];
}

- (void) setCredential:(NSURLCredential *)cred {
    // Hardcoded username doesn't mix with stored credentials.
    NSURL* url = self.remoteURL;
    [self setRemote: url.my_URLByRemovingUser.absoluteString];

    NSURLProtectionSpace* space = [url my_protectionSpaceWithRealm: nil
                                            authenticationMethod: NSURLAuthenticationMethodDefault];
    NSURLCredentialStorage* storage = [NSURLCredentialStorage sharedCredentialStorage];
    if (cred) {
        [storage setDefaultCredential: cred forProtectionSpace: space];
    } else {
        cred = [storage defaultCredentialForProtectionSpace: space];
        if (cred)
            [storage removeCredential: cred forProtectionSpace: space];
    }
    [self restart];
}

- (NSDictionary*) OAuth {
    NSDictionary* auth = $castIf(NSDictionary, (self.remoteDictionary)[@"auth"]);
    return auth[@"oauth"];
}

- (void) setOAuth: (NSDictionary*)oauth {
    NSDictionary* auth = oauth ? @{@"oauth": oauth} : nil;
    [self setRemoteDictionaryValue: auth forKey: @"auth"];
}

- (NSURL*) browserIDOrigin {
    return [CBLBrowserIDAuthorizer originForSite: self.remoteURL];
}

- (NSString*) browserIDEmailAddress {
    NSDictionary* auth = $castIf(NSDictionary, (self.remoteDictionary)[@"auth"]);
    return auth[@"browserid"][@"email"];
}

- (void) setBrowserIDEmailAddress:(NSString *)email {
    NSDictionary* auth = nil;
    if (email)
        auth = @{@"browserid": @{@"email": email}};
    [self setRemoteDictionaryValue: auth forKey: @"auth"];
}

- (bool) registerBrowserIDAssertion: (NSString*)assertion {
    NSString* email = [CBLBrowserIDAuthorizer registerAssertion: assertion];
    if (!email) {
        Warn(@"Invalid BrowserID assertion: %@", assertion);
        return false;
    }
    self.browserIDEmailAddress = email;
    [self restart];
    return true;
}


#pragma mark - START/STOP:


- (void) tellDatabaseManager: (void (^)(CBLManager*))block {
#if RUN_IN_BACKGROUND
    [self.database.manager.tdServer tellDatabaseManager: block];
#else
    block(self.database.manager);
#endif
}


- (void) observeReplicatorManager {
    _bg_documentID = self.document.documentID;
    _mainThread = [NSThread currentThread];
#if RUN_IN_BACKGROUND
    [self.database.manager.tdServer tellDatabaseNamed: self.localDatabase.name
                                                   to: ^(CBL_Database* tddb) {
                                                       _bg_serverDatabase = tddb;
                                                   }];
#else
    _bg_serverDatabase = self.localDatabase;
#endif
    // Observe *all* replication changes:
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(bg_replicationProgressChanged:)
                                                 name: CBL_ReplicatorProgressChangedNotification
                                               object: nil];
}


- (void) start {
    if (self.persistent) {
        // Removing the _replication_state property triggers the replicator manager to start it.
        [self setValue: nil ofProperty: @"_replication_state"];

    } else if (!_started) {
        // Non-persistent replications I run myself:
        _started = YES;
        _mainThread = [NSThread currentThread];

        [self tellDatabaseManager:^(CBLManager* dbmgr) {
            // This runs on the server thread:
            [self bg_startReplicator: dbmgr properties: self.currentProperties];
        }];
    }
}


- (void) stop {
    // This is a no-op for persistent replications
    if (self.persistent)
        return;
    [self tellDatabaseManager:^(CBLManager* dbmgr) {
        // This runs on the server thread:
        [self bg_stopReplicator];
    }];
    _started = NO;
}


- (void) restart {
    [self setValue: nil ofProperty: @"_replication_state"];
}


@synthesize running = _running, completed=_completed, total=_total, error = _error, mode=_mode;


- (void) updateMode: (CBLReplicationMode)mode
              error: (NSError*)error
          processed: (NSUInteger)changesProcessed
            ofTotal: (NSUInteger)changesTotal
{
    if (!_started && !self.persistent)
        return;
    if (mode == kCBLReplicationStopped)
        _started = NO;
    
    BOOL changed = NO;
    if (mode != _mode) {
        self.mode = mode;
        changed = YES;
    }
    BOOL running = (mode > kCBLReplicationStopped);
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
        LogTo(CBLReplication, @"%@: mode=%d, completed=%u, total=%u (changed=%d)",
              self, mode, (unsigned)changesProcessed, (unsigned)changesTotal, changed);
        [[NSNotificationCenter defaultCenter]
                        postNotificationName: kCBLReplicationChangeNotification object: self];
    }
}


#pragma mark - BACKGROUND OPERATIONS:


// CAREFUL: This is called on the server's background thread!
- (void) bg_startReplicator: (CBLManager*)server_dbmgr
                 properties: (NSDictionary*)properties
{
    // The setup should use properties, not ivars, because the ivars may change on the main thread.
    CBLStatus status;
    CBL_Replicator* repl = [server_dbmgr replicatorWithProperties: properties status: &status];
    if (!repl) {
        MYOnThread(_mainThread, ^{
            [self updateMode: kCBLReplicationStopped
                       error: CBLStatusToNSError(status, nil)
                   processed: 0 ofTotal: 0];
        });
        return;
    }
    _bg_replicator = repl;
    _bg_serverDatabase = repl.db;
    [repl start];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(bg_replicationProgressChanged:)
                                                 name: CBL_ReplicatorProgressChangedNotification
                                               object: _bg_replicator];
    [self bg_updateProgress: _bg_replicator];
}


// CAREFUL: This is called on the server's background thread!
- (void) bg_stopReplicator {
    [_bg_replicator stop];
    _bg_replicator = nil;
    _bg_serverDatabase = nil;
}


// CAREFUL: This is called on the server's background thread!
- (void) bg_replicationProgressChanged: (NSNotification*)n
{
    CBL_Replicator* tdReplicator = n.object;
    if (_bg_replicator) {
        AssertEq(tdReplicator, _bg_replicator);
    } else {
        // Persistent replications get this notification for every CBL_Replicator,
        // so weed out non-matching ones:
        if (!$equal(tdReplicator.documentID, _bg_documentID))
            return;
    }
    [self bg_updateProgress: tdReplicator];
}


// CAREFUL: This is called on the server's background thread!
- (void) bg_updateProgress: (CBL_Replicator*)tdReplicator {
    CBLReplicationMode mode;
    if (!tdReplicator.running)
        mode = kCBLReplicationStopped;
    else if (!tdReplicator.online)
        mode = kCBLReplicationOffline;
    else
        mode = tdReplicator.active ? kCBLReplicationActive : kCBLReplicationIdle;
    
    // Communicate its state back to the main thread:
    MYOnThread(_mainThread, ^{
        [self updateMode: mode
                   error: tdReplicator.error
               processed: tdReplicator.changesProcessed
                 ofTotal: tdReplicator.changesTotal];
    });
    
    if (_bg_replicator && mode == kCBLReplicationStopped) {
        [[NSNotificationCenter defaultCenter] removeObserver: self name: nil object: _bg_replicator];
        _bg_replicator = nil;
    }
}


@end
