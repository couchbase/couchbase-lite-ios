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

#import "CBLInternal.h"
#import "CBLReplication.h"

#import "CBL_Replicator.h"
#import "CBLDatabase+Replication.h"
#import "CBLDatabase+Internal.h"
#import "CBLManager+Internal.h"
#import "CBL_Server.h"
#import "CBLCookieStorage.h"
#import "CBLAuthorizer.h"
#import "CBL_AttachmentTask.h"
#import "CBLProgressGroup.h"
#import "MYBlockUtils.h"
#import "MYURLUtils.h"


typedef void (^PendingAction)(id<CBL_Replicator>);


NSString* const kCBLReplicationChangeNotification = @"CBLReplicationChange";
NSString* const kCBLProgressErrorKey = kCBLProgressError;


// Declared in CBL_Replicator.h
NSString* CBL_ReplicatorProgressChangedNotification = @"CBL_ReplicatorProgressChanged";
NSString* CBL_ReplicatorStoppedNotification = @"CBL_ReplicatorStopped";


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

    // ONLY used on the server thread:
    id<CBL_Replicator> _bg_replicator;
    NSMutableArray* _bg_pendingCookies;
    NSMutableArray* _bg_pendingActions;
    NSConditionLock* _bg_stopLock;
}


@synthesize localDatabase=_database, createTarget=_createTarget;
@synthesize continuous=_continuous, filter=_filter, filterParams=_filterParams;
@synthesize documentIDs=_documentIDs, network=_network, remoteURL=_remoteURL, pull=_pull;
@synthesize headers=_headers, OAuth=_OAuth, customProperties=_customProperties;
@synthesize running = _running, completedChangesCount=_completedChangesCount;
@synthesize changesCount=_changesCount, lastError=_lastError, status=_status;
@synthesize authenticator=_authenticator, serverCertificate=_serverCertificate;
@synthesize downloadsAttachments=_downloadsAttachments;


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
        _downloadsAttachments = YES;
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


- (NSURL*) personaOrigin {
    return self.remoteURL.my_baseURL;
}


- (void) setCookieNamed: (NSString*)name
              withValue: (NSString*)value
                   path: (nullable NSString*)path
         expirationDate: (nullable NSDate*)expirationDate
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

    [self tellReplicator: ^(id<CBL_Replicator> bgReplicator) {
        if (bgReplicator)
            [bgReplicator.cookieStorage setCookie: cookie];
        else {
            if (!_bg_pendingCookies)
                _bg_pendingCookies = [NSMutableArray array];
            [_bg_pendingCookies addObject: cookie];
        }
    }];
}


- (void) deleteCookieNamed: (NSString*)name {
    [self tellReplicator: ^(id<CBL_Replicator> bgReplicator) {
        if (_bg_replicator)
            [_bg_replicator.cookieStorage deleteCookiesNamed: name];
        else {
            if (!_bg_pendingCookies)
                _bg_pendingCookies = [NSMutableArray array];
            [_bg_pendingCookies addObject: name];
        }
    }];
}


+ (void) setAnchorCerts: (NSArray*)certs onlyThese: (BOOL)onlyThese {
    CBLSetAnchorCerts(certs, onlyThese);
}


#pragma mark - START/STOP:


- (NSDictionary*) properties {
    // This is basically the inverse of -[CBLManager parseReplicatorProperties:...]
    NSMutableDictionary* props = $mdict({@"continuous", @(_continuous)},
                                        {@"create_target", @(_createTarget)},
                                        {@"filter", _filter},
                                        {@"query_params", _filterParams},
                                        {@"doc_ids", _documentIDs},
                                        {@"attachments", (_downloadsAttachments ? nil : @NO)});
    NSURL* remoteURL = _remoteURL;
    NSMutableDictionary* authDict = nil;
    if (_authenticator) {
        remoteURL = remoteURL.my_URLByRemovingUser;
    } else if (_OAuth) {
        remoteURL = remoteURL.my_URLByRemovingUser;
        authDict = $mdict({@"oauth", _OAuth});
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
    if (!_started)
        return;

    BOOL stopping = [[self tellReplicatorAndWait: ^id(id<CBL_Replicator> bgReplicator) {
        if (bgReplicator.status != kCBLReplicatorStopped) {
            _bg_stopLock = [[NSConditionLock alloc] initWithCondition: 0];
            [bgReplicator stop];
            return @(YES);
        }
        return @(NO);
    }] boolValue];

    if (!stopping)
        return;
    
    // Waiting for the background stop notification:
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0]; // 2 seconds:
    if ([_bg_stopLock lockWhenCondition: 1 beforeDate: timeout])
        [_bg_stopLock unlock];
    else
        Warn(@"%@: Timeout waiting for background stop notification", self);

    [self tellReplicatorAndWait: ^id(id<CBL_Replicator> bgReplicator) {
        _bg_stopLock = nil;
        return @(YES);
    }];
}


- (void) restart {
    if (_started) {
        [self stop];

        // Schedule to call the -start method in the next runloop queue or dispatch queue.
        // This allows the -start method to be called after the _started var is set to 'NO'
        // in the -updateStatus: method.
        [_database doAsync:^{
            [self start];
        }];
    }
}


- (BOOL) suspended {
    NSNumber* result = [self tellReplicatorAndWait: ^(id<CBL_Replicator> bgReplicator) {
        return @(bgReplicator.suspended);
    }];
    return result.boolValue;
}


- (void) setSuspended: (BOOL)suspended {
    [self tellReplicator: ^(id<CBL_Replicator> bgReplicator) {
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
#ifndef MY_DISABLE_LOGGING
        static const char* kStatusNames[] = {"stopped", "offline", "idle", "active"};
        LogTo(Sync, @"%@: %s, progress = %u / %u, err: %@",
              self, kStatusNames[status], (unsigned)changesProcessed, (unsigned)changesTotal,
              error.localizedDescription);
#endif
        [[NSNotificationCenter defaultCenter]
                        postNotificationName: kCBLReplicationChangeNotification object: self];
    }
}


#pragma mark - PUSH REPLICATION ONLY:

- (NSSet*) pendingDocumentIDs {
    if (_pull || (_started && _pendingDocIDs))
        return _pendingDocIDs;

    _pendingDocIDs = [_database.manager.backgroundServer
                      waitForDatabaseNamed: _database.name to: ^id(CBLDatabase* bgDb)
    {
        CBLStatus status;
        CBL_ReplicatorSettings* settings =
            [bgDb.manager replicatorSettingsWithProperties: self.properties
                                                toDatabase: nil
                                                    status: &status];
        if (!settings) {
            Warn(@"Error parsing replicator settings : %@", CBLStatusToNSError(status));
            return nil;
        }

        NSString* lastSequence = _bg_replicator.lastSequence;
        if (!lastSequence)
            lastSequence = [bgDb lastSequenceForReplicator: settings];

        NSError* error;
        CBL_RevisionList* revs = [bgDb unpushedRevisionsSince: lastSequence
                                                       filter: settings.filterBlock
                                                       params: settings.filterParameters
                                                        error: &error];
        if (revs)
            return [NSSet setWithArray: revs.allDocIDs];
        else
            Warn(@"Error getting unpushed revisions : %@", error);
        return nil;
    }];
    return _pendingDocIDs;
}


- (BOOL) isDocumentPending: (CBLDocument*)doc {
    return doc && [self.pendingDocumentIDs containsObject: doc.documentID];
    //OPT: It may be cheaper to do this by fetching the replicator's checkpoint sequence and
    // comparing the doc's sequence to it.
}


#pragma mark - PULL REPLICATION ONLY:


- (NSProgress*) downloadAttachment: (CBLAttachment*)attachment{
    Assert(_pull, @"Not a pull replication");
    AssertEq(attachment.document.database, _database);

    if (attachment.contentAvailable)
        return nil;

    NSProgress* progress = [NSProgress progressWithTotalUnitCount: attachment.encodedLength];
    progress.cancellable = YES;     // downloader will set its own cancellation handler
    progress.kind = NSProgressKindFile;
    [progress setUserInfoObject: NSProgressFileOperationKindDownloading
                         forKey: NSProgressFileOperationKindKey];

    CBL_AttachmentID *attID;
    attID = [[CBL_AttachmentID alloc] initWithDocID: attachment.document.documentID
                                              revID: attachment.revision.revisionID
                                               name: attachment.name
                                           metadata: attachment.metadata];
    CBL_AttachmentTask *request = [[CBL_AttachmentTask alloc] initWithID: attID
                                                                progress: progress];

    [self tellReplicatorWhileRunning:^(id<CBL_Replicator> bgReplicator) {
        [bgReplicator downloadAttachment: request];
    }];
    [self start];
    return progress;
}


#pragma mark - BACKGROUND OPERATIONS:


- (void) tellReplicator: (void (^)(id<CBL_Replicator>))block {
    [_database.manager.backgroundServer tellDatabaseManager: ^(CBLManager* _) {
        block(_bg_replicator);
    }];
}

- (id) tellReplicatorAndWait: (id (^)(id<CBL_Replicator>))block {
    return [_database.manager.backgroundServer waitForDatabaseManager: ^(CBLManager* _) {
        return block(_bg_replicator);
    }];
}

- (void) tellReplicatorWhileRunning: (void (^)(id<CBL_Replicator>))block {
    [self tellReplicator: ^(id<CBL_Replicator> bgRepl) {
        if (bgRepl.status > kCBLReplicatorStopped) {
            // If we have an active replicator, tell it right away:
            block(bgRepl);
        } else {
            // Otherwise, queue the action till the replicator starts:
            if (!_bg_pendingActions)
                _bg_pendingActions = [NSMutableArray new];
            [_bg_pendingActions addObject: block];
        }
    }];
}


// CAREFUL: This is called on the server's background thread!
- (void) bg_setReplicator: (id<CBL_Replicator>)repl {
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
    id<CBL_Replicator> repl = [server_dbmgr replicatorWithProperties: properties status: &status];
    if (!repl) {
        __weak CBLReplication *weakSelf = self;
        [_database doAsync: ^{
            CBLReplication *strongSelf = weakSelf;
            [strongSelf updateStatus: kCBLReplicationStopped
                               error: CBLStatusToNSError(status)
                           processed: 0 ofTotal: 0 serverCert: NULL];
        }];
        return;
    }
    if (auth)
        repl.settings.authorizer = auth;

    if ([_bg_pendingCookies count] > 0) {
        for (id cookie in _bg_pendingCookies) {
            if ([cookie isKindOfClass: [NSHTTPCookie class]])
                [repl.cookieStorage setCookie: cookie];
            else if ([cookie isKindOfClass: [NSString class]])
                [repl.cookieStorage deleteCookiesNamed: cookie];
        }
        _bg_pendingCookies = nil;
    }

    CBLPropertiesTransformationBlock xformer = self.propertiesTransformationBlock;
    if (xformer) {
        repl.settings.revisionBodyTransformationBlock = ^(CBL_Revision* rev) {
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

    // Perform any pending actions that were queued up by -tellReplicatorWhileRunning:
    NSArray* actions = _bg_pendingActions;
    _bg_pendingActions = nil;
    for (PendingAction action in actions)
        action(repl);
}


// CAREFUL: This is called on the server's background thread!
- (void) bg_replicationProgressChanged: (NSNotification*)n {
    if (n.object == _bg_replicator)
        [self bg_updateProgress];
    else
        Warn(@"%@: Received replication change notification from "
             "an unexpected replicator %@ (expected %@)", self, n.object, _bg_replicator);
}


// CAREFUL: This is called on the server's background thread!
- (void) bg_updateProgress {
    CBLReplicationStatus status = (CBLReplicationStatus)_bg_replicator.status;
    NSError* error = _bg_replicator.error;
    NSUInteger changes = _bg_replicator.changesProcessed;
    NSUInteger total = _bg_replicator.changesTotal;
    SecCertificateRef serverCert = _bg_replicator.serverCert;
    cfretain(serverCert);

    if (status == kCBLReplicationStopped) {
        [self bg_setReplicator: nil];
    }

    // Communicate its state back to the main thread:
    // Call -doAsync: on the manager object instead of on the database object
    // to allow the block to be executed regardless of the database open status.
    // Without loosing the database open status check, the stopped notification
    // can't be sent when the replication is stopped from closing the database.
    __weak CBLReplication *weakSelf = self;
    [_database.manager doAsync:^{
        CBLReplication *strongSelf = weakSelf;
        [strongSelf updateStatus: status error: error processed: changes ofTotal: total
                      serverCert: serverCert];
        cfrelease(serverCert);
    }];

    if (status == kCBLReplicationStopped) {
        [_bg_stopLock lockWhenCondition: 0];
        [_bg_stopLock unlockWithCondition: 1];
    }
}


@end
