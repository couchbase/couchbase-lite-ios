//
//  TDReplicatorManager.m
//  TouchDB
//
//  Created by Jens Alfke on 2/15/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
//  http://wiki.apache.org/couchdb/Replication#Replicator_database
//  http://www.couchbase.com/docs/couchdb-release-1.1/index.html

#import "TDReplicatorManager.h"
#import "TDServer.h"
#import <TouchDB/TDDatabase.h>
#import "TDDatabase+Insertion.h"
#import "TDDatabase+Replication.h"
#import "TDPusher.h"
#import "TDPuller.h"
#import "TDView.h"
#import "TDOAuth1Authorizer.h"
#import "TDInternal.h"
#import "TDMisc.h"
#import "MYBlockUtils.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif


NSString* const kTDReplicatorDatabaseName = @"_replicator";


@interface TDReplicatorManager ()
- (BOOL) validateRevision: (TDRevision*)newRev context: (id<TDValidationContext>)context;
- (void) processAllDocs;
@end


@implementation TDReplicatorManager


- (id) initWithDatabaseManager: (TDDatabaseManager*)dbManager {
    self = [super init];
    if (self) {
        _dbManager = dbManager;
        _replicatorDB = [[dbManager databaseNamed: kTDReplicatorDatabaseName] retain];
        if (!_replicatorDB) {
            [self release];
            return nil;
        }
        Assert(_replicatorDB);
        _thread = [NSThread currentThread];
    }
    return self;
}


- (void)dealloc {
    [self stop];
    [_replicatorDB release];
    [super dealloc];
}


- (void) start {
    [_replicatorDB defineValidation: @"TDReplicatorManager" asBlock:
         ^BOOL(TDRevision *newRevision, id<TDValidationContext> context) {
             return [self validateRevision: newRevision context: context];
         }];
    [self processAllDocs];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(dbChanged:) 
                                                 name: TDDatabaseChangeNotification
                                               object: _replicatorDB];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(someDbDeleted:)
                                                 name: TDDatabaseWillBeDeletedNotification
                                               object: nil];
#if TARGET_OS_IPHONE
    // Register for foreground/background transition notifications, on iOS:
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(appForegrounding:)
                                                 name: UIApplicationWillEnterForegroundNotification
                                               object: nil];
#endif
    
}


- (void) stop {
    LogTo(TDServer, @"STOP %@", self);
    [_replicatorDB defineValidation: @"TDReplicatorManager" asBlock: nil];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_replicatorsByDocID release];
    _replicatorsByDocID = nil;
}


- (NSString*) docIDForReplicator: (TDReplicator*)repl {
    return [[_replicatorsByDocID allKeysForObject: repl] lastObject];
}


// Replication 'source' or 'target' property may be a string or a dictionary. Normalize to dict form
static NSDictionary* parseSourceOrTarget(NSDictionary* properties, NSString* key) {
    id value = properties[key];
    if ([value isKindOfClass: [NSDictionary class]])
        return value;
    else if ([value isKindOfClass: [NSString class]])
        return $dict({@"url", value});
    else
        return nil;
}


- (TDStatus) parseReplicatorProperties: (NSDictionary*)properties
                            toDatabase: (TDDatabase**)outDatabase   // may be NULL
                                remote: (NSURL**)outRemote          // may be NULL
                                isPush: (BOOL*)outIsPush
                          createTarget: (BOOL*)outCreateTarget
                               headers: (NSDictionary**)outHeaders
                            authorizer: (id<TDAuthorizer>*)outAuthorizer
{
    // http://wiki.apache.org/couchdb/Replication
    NSDictionary* sourceDict = parseSourceOrTarget(properties, @"source");
    NSDictionary* targetDict = parseSourceOrTarget(properties, @"target");
    NSString* source = sourceDict[@"url"];
    NSString* target = targetDict[@"url"];
    if (!source || !target)
        return kTDStatusBadRequest;

    *outCreateTarget = [$castIf(NSNumber, properties[@"create_target"]) boolValue];
    *outIsPush = NO;
    TDDatabase* db = nil;
    NSDictionary* remoteDict = nil;
    if ([TDDatabaseManager isValidDatabaseName: source]) {
        if (outDatabase)
            db = [_dbManager existingDatabaseNamed: source];
        remoteDict = targetDict;
        *outIsPush = YES;
    } else {
        if (![TDDatabaseManager isValidDatabaseName: target])
            return kTDStatusBadID;
        remoteDict = sourceDict;
        if (outDatabase) {
            if (*outCreateTarget) {
                db = [_dbManager databaseNamed: target];
                if (![db open])
                    return kTDStatusDBError;
            } else {
                db = [_dbManager existingDatabaseNamed: target];
            }
        }
    }
    NSURL* remote = [NSURL URLWithString: remoteDict[@"url"]];
    if (![@[@"http", @"https", @"touchdb"] containsObject: remote.scheme.lowercaseString])
        return kTDStatusBadRequest;
    if (outDatabase) {
        *outDatabase = db;
        if (!db)
            return kTDStatusNotFound;
    }
    if (outRemote)
        *outRemote = remote;
    if (outHeaders)
        *outHeaders = $castIf(NSDictionary, remoteDict[@"headers"]);
    
    if (outAuthorizer) {
        *outAuthorizer = nil;
        NSDictionary* auth = $castIf(NSDictionary, remoteDict[@"auth"]);
        NSDictionary* oauth = $castIf(NSDictionary, auth[@"oauth"]);
        if (oauth) {
            NSString* consumerKey = $castIf(NSString, oauth[@"consumer_key"]);
            NSString* consumerSec = $castIf(NSString, oauth[@"consumer_secret"]);
            NSString* token = $castIf(NSString, oauth[@"token"]);
            NSString* tokenSec = $castIf(NSString, oauth[@"token_secret"]);
            NSString* sigMethod = $castIf(NSString, oauth[@"signature_method"]);
            *outAuthorizer = [[[TDOAuth1Authorizer alloc] initWithConsumerKey: consumerKey
                                                               consumerSecret: consumerSec
                                                                        token: token
                                                                  tokenSecret: tokenSec
                                                              signatureMethod: sigMethod]
                              autorelease];
            if (!*outAuthorizer)
                return kTDStatusBadRequest;
        }
    }
    
    return kTDStatusOK;
}


#pragma mark - CRUD:


// Validation function for the _replicator database:
- (BOOL) validateRevision: (TDRevision*)newRev context: (id<TDValidationContext>)context {
    // Ignore the change if it's one I'm making myself, or if it's a deletion:
    if (_updateInProgress || newRev.deleted)
        return YES;
    
    // First make sure the basic properties are valid:
    NSDictionary* newProperties = newRev.properties;
    LogTo(Sync, @"ReplicatorManager: Validating %@: %@", newRev, newProperties);
    BOOL push, createTarget;
    if ([self parseReplicatorProperties: newProperties toDatabase: NULL
                                 remote: NULL isPush: &push createTarget: &createTarget
                                headers: NULL
                             authorizer: NULL] >= 300) {
        context.errorMessage = @"Invalid replication parameters";
        return NO;
    }
    
    // Only certain keys can be changed or removed:
    NSSet* deletableProperties = [NSSet setWithObjects: @"_replication_state", nil];
    NSSet* mutableProperties = [NSSet setWithObjects: @"filter", @"query_params",
                                                      @"heartbeat", @"feed", nil];
    NSSet* partialMutableProperties = [NSSet setWithObjects:@"target", @"source", nil];
    return [context enumerateChanges: ^BOOL(NSString *key, id oldValue, id newValue) {
        if (![context currentRevision])
            return ![key hasPrefix: @"_"];
        
        // allow change of 'headers' and 'auth' in target and source
        if ([partialMutableProperties containsObject:key]) {
            NSDictionary *old = $castIf(NSDictionary, oldValue);
            NSDictionary *nuu = $castIf(NSDictionary, newValue);
            if ([oldValue isKindOfClass:[NSString class]]) {
                old = @{@"url": oldValue};
            }
            if ([newValue isKindOfClass:[NSString class]]) {
                nuu = @{@"url": newValue};
            }
            NSMutableSet* changedKeys = [NSMutableSet set];
            for (NSString *subKey in old.allKeys) {
                if (!$equal(old[subKey], nuu[subKey])) {
                    [changedKeys addObject:subKey];
                }
            }
            for (NSString *subKey in nuu.allKeys) {
                if (!old[subKey]) {
                    [changedKeys addObject:subKey];
                }
            }
            NSSet* mutableSubProperties = [NSSet setWithObjects:@"headers", @"auth", nil];
            [changedKeys minusSet:mutableSubProperties];
            return [changedKeys count] == 0;
        }
        
        NSSet* allowed = newValue ? mutableProperties : deletableProperties;
        return [allowed containsObject: key];
    }];
}


// PUT a change to a replication document, retrying if there are conflicts:
- (TDStatus) updateDoc: (TDRevision*)currentRev
        withProperties: (NSDictionary*)updates 
{
    LogTo(Sync, @"ReplicatorManager: Updating %@ with %@", currentRev, updates);
    Assert(currentRev.revID);
    TDStatus status;
    do {
        // Create an updated revision by merging in the updates:
        NSDictionary* currentProperties = currentRev.properties;
        NSMutableDictionary* updatedProperties = [[currentProperties mutableCopy] autorelease];
        [updatedProperties addEntriesFromDictionary: updates];
        if ($equal(updatedProperties, currentProperties)) {
            status = kTDStatusOK;     // this is a no-op change
            break;
        }
        TDRevision* updatedRev = [TDRevision revisionWithProperties: updatedProperties];
        
        // Attempt to PUT the updated revision:
        _updateInProgress = YES;
        @try {
            [_replicatorDB putRevision: updatedRev prevRevisionID: currentRev.revID
                         allowConflict: NO status: &status];
        } @finally {
            _updateInProgress = NO;
        }
        
        if (status == kTDStatusConflict) {
            // Conflict -- doc has been updated, get the latest revision & try again:
            TDStatus status2;
            currentRev = [_replicatorDB getDocumentWithID: currentRev.docID
                                               revisionID: nil options: 0
                                                   status: &status2];
            if (!currentRev)
                status = status2;
        }
    } while (status == kTDStatusConflict);
    
    if (TDStatusIsError(status))
        Warn(@"TDReplicatorManager: Error %d updating _replicator doc %@", status, currentRev);
    return status;
}


- (void) updateDoc: (TDRevision*)rev forReplicator: (TDReplicator*)repl {
    NSString* state;
    if (repl.running)
        state = @"triggered";
    else if (repl.error)
        state = @"error";
    else
        state = @"completed";
    
    NSMutableDictionary* update = $mdict({@"_replication_id", repl.sessionID});
    if (!$equal(state, rev[@"_replication_state"])) {
        update[@"_replication_state"] = state;
        update[@"_replication_state_time"] = @(time(NULL));
    }
    [self updateDoc: rev withProperties: update];
}


// A replication document has been created, so create the matching TDReplicator:
- (void) processInsertion: (TDRevision*)rev {
    if (_replicatorsByDocID[rev.docID])
        return;
    LogTo(Sync, @"ReplicatorManager: %@ was created", rev);
    NSDictionary* properties = rev.properties;
    TDDatabase* localDb;
    NSURL* remote;
    BOOL push, createTarget;
    NSDictionary* headers;
    id<TDAuthorizer> authorizer;
    TDStatus status = [self parseReplicatorProperties: properties
                                           toDatabase: &localDb remote: &remote
                                               isPush: &push
                                         createTarget: &createTarget
                                              headers: &headers
                                           authorizer: &authorizer];
    if (TDStatusIsError(status)) {
        Warn(@"TDReplicatorManager: Can't find replication endpoints for %@", properties);
        return;
    }
    
    BOOL continuous = [$castIf(NSNumber, properties[@"continuous"]) boolValue];
    LogTo(Sync, @"TDReplicatorManager creating (remote=%@, push=%d, create=%d, continuous=%d)",
          remote, push, createTarget, continuous);
    TDReplicator* repl = [localDb replicatorWithRemoteURL: remote
                                                     push: push
                                               continuous: continuous];
    if (!repl)
        return;
    if (!_replicatorsByDocID)
        _replicatorsByDocID = [[NSMutableDictionary alloc] init];
    _replicatorsByDocID[rev.docID] = repl;
    NSString* replicationID = properties[@"_replication_id"] ?: TDCreateUUID();
    repl.sessionID = replicationID;
    repl.filterName = $castIf(NSString, properties[@"filter"]);;
    repl.filterParameters = $castIf(NSDictionary, properties[@"query_params"]);
    repl.options = properties;
    repl.requestHeaders = headers;
    repl.authorizer = authorizer;
    if (push)
        ((TDPusher*)repl).createTarget = createTarget;
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(replicatorChanged:)
                                                 name: nil
                                               object: repl];

    [repl start];
    [self updateDoc: rev forReplicator: repl];
}


// A replication document has been changed:
- (void) processUpdate: (TDRevision*)rev {
    if (!rev[@"_replication_state"]) {
        // Client deleted the _replication_state property; restart the replicator:
        LogTo(Sync, @"ReplicatorManager: Restarting replicator for %@", rev);
        TDReplicator* repl = _replicatorsByDocID[rev.docID];
        if (repl) {
            [repl.db stopAndForgetReplicator: repl];
            [_replicatorsByDocID removeObjectForKey: rev.docID];
        }
        [self processInsertion: rev];
    }
}


// A replication document has been deleted:
- (void) processDeletion: (TDRevision*)rev ofReplicator: (TDReplicator*)repl {
    LogTo(Sync, @"ReplicatorManager: %@ was deleted", rev);
    [_replicatorsByDocID removeObjectForKey: rev.docID];
    [repl stop];
}


#pragma mark - NOTIFICATIONS:


- (void) processRevision: (TDRevision*)rev {
    if (rev.generation == 1)
        [self processInsertion: rev];
    else
        [self processUpdate: rev];
}


// Create TDReplications for all documents at startup:
- (void) processAllDocs {
    if (!_replicatorDB.exists)
        return;
    [_replicatorDB open];
    LogTo(Sync, @"ReplicatorManager scanning existing _replicator docs...");
    TDQueryOptions options = kDefaultTDQueryOptions;
    options.includeDocs = YES;
    NSArray* allDocs = [_replicatorDB getAllDocs: &options][@"rows"];
    for (NSDictionary* row in allDocs) {
        NSDictionary* docProps = row[@"doc"];
        NSString* state = docProps[@"_replication_state"];
        if (state==nil || $equal(state, @"triggered") ||
                    [docProps[@"continuous"] boolValue]) {
            [self processInsertion: [TDRevision revisionWithProperties: docProps]];
        }
    }
    LogTo(Sync, @"ReplicatorManager done scanning.");
}


- (void) appForegrounding: (NSNotification*)n {
    // Danger: This is called on the main thread!
    MYOnThread(_thread, ^{
        LogTo(Sync, @"App activated -- restarting all replications");
        [self processAllDocs];
    });
}


// Notified that a _replicator database document has been created/updated/deleted:
- (void) dbChanged: (NSNotification*)n {
    if (_updateInProgress)
        return;
    TDRevision* rev = (n.userInfo)[@"rev"];
    LogTo(SyncVerbose, @"ReplicatorManager: %@ %@", n.name, rev);
    NSString* docID = rev.docID;
    if ([docID hasPrefix: @"_"])
        return;
    if (rev.deleted) {
        TDReplicator* repl = _replicatorsByDocID[docID];
        if (repl)
            [self processDeletion: rev ofReplicator: repl];
    } else {
        if ([_replicatorDB loadRevisionBody: rev options: 0])
            [self processRevision: rev];
        else
            Warn(@"Unable to load body of %@", rev);
    }
}


// Notified that a TDReplicator has changed status or stopped:
- (void) replicatorChanged: (NSNotification*)n {
    TDReplicator* repl = n.object;
    LogTo(SyncVerbose, @"ReplicatorManager: %@ %@", n.name, repl);
    NSString* docID = [self docIDForReplicator: repl];
    if (!docID)
        return;  // If it's not a persistent replicator
    TDRevision* rev = [_replicatorDB getDocumentWithID: docID revisionID: nil];
    
    [self updateDoc: rev forReplicator: repl];
    
    if ($equal(n.name, TDReplicatorStoppedNotification)) {
        // Replicator has stopped:
        [[NSNotificationCenter defaultCenter] removeObserver: self name: nil object: repl];
        [_replicatorsByDocID removeObjectForKey: docID];
    }
}


// Notified that some database is being deleted; delete any associated replication document:
- (void) someDbDeleted: (NSNotification*)n {
    if (!_replicatorDB.exists)
        return;
    TDDatabase* db = n.object;
    if ([_dbManager.allOpenDatabases indexOfObjectIdenticalTo: db] == NSNotFound)
        return;
    NSString* dbName = db.name;
    
    TDQueryOptions options = kDefaultTDQueryOptions;
    options.includeDocs = YES;
    NSArray* allDocs = [_replicatorDB getAllDocs: &options][@"rows"];
    for (NSDictionary* row in allDocs) {
        NSDictionary* docProps = row[@"doc"];
        NSString* source = $castIf(NSString, docProps[@"source"]);
        NSString* target = $castIf(NSString, docProps[@"target"]);
        if ([source isEqualToString: dbName] || [target isEqualToString: dbName]) {
            // Replication doc involves this database -- delete it:
            LogTo(Sync, @"ReplicatorManager deleting replication %@", docProps);
            TDRevision* delRev = [[TDRevision alloc] initWithDocID: docProps[@"_id"]
                                                             revID: nil deleted: YES];
            TDStatus status;
            if (![_replicatorDB putRevision: delRev
                             prevRevisionID: docProps[@"_rev"]
                              allowConflict: NO status: &status]) {
                Warn(@"TDReplicatorManager: Couldn't delete replication doc %@", docProps);
            }
            [delRev release];
        }
    }
}


@end
