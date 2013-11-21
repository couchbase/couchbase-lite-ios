//
//  CBLReplication.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLitePrivate.h"
#import "CBLReplication.h"

#import "CBL_Pusher.h"
#import "CBLDatabase+Replication.h"
#import "CBLDatabase+Internal.h"
#import "CBLManager+Internal.h"
#import "CBLModel_Internal.h"
#import "CBL_Server.h"
#import "CBLPersonaAuthorizer.h"
#import "CBLFacebookAuthorizer.h"
#import "MYBlockUtils.h"
#import "MYURLUtils.h"


#define RUN_IN_BACKGROUND 1


NSString* const kCBLReplicationChangeNotification = @"CBLReplicationChange";


#define kByChannelFilterName @"sync_gateway/bychannel"
#define kChannelsQueryParam  @"channels"


@interface CBLReplication ()
@property (copy) id source, target;  // document properties

@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, readwrite) CBLReplicationMode mode;
@property (nonatomic, readwrite) unsigned completedChangesCount, changesCount;
@property (nonatomic, readwrite, retain) NSError* lastError;
@end


@implementation CBLReplication
{
    NSURL* _remoteURL;
    BOOL _pull;
    NSThread* _mainThread;
    BOOL _started;
    BOOL _running;
    unsigned _completedChangesCount, _changesCount;
    CBLReplicationMode _mode;
    NSError* _lastError;

    CBL_Replicator* _bg_replicator;       // ONLY used on the server thread
    NSString* _bg_documentID;           // ONLY used on the server thread
}


- (instancetype) initPullFromSourceURL: (NSURL*)source toDatabase: (CBLDatabase*)database {
    return [self initWithDatabase: database remote: source pull: YES];
}

- (instancetype) initPushFromDatabase: (CBLDatabase*)database toTargetURL: (NSURL*)target {
    return [self initWithDatabase: database remote: target pull: NO];
}

// Instantiate a new replication; it is not persistent yet
- (instancetype) initWithDatabase: (CBLDatabase*)database
                           remote: (NSURL*)remote
                             pull: (BOOL)pull
{
    NSParameterAssert(database);
    NSParameterAssert(remote);
    CBLDatabase* replicatorDB = [database.manager databaseNamed: @"_replicator" error: NULL];
    if (!replicatorDB)
        return nil;
    self = [super initWithNewDocumentInDatabase: replicatorDB];
    if (self) {
        _remoteURL = remote;
        _pull = pull;
        self.autosaves = NO;
        self.source = pull ? remote.absoluteString : database.name;
        self.target = pull ? database.name : remote.absoluteString;
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
    if (!self.persistent)
        [self setNeedsSave: false];     // I'm ephemeral, so avoid warning about unsaved changes
}


// These are the JSON properties in the replication document:
@dynamic source, target, continuous, filter, network;

@synthesize remoteURL=_remoteURL, pull=_pull;


- (BOOL) createTarget {
    return $castIf(NSNumber, [self valueForKey: @"create_target"]).boolValue;
}

- (void) setCreateTarget:(BOOL)createTarget {
    [self setValue: (createTarget ? $true : nil) forKey: @"create_target"];
}

- (NSDictionary*) filterParams {
    return $castIf(NSDictionary, [self valueForKey: @"query_params"]);
}

- (void) setFilterParams:(NSDictionary *)filterParams {
    [self setValue: filterParams forKey: @"query_params"];
}

- (NSArray*) documentIDs {
    return $castIf(NSArray, [self valueForKey: @"doc_ids"]);
}

- (void) setDocumentIDs:(NSArray *)documentIDs {
    [self setValue: documentIDs forKey: @"doc_ids"];
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@ %@]",
                self.class, (self.pull ? @"from" : @"to"), self.remoteURL.my_sanitizedString];
}


static inline BOOL isLocalDBName(NSString* url) {
    return [url rangeOfString: @":"].length == 0;
}


- (BOOL) persistent {
    return !self.isNew;  // i.e. if it's been saved to the database, it's persistent
}

- (void) setPersistent:(BOOL)persistent {
    if (persistent == self.persistent)
        return;
    BOOL ok;
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
    return self.database.manager[name];
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
    [self restart];
}


- (NSArray*) channels {
    NSString* params = self.filterParams[kChannelsQueryParam];
    if (!self.pull || !$equal(self.filter, kByChannelFilterName) || params.length == 0)
        return nil;
    return [params componentsSeparatedByString: @","];
}

- (void) setChannels:(NSArray *)channels {
    if (channels) {
        Assert(self.pull, @"filterChannels can only be set in pull replications");
        self.filter = kByChannelFilterName;
        self.filterParams = @{kChannelsQueryParam: [channels componentsJoinedByString: @","]};
    } else if ($equal(self.filter, kByChannelFilterName)) {
        self.filter = nil;
        self.filterParams = nil;
    }
}


- (void) willSave: (NSSet*)changedProperties {
    // If any properties change that require the replication to restart, clear the
    // _replication_state property too, which will cause the CBL_ReplicatorManager to restart it.
    static NSSet* sRestartProperties;
    if (!sRestartProperties)
        sRestartProperties = [NSSet setWithObjects: @"filter", @"query_params", @"continuous",
                                                    @"doc_ids", nil];
    if ([changedProperties intersectsSet: sRestartProperties])
        [self setValue: nil ofProperty: @"_replication_state"];
    [super willSave: changedProperties];
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


- (NSString*) facebookEmailAddress {
    NSDictionary* auth = $castIf(NSDictionary, (self.remoteDictionary)[@"auth"]);
    return auth[@"facebook"][@"email"];
}

- (void) setFacebookEmailAddress:(NSString *)email {
    NSDictionary* auth = nil;
    if (email)
        auth = @{@"facebook": @{@"email": email}};
    [self setRemoteDictionaryValue: auth forKey: @"auth"];
}

- (BOOL) registerFacebookToken: (NSString*)token forEmailAddress: (NSString*)email {
    if (![CBLFacebookAuthorizer registerToken: token forEmailAddress: email forSite: self.remoteURL])
        return false;
    self.facebookEmailAddress = email;
    [self restart];
    return true;
}


- (NSURL*) personaOrigin {
    return self.remoteURL.my_baseURL;
}

- (NSString*) personaEmailAddress {
    NSDictionary* auth = $castIf(NSDictionary, (self.remoteDictionary)[@"auth"]);
    return auth[@"persona"][@"email"];
}

- (void) setPersonaEmailAddress:(NSString *)email {
    NSDictionary* auth = nil;
    if (email)
        auth = @{@"persona": @{@"email": email}};
    [self setRemoteDictionaryValue: auth forKey: @"auth"];
}

- (BOOL) registerPersonaAssertion: (NSString*)assertion {
    NSString* email = [CBLPersonaAuthorizer registerAssertion: assertion];
    if (!email) {
        Warn(@"Invalid Persona assertion: %@", assertion);
        return false;
    }
    self.personaEmailAddress = email;
    [self restart];
    return true;
}


+ (void) setAnchorCerts: (NSArray*)certs onlyThese: (BOOL)onlyThese {
    [CBL_Replicator setAnchorCerts: certs onlyThese: onlyThese];
}


#pragma mark - START/STOP:


- (void) tellDatabaseManager: (void (^)(CBLManager*))block {
#if RUN_IN_BACKGROUND
    [self.database.manager.backgroundServer tellDatabaseManager: block];
#else
    block(self.database.manager);
#endif
}


- (void) observeReplicatorManager {
    _bg_documentID = self.document.documentID;
    _mainThread = [NSThread currentThread];
    // Observe *all* replication changes:
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(bg_replicationProgressChanged:)
                                                 name: CBL_ReplicatorProgressChangedNotification
                                               object: nil];
}


- (void) start {
    if (!self.database.isOpen)  // Race condition: db closed before replication starts
        return;

    if (self.persistent) {
        // Removing the _replication_state property triggers the replicator manager to start it.
        [self setValue: nil ofProperty: @"_replication_state"];

    } else if (!_started) {
        // Non-persistent replications I run myself:
        _started = YES;
        _mainThread = [NSThread currentThread];

        NSDictionary* properties= self.currentProperties;
        [self tellDatabaseManager:^(CBLManager* dbmgr) {
            // This runs on the server thread:
            [self bg_startReplicator: dbmgr properties: properties];
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


@synthesize running = _running, completedChangesCount=_completedChangesCount, changesCount=_changesCount, lastError = _lastError, mode=_mode;


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
    if (!$equal(error, _lastError)) {
        self.lastError = error;
        changed = YES;
    }
    if (changesProcessed != _completedChangesCount) {
        self.completedChangesCount = changesProcessed;
        changed = YES;
    }
    if (changesTotal != _changesCount) {
        self.changesCount = changesTotal;
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
- (void) bg_setReplicator: (CBL_Replicator*)repl {
    if (_bg_replicator) {
        [[NSNotificationCenter defaultCenter] removeObserver: self name: nil
                                                      object: _bg_replicator];
    }
    _bg_replicator = repl;
    if (_bg_replicator) {
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(bg_replicationProgressChanged:)
                                                     name: CBL_ReplicatorProgressChangedNotification
                                                   object: _bg_replicator];
    }
}


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
    [self bg_setReplicator: repl];
    [repl start];
    [self bg_updateProgress: _bg_replicator];
}


// CAREFUL: This is called on the server's background thread!
- (void) bg_stopReplicator {
    [_bg_replicator stop];
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
        [self bg_setReplicator: nil];
    }
}


#ifdef CBL_DEPRECATED
@dynamic create_target, query_params, doc_ids;
- (NSError*) error      {return self.lastError;}
- (unsigned) completed  {return self.completedChangesCount;}
- (unsigned) total      {return self.changesCount;}
#endif

@end
