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
#import "CBL_Server.h"
#import "CBLPersonaAuthorizer.h"
#import "CBLFacebookAuthorizer.h"
#import "CBLCookieStorage.h"
#import "MYBlockUtils.h"
#import "MYURLUtils.h"


NSString* const kCBLReplicationChangeNotification = @"CBLReplicationChange";


#define kByChannelFilterName @"sync_gateway/bychannel"
#define kChannelsQueryParam  @"channels"


@interface CBLReplication ()
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, readwrite) CBLReplicationStatus status;
@property (nonatomic, readwrite) unsigned completedChangesCount, changesCount;
@property (nonatomic, readwrite, strong, nullable) NSError* lastError;
@end


@implementation CBLReplication
{
    NSSet* _pendingDocIDs;
    bool _started;
    CBL_Replicator* _bg_replicator;       // ONLY used on the server thread
    NSMutableArray* _pendingCookies;        
}


@synthesize localDatabase=_database, createTarget=_createTarget;
@synthesize continuous=_continuous, filter=_filter, filterParams=_filterParams;
@synthesize documentIDs=_documentIDs, network=_network, remoteURL=_remoteURL, pull=_pull;
@synthesize headers=_headers, OAuth=_OAuth, customProperties=_customProperties;
@synthesize running = _running, completedChangesCount=_completedChangesCount;
@synthesize changesCount=_changesCount, lastError=_lastError, status=_status;
@synthesize authenticator=_authenticator, serverCertificate=_serverCertificate;


- (instancetype) initWithDatabase: (CBLDatabase*)database
                           remote: (NSURL*)remote
                             pull: (BOOL)pull
{
    NSParameterAssert(database);
    NSParameterAssert(remote);
    self = [super init];
    if (self) {
        _database = database;
        _remoteURL = remote;
        _pull = pull;
    }
    return self;
}


- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    cfrelease(_serverCertificate);
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@ %@]",
                self.class, (self.pull ? @"from" : @"to"), self.remoteURL.my_sanitizedString];
}

- (void) setContinuous:(bool)continuous {
    if (continuous != _continuous) {
        _continuous = continuous;
        [self restart];
    }
}

- (void) setFilter:(NSString *)filter {
    if (!$equal(filter, _filter)) {
        _filter = filter;
        [self restart];
    }
}

- (void) setHeaders: (NSDictionary*)headers {
    if (!$equal(headers, _headers)) {
        _headers = headers;
        [self restart];
    }
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


#pragma mark - AUTHENTICATION:


- (NSURLCredential*) credential {
    return [self.remoteURL my_credentialForRealm: nil
                            authenticationMethod: NSURLAuthenticationMethodDefault];
}

- (void) setCredential:(NSURLCredential *)cred {
    // Hardcoded username doesn't mix with stored credentials.
    NSURL* url = self.remoteURL;
    _remoteURL = url.my_URLByRemovingUser;

    NSURLProtectionSpace* space = [url my_protectionSpaceWithRealm: nil
                                            authenticationMethod: NSURLAuthenticationMethodDefault];
    NSURLCredentialStorage* storage = [NSURLCredentialStorage sharedCredentialStorage];
    if (cred) {
        self.authenticator = nil;
        [storage setDefaultCredential: cred forProtectionSpace: space];
    } else {
        cred = [storage defaultCredentialForProtectionSpace: space];
        if (cred)
            [storage removeCredential: cred forProtectionSpace: space];
    }
    [self restart];
}


#ifdef CBL_DEPRECATED

@synthesize facebookEmailAddress=_facebookEmailAddress;

- (BOOL) registerFacebookToken: (NSString*)token forEmailAddress: (NSString*)email {
    if (![CBLFacebookAuthorizer registerToken: token forEmailAddress: email forSite: self.remoteURL])
        return false;
    self.facebookEmailAddress = email;
    [self restart];
    return true;
}
#endif


- (NSURL*) personaOrigin {
    return self.remoteURL.my_baseURL;
}


#ifdef CBL_DEPRECATED
@synthesize personaEmailAddress=_personaEmailAddress;

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
#endif


- (void) setCookieNamed: (NSString*)name
              withValue: (NSString*)value
                   path: (NSString*)path
         expirationDate: (NSDate*)expirationDate
                 secure: (BOOL)secure
{
    if (secure && !_remoteURL.my_isHTTPS)
        Warn(@"%@: Attempting to set secure cookie for non-secure URL %@", self, _remoteURL);
    NSDictionary* props = $dict({NSHTTPCookieOriginURL, _remoteURL.my_baseURL},
                                {NSHTTPCookiePath, (path ?: _remoteURL.path)},
                                {NSHTTPCookieName, name},
                                {NSHTTPCookieValue, value},
                                {NSHTTPCookieExpires, expirationDate},
                                {NSHTTPCookieSecure, (secure ? @YES : nil)});
    NSHTTPCookie* cookie = [NSHTTPCookie cookieWithProperties: props];
    if (!cookie) {
        Warn(@"%@: Could not create cookie from parameters", self);
        return;
    }

    if (_bg_replicator)
        [_bg_replicator.cookieStorage setCookie: cookie];
    else {
        if (!_pendingCookies)
            _pendingCookies = [NSMutableArray array];
        [_pendingCookies addObject: cookie];
    }
}


-(void) deleteCookieNamed: (NSString*)name {
    if (_bg_replicator)
        [_bg_replicator.cookieStorage deleteCookiesNamed: name];
    else {
        if (!_pendingCookies)
            _pendingCookies = [NSMutableArray array];
        [_pendingCookies addObject: name];
    }
}


+ (void) setAnchorCerts: (NSArray*)certs onlyThese: (BOOL)onlyThese {
    [CBL_Replicator setAnchorCerts: certs onlyThese: onlyThese];
}


#pragma mark - START/STOP:


- (NSDictionary*) properties {
    // This is basically the inverse of -[CBLManager parseReplicatorProperties:...]
    NSMutableDictionary* props = $mdict({@"continuous", @(_continuous)},
                                        {@"create_target", @(_createTarget)},
                                        {@"filter", _filter},
                                        {@"query_params", _filterParams},
                                        {@"doc_ids", _documentIDs});
    NSURL* remoteURL = _remoteURL;
    NSMutableDictionary* authDict = nil;
    if (_authenticator) {
        remoteURL = remoteURL.my_URLByRemovingUser;
    } else if (_OAuth || _facebookEmailAddress || _personaEmailAddress) {
        remoteURL = remoteURL.my_URLByRemovingUser;
        authDict = $mdict({@"oauth", _OAuth});
        if (_facebookEmailAddress)
            authDict[@"facebook"] = @{@"email": _facebookEmailAddress};
        if (_personaEmailAddress)
            authDict[@"persona"] = @{@"email": _personaEmailAddress};
    }
    NSDictionary* remote = $dict({@"url", remoteURL.absoluteString},
                                 {@"headers", _headers},
                                 {@"auth", authDict});
    if (_pull) {
        props[@"source"] = remote;
        props[@"target"] = _database.name;
    } else {
        props[@"source"] = _database.name;
        props[@"target"] = remote;
    }

    if (_customProperties)
        [props addEntriesFromDictionary: _customProperties];
    return props;
}


- (void) start {
    if (!_database.isOpen)  // Race condition: db closed before replication starts
        return;

    if (!_started) {
        _started = YES;

        NSDictionary* properties= self.properties;
        id<CBLAuthorizer> auth = (id<CBLAuthorizer>)_authenticator;
        [_database.manager.backgroundServer tellDatabaseManager: ^(CBLManager* bgManager) {
            // This runs on the server thread:
            [self bg_startReplicator: bgManager properties: properties auth: auth];
        }];

        // Initialize the status to something other than kCBLReplicationStopped:
        [self updateStatus: kCBLReplicationOffline error: nil processed: 0 ofTotal: 0
                serverCert: NULL];

        [_database addReplication: self];
    }
}


- (void) stop {
    [self tellReplicator: ^(CBL_Replicator* bgReplicator) {
        // This runs on the server thread:
        [bgReplicator stop];
    }];
    _started = NO;
    [_database forgetReplication: self];
}


- (void) restart {
    if (_started) {
        [self stop];
        [self start];
    }
}


- (BOOL) suspended {
    NSNumber* result = [self tellReplicatorAndWait: ^(CBL_Replicator* bgReplicator) {
        return @(bgReplicator.suspended);
    }];
    return result.boolValue;
}


- (void) setSuspended: (BOOL)suspended {
    [self tellReplicator: ^(CBL_Replicator* bgReplicator) {
        bgReplicator.suspended = suspended;
    }];
}


- (void) updateStatus: (CBLReplicationStatus)status
                error: (NSError*)error
            processed: (NSUInteger)changesProcessed
              ofTotal: (NSUInteger)changesTotal
           serverCert: (SecCertificateRef)serverCert
{
    if (!_started)
        return;
    if (status == kCBLReplicationStopped) {
        _started = NO;
        [_database forgetReplication: self];
    }

    _pendingDocIDs = nil; // forget cached IDs

    BOOL changed = NO;
    if (!$equal(error, _lastError)) {
        self.lastError = error;
        changed = YES;
    }
    if (changesProcessed != _completedChangesCount || changesTotal != _changesCount) {
        // Change the two at the same time to avoid confusing KVO observers:
        [self willChangeValueForKey: @"completedChangesCount"];
        [self willChangeValueForKey: @"changesCount"];
        _changesCount = (unsigned)changesTotal;
        _completedChangesCount = (unsigned)changesProcessed;
        [self didChangeValueForKey: @"changesCount"];
        [self didChangeValueForKey: @"completedChangesCount"];
        changed = YES;
    }
    if (status != _status) {
        self.status = status;
        changed = YES;
    }
    BOOL running = (status > kCBLReplicationStopped);
    if (running != _running) {
        self.running = running;
        changed = YES;
    }

    cfSetObj(&_serverCertificate, serverCert);

    if (changed) {
        static const char* kStatusNames[] = {"stopped", "offline", "idle", "active"};
        LogTo(Sync, @"%@: %s, progress = %u / %u, err: %@",
              self, kStatusNames[status], (unsigned)changesProcessed, (unsigned)changesTotal,
              error.localizedDescription);
        [[NSNotificationCenter defaultCenter]
                        postNotificationName: kCBLReplicationChangeNotification object: self];
    }
}


#pragma mark - PUSH REPLICATION ONLY:


- (NSSet*) pendingDocumentIDs {
    if (!_pendingDocIDs && _started && !_pull) {
        _pendingDocIDs = [self tellReplicatorAndWait: ^(CBL_Replicator* bgReplicator) {
            CBL_RevisionList* revs = ($castIf(CBL_Pusher, bgReplicator)).unpushedRevisions;
            return revs ? [NSSet setWithArray: revs.allDocIDs] : nil;
        }];
    }
    return _pendingDocIDs;
}

- (BOOL) isDocumentPending: (CBLDocument*)doc {
    return doc && [self.pendingDocumentIDs containsObject: doc.documentID];
    //OPT: It may be cheaper to do this by fetching the replicator's checkpoint sequence and
    // comparing the doc's sequence to it.
}


#pragma mark - BACKGROUND OPERATIONS:


- (void) tellReplicator: (void (^)(CBL_Replicator*))block {
    [_database.manager.backgroundServer tellDatabaseManager: ^(CBLManager* _) {
        block(_bg_replicator);
    }];
}

- (id) tellReplicatorAndWait: (id (^)(CBL_Replicator*))block {
    return [_database.manager.backgroundServer waitForDatabaseManager: ^(CBLManager* _) {
        return block(_bg_replicator);
    }];
}


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
                       auth: (id<CBLAuthorizer>)auth
{
    // The setup must use properties, not ivars, because the ivars may change on the main thread.
    CBLStatus status;
    CBL_Replicator* repl = [server_dbmgr replicatorWithProperties: properties status: &status];
    if (!repl) {
        [_database doAsync: ^{
            [self updateStatus: kCBLReplicationStopped
                         error: CBLStatusToNSError(status, nil)
                     processed: 0 ofTotal: 0 serverCert: NULL];
        }];
        return;
    }
    if (auth)
        repl.authorizer = auth;

    if ([_pendingCookies count] > 0) {
        for (id cookie in _pendingCookies) {
            if ([cookie isKindOfClass: [NSHTTPCookie class]])
                [repl.cookieStorage setCookie: cookie];
            else if ([cookie isKindOfClass: [NSString class]])
                [repl.cookieStorage deleteCookiesNamed: cookie];
        }
        _pendingCookies = nil;
    }

    CBLPropertiesTransformationBlock xformer = self.propertiesTransformationBlock;
    if (xformer) {
        repl.revisionBodyTransformationBlock = ^(CBL_Revision* rev) {
            NSDictionary* properties = rev.properties;
            NSDictionary* xformedProperties = xformer(properties);
            if (xformedProperties == nil) {
                rev = nil;
            } else if (xformedProperties != properties) {
                Assert(xformedProperties != nil);
                AssertEqual(xformedProperties.cbl_id, properties.cbl_id);
                AssertEqual(xformedProperties.cbl_rev, properties.cbl_rev);
                CBL_MutableRevision* nuRev = rev.mutableCopy;
                nuRev.properties = xformedProperties;
                rev = nuRev;
            }
            return rev;
        };
    }

    [self bg_setReplicator: repl];
    [repl start];
    [self bg_updateProgress];
}


// CAREFUL: This is called on the server's background thread!
- (void) bg_replicationProgressChanged: (NSNotification*)n
{
    AssertEq(n.object, _bg_replicator);
    [self bg_updateProgress];
}


// CAREFUL: This is called on the server's background thread!
- (void) bg_updateProgress {
    CBLReplicationStatus status;
    if (!_bg_replicator.running)
        status = kCBLReplicationStopped;
    else if (!_bg_replicator.online)
        status = kCBLReplicationOffline;
    else
        status = _bg_replicator.active ? kCBLReplicationActive : kCBLReplicationIdle;
    
    // Communicate its state back to the main thread:
    NSError* error = _bg_replicator.error;
    NSUInteger changes = _bg_replicator.changesProcessed;
    NSUInteger total = _bg_replicator.changesTotal;
    SecCertificateRef serverCert = _bg_replicator.serverCert;
    cfretain(serverCert);
    [_database doAsync: ^{
        [self updateStatus: status error: error processed: changes ofTotal: total
                serverCert: serverCert];
        cfrelease(serverCert);
    }];
    
    if (status == kCBLReplicationStopped) {
        [self bg_setReplicator: nil];
    }
}


@end
