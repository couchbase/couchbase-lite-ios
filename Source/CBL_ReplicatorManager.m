//
//  CBL_ReplicatorManager.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/15/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
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

#import "CouchbaseLitePrivate.h"
#import "CBL_ReplicatorManager.h"
#import "CouchbaseLitePrivate.h"
#import "CBL_Server.h"
#import "CBLDatabase.h"
#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+Replication.h"
#import "CBLDatabaseChange.h"
#import "CBL_Pusher.h"
#import "CBL_Puller.h"
#import "CBLView+Internal.h"
#import "CBLRevision.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "MYBlockUtils.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif


NSString* const kCBL_ReplicatorDatabaseName = @"_replicator";


@implementation CBL_ReplicatorManager


- (instancetype) initWithDatabaseManager: (CBLManager*)dbManager {
    self = [super init];
    if (self) {
        _dbManager = dbManager;
        // Instantiate db but don't open/create the file yet:
        _replicatorDB = [dbManager _databaseNamed: kCBL_ReplicatorDatabaseName
                                        mustExist: NO error: NULL];
        if (!_replicatorDB) {
            return nil;
        }
        Assert(_replicatorDB);
    }
    return self;
}


- (void)dealloc {
    [self stop];
}


- (void) start {
    [_replicatorDB open: nil];
    __weak CBL_ReplicatorManager* weakSelf = self;
    [_replicatorDB setValidationNamed: @"CBL_ReplicatorManager" asBlock:
         ^BOOL(CBLSavedRevision *newRevision, id<CBLValidationContext> context) {
             return [weakSelf validateRevision: newRevision context: context];
         }];
    [self processAllDocs];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(dbChanged:) 
                                                 name: CBL_DatabaseChangesNotification
                                               object: _replicatorDB];
#if TARGET_OS_IPHONE
    // Register for foreground/background transition notifications, on iOS:
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(appForegrounding:)
                                                 name: UIApplicationWillEnterForegroundNotification
                                               object: nil];
#endif
    
}


- (void) stop {
    LogTo(CBL_Server, @"STOP %@", self);
    [_replicatorDB setValidationNamed: @"CBL_ReplicatorManager" asBlock: nil];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    _replicatorsByDocID = nil;
}


#pragma mark - CRUD:


// Validation function for the _replicator database:
- (BOOL) validateRevision: (CBLSavedRevision*)newRev context: (id<CBLValidationContext>)context {
    // Ignore the change if it's one I'm making myself, or if it's a deletion:
    if (_updateInProgress || newRev.isDeletion)
        return YES;
    
    // First make sure the basic properties are valid:
    NSDictionary* newProperties = newRev.properties;
    LogTo(Sync, @"ReplicatorManager: Validating %@: %@", newRev, newProperties);
    if ([_dbManager validateReplicatorProperties: newProperties] >= 300) {
        context.errorMessage = @"Invalid replication parameters";
        return NO;
    }
    
    // Only certain keys can be changed or removed:
    NSSet* deletableProperties = [NSSet setWithObjects: @"_replication_state", @"continuous", nil];
    NSSet* mutableProperties = [NSSet setWithObjects: @"filter", @"query_params",
                                              @"heartbeat", @"feed", @"reset", @"continuous",
                                              @"headers", @"network", nil];
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

        return [mutableProperties containsObject: key] ||
                (newValue == nil && [deletableProperties containsObject: key]);
    }];
}


// PUT a change to a replication document, retrying if there are conflicts:
- (CBLStatus) updateDoc: (CBL_Revision*)currentRev
        withProperties: (NSDictionary*)updates 
{
    LogTo(Sync, @"ReplicatorManager: Updating %@ with %@", currentRev, updates);
    Assert(currentRev.revID);
    CBLStatus status;
    do {
        // Create an updated revision by merging in the updates:
        NSDictionary* currentProperties = currentRev.properties;
        NSMutableDictionary* updatedProperties = [currentProperties mutableCopy];
        [updatedProperties addEntriesFromDictionary: updates];
        [updatedProperties removeObjectForKey: @"reset"];   // reset is one-shot, so take it out now
        
        if ($equal(updatedProperties, currentProperties)) {
            status = kCBLStatusOK;     // this is a no-op change
            break;
        }
        CBL_Revision* updatedRev = [CBL_Revision revisionWithProperties: updatedProperties];
        
        // Attempt to PUT the updated revision:
        _updateInProgress = YES;
        @try {
            [_replicatorDB putRevision: updatedRev prevRevisionID: currentRev.revID
                         allowConflict: NO status: &status];
        } @finally {
            _updateInProgress = NO;
        }
        
        if (status == kCBLStatusConflict) {
            // Conflict -- doc has been updated, get the latest revision & try again:
            CBLStatus status2;
            currentRev = [_replicatorDB getDocumentWithID: currentRev.docID
                                               revisionID: nil options: 0
                                                   status: &status2];
            if (!currentRev)
                status = status2;
        }
    } while (status == kCBLStatusConflict);
    
    if (CBLStatusIsError(status) && status != kCBLStatusNotFound)
        Warn(@"CBL_ReplicatorManager: Error %d updating _replicator doc %@", status, currentRev);
    return status;
}


- (void) updateDoc: (CBL_Revision*)rev forReplicator: (CBL_Replicator*)repl {
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


// A replication document has been created, so create the matching CBL_Replicator:
- (void) processInsertion: (CBL_Revision*)rev {
    if (_replicatorsByDocID[rev.docID])
        return;
    LogTo(Sync, @"ReplicatorManager: %@ was created", rev);
    NSDictionary* properties = rev.properties;
    CBLStatus status;
    CBL_Replicator* repl = [_dbManager replicatorWithProperties: properties status: &status];
    if (!repl) {
        Warn(@"CBL_ReplicatorManager: Can't create replicator for %@ (status %d)",
             properties, status);
        return;
    }
    NSString* replicationID = properties[@"_replication_id"] ?: CBLCreateUUID();
    repl.sessionID = replicationID;
    repl.documentID = rev.docID;

    if (!_replicatorsByDocID)
        _replicatorsByDocID = [[NSMutableDictionary alloc] init];
    _replicatorsByDocID[rev.docID] = repl;
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(replicatorChanged:)
                                                 name: nil
                                               object: repl];

    [repl start];
    [self updateDoc: rev forReplicator: repl];
}


// A replication document has been changed:
- (void) processUpdate: (CBL_Revision*)rev {
    if (!rev[@"_replication_state"]) {
        // Client deleted the _replication_state property; restart the replicator:
        LogTo(Sync, @"ReplicatorManager: Restarting replicator for %@", rev);
        CBL_Replicator* repl = _replicatorsByDocID[rev.docID];
        if (repl) {
            [repl.db stopAndForgetReplicator: repl];
            [_replicatorsByDocID removeObjectForKey: rev.docID];
        }
        [self processInsertion: rev];
    }
}


// A replication document has been deleted:
- (void) processDeletion: (CBL_Revision*)rev ofReplicator: (CBL_Replicator*)repl {
    LogTo(Sync, @"ReplicatorManager: %@ was deleted", rev);
    [_replicatorsByDocID removeObjectForKey: rev.docID];
    [repl stop];
}


#pragma mark - NOTIFICATIONS:


- (void) processRevision: (CBL_Revision*)rev {
    if (rev.generation == 1)
        [self processInsertion: rev];
    else
        [self processUpdate: rev];
}


// Create CBLReplications for all documents at startup:
- (void) processAllDocs {
    LogTo(Sync, @"ReplicatorManager scanning existing _replicator docs...");
    CBLQueryOptions options = kDefaultCBLQueryOptions;
    options.includeDocs = YES;
    for (CBLQueryRow* row in [_replicatorDB getAllDocs: &options]) {
        NSDictionary* docProps = row.documentProperties;
        NSString* state = docProps[@"_replication_state"];
        if (state==nil || $equal(state, @"triggered") ||
                    [docProps[@"continuous"] boolValue]) {
            [self processInsertion: [CBL_Revision revisionWithProperties: docProps]];
        }
    }
    LogTo(Sync, @"ReplicatorManager done scanning.");
}


- (void) appForegrounding: (NSNotification*)n {
    // Danger: This is called on the main thread!
    [_replicatorDB doAsync: ^{
        LogTo(Sync, @"App activated -- restarting all replications");
        [self processAllDocs];
    }];
}


// Notified that a _replicator database document has been created/updated/deleted:
- (void) dbChanged: (NSNotification*)n {
    if (_updateInProgress)
        return;
    for (CBLDatabaseChange* change in n.userInfo[@"changes"]) {
        CBL_Revision* rev = change.winningRevision;
        LogTo(SyncVerbose, @"ReplicatorManager: %@ %@", n.name, rev);
        NSString* docID = rev.docID;
        if ([docID hasPrefix: @"_"])
            continue;
        if (rev.deleted) {
            CBL_Replicator* repl = _replicatorsByDocID[docID];
            if (repl)
                [self processDeletion: rev ofReplicator: repl];
        } else {
            CBLStatus status;
            rev = [_replicatorDB revisionByLoadingBody: rev options: 0 status: &status];
            if (rev)
                [self processRevision: rev];
            else
                Warn(@"Unable to load body of %@: %d", rev, status);
        }
    }
}


// Notified that a CBL_Replicator has changed status or stopped:
- (void) replicatorChanged: (NSNotification*)n {
    CBL_Replicator* repl = n.object;
    LogTo(SyncVerbose, @"ReplicatorManager: %@ %@", n.name, repl);

    for (NSString* docID in [_replicatorsByDocID allKeysForObject: repl]) {
        CBL_Revision* rev = [_replicatorDB getDocumentWithID: docID revisionID: nil];
        if (rev)
            [self updateDoc: rev forReplicator: repl];
        
        if ($equal(n.name, CBL_ReplicatorStoppedNotification)) {
            // Replicator has stopped:
            [[NSNotificationCenter defaultCenter] removeObserver: self name: nil object: repl];
            [_replicatorsByDocID removeObjectForKey: docID];
        }
    }
}


@end
