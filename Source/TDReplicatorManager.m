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
#import "TDInternal.h"
#import "TDMisc.h"


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
        Assert(_replicatorDB);
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


- (TDStatus) parseReplicatorProperties: (NSDictionary*)properties
                            toDatabase: (TDDatabase**)outDatabase   // may be NULL
                                remote: (NSURL**)outRemote          // may be NULL
                                isPush: (BOOL*)outIsPush
                          createTarget: (BOOL*)outCreateTarget;
{
    NSString* source = $castIf(NSString, [properties objectForKey: @"source"]);
    NSString* target = $castIf(NSString, [properties objectForKey: @"target"]);
    *outCreateTarget = [$castIf(NSNumber, [properties objectForKey: @"create_target"]) boolValue];
    
    if (!source || !target)
        return kTDStatusBadRequest;
    *outIsPush = NO;
    TDDatabase* db = nil;
    NSString* remoteStr;
    if ([TDDatabaseManager isValidDatabaseName: source]) {
        if (outDatabase)
            db = [_dbManager existingDatabaseNamed: source];
        remoteStr = target;
        *outIsPush = YES;
    } else {
        if (![TDDatabaseManager isValidDatabaseName: target])
            return kTDStatusBadID;
        remoteStr = source;
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
    NSURL* remote = [NSURL URLWithString: remoteStr];
    if (!remote || ![remote.scheme hasPrefix: @"http"])
        return kTDStatusBadRequest;
    if (outDatabase) {
        *outDatabase = db;
        if (!db)
            return kTDStatusNotFound;
    }
    if (outRemote)
        *outRemote = remote;
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
                                 remote: NULL isPush: &push createTarget: &createTarget] >= 300) {
        context.errorMessage = @"Invalid replication parameters";
        return NO;
    }
    
    // "_"-prefixed keys cannot be added:
    NSDictionary* curProperties = context.currentRevision.properties;
    for (NSString* key in newProperties) {
        if ([key hasPrefix: @"_"] &&
                !$equal(key, @"_id") && !$equal(key, @"_rev") &&
                !$equal([curProperties objectForKey: key], [newProperties objectForKey: key])) {
            context.errorMessage = $sprintf(@"Cannot add a '%@' property", key);
            return NO;
        }
    }
    
    // Only certain keys can be changed or removed:
    NSSet* deletableProperties = [NSSet setWithObjects: @"_replication_state", nil];
    NSSet* mutableProperties = [NSSet setWithObjects: @"filter", @"query_params", nil];
    for (NSString* key in curProperties) {
        id newValue = [newProperties objectForKey: key];
        if (!newValue && [deletableProperties containsObject: key])
            ;
        else if (![mutableProperties containsObject: key] &&
                !$equal([curProperties objectForKey: key], newValue)) {
            context.errorMessage = $sprintf(@"Cannot modify the '%@' property", key);
            return NO;
        }
    }
    return YES;
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
            currentRev = [_replicatorDB getDocumentWithID: currentRev.docID
                                               revisionID: nil options: 0];
            if (!currentRev)
                status = kTDStatusNotFound;   // doc's been deleted, apparently
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
    if (!$equal(state, [rev.properties objectForKey: @"_replication_state"])) {
        [update setObject: state forKey: @"_replication_state"];
        [update setObject: $object(time(NULL)) forKey: @"_replication_state_time"];
    }
    [self updateDoc: rev withProperties: update];
}


// A replication document has been created, so create the matching TDReplicator:
- (void) processInsertion: (TDRevision*)rev {
    LogTo(Sync, @"ReplicatorManager: %@ was created", rev);
    NSDictionary* properties = rev.properties;
    TDDatabase* localDb;
    NSURL* remote;
    BOOL push, createTarget;
    TDStatus status = [self parseReplicatorProperties: properties
                                           toDatabase: &localDb remote: &remote
                                               isPush: &push
                                         createTarget: &createTarget];
    if (TDStatusIsError(status)) {
        Warn(@"TDReplicatorManager: Can't find replication endpoints for %@", properties);
        return;
    }
    
    BOOL continuous = [$castIf(NSNumber, [properties objectForKey: @"continuous"]) boolValue];
    LogTo(Sync, @"TDReplicatorManager creating (remote=%@, push=%d, create=%d, continuous=%d)",
          remote, push, createTarget, continuous);
    TDReplicator* repl = [localDb replicatorWithRemoteURL: remote
                                                     push: push
                                               continuous: continuous];
    if (!repl)
        return;
    if (!_replicatorsByDocID)
        _replicatorsByDocID = [[NSMutableDictionary alloc] init];
    [_replicatorsByDocID setObject: repl forKey: rev.docID];
    NSString* replicationID = [properties objectForKey: @"_replication_id"] ?: TDCreateUUID();
    repl.sessionID = replicationID;
    repl.filterName = $castIf(NSString, [properties objectForKey: @"filter"]);;
    repl.filterParameters = $castIf(NSDictionary, [properties objectForKey: @"query_params"]);
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
    if (![rev.properties objectForKey: @"_replication_state"]) {
        // Client deleted the _replication_state property; restart the replicator:
        LogTo(Sync, @"ReplicatorManager: Restarting replicator for %@", rev);
        TDReplicator* repl = [_replicatorsByDocID objectForKey: rev.docID];
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
    NSArray* allDocs = [[_replicatorDB getAllDocs: &options] objectForKey: @"rows"];
    for (NSDictionary* row in allDocs) {
        NSDictionary* docProps = [row objectForKey: @"doc"];
        NSString* state = [docProps objectForKey: @"_replication_state"];
        if (state==nil || $equal(state, @"triggered"))
            [self processInsertion: [TDRevision revisionWithProperties: docProps]];
    }
    LogTo(Sync, @"ReplicatorManager done scanning.");
}


// Notified that a _replicator database document has been created/updated/deleted:
- (void) dbChanged: (NSNotification*)n {
    if (_updateInProgress)
        return;
    TDRevision* rev = [n.userInfo objectForKey: @"rev"];
    LogTo(SyncVerbose, @"ReplicatorManager: %@ %@", n.name, rev);
    NSString* docID = rev.docID;
    if ([docID hasPrefix: @"_"])
        return;
    if (rev.deleted) {
        TDReplicator* repl = [_replicatorsByDocID objectForKey: docID];
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
    TDRevision* rev = [_replicatorDB getDocumentWithID: docID revisionID: nil options: 0];
    
    [self updateDoc: rev forReplicator: repl];
    
    if ($equal(n.name, TDReplicatorStoppedNotification)) {
        // Replicator has stopped:
        [[NSNotificationCenter defaultCenter] removeObserver: self name: nil object: repl];
        [_replicatorsByDocID removeObjectForKey: docID];
    }
}



@end
