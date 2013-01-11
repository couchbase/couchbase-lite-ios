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
#import "TD_Server.h"
#import <TouchDB/TD_Database.h>
#import "TD_Database+Insertion.h"
#import "TD_Database+Replication.h"
#import "TDPusher.h"
#import "TDPuller.h"
#import "TD_View.h"
#import "TDInternal.h"
#import "TDMisc.h"
#import "MYBlockUtils.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif


NSString* const kTDReplicatorDatabaseName = @"_replicator";


@interface TDReplicatorManager ()
- (BOOL) validateRevision: (TD_Revision*)newRev context: (id<TD_ValidationContext>)context;
- (void) processAllDocs;
@end


@implementation TDReplicatorManager


- (id) initWithDatabaseManager: (TD_DatabaseManager*)dbManager {
    self = [super init];
    if (self) {
        _dbManager = dbManager;
        _replicatorDB = [dbManager databaseNamed: kTDReplicatorDatabaseName];
        if (!_replicatorDB) {
            return nil;
        }
        Assert(_replicatorDB);
        _thread = [NSThread currentThread];
    }
    return self;
}


- (void)dealloc {
    [self stop];
}


- (void) start {
    [_replicatorDB defineValidation: @"TDReplicatorManager" asBlock:
         ^BOOL(TD_Revision *newRevision, id<TD_ValidationContext> context) {
             return [self validateRevision: newRevision context: context];
         }];
    [self processAllDocs];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(dbChanged:) 
                                                 name: TD_DatabaseChangeNotification
                                               object: _replicatorDB];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(someDbDeleted:)
                                                 name: TD_DatabaseWillBeDeletedNotification
                                               object: nil];
#if TARGET_OS_IPHONE
    // Register for foreground/background transition notifications, on iOS:
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(appForegrounding:)
                                                 name: UIApplicationWillEnterForegroundNotification
                                               object: nil];
#endif
    
}


- (void) stop {
    LogTo(TD_Server, @"STOP %@", self);
    [_replicatorDB defineValidation: @"TDReplicatorManager" asBlock: nil];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    _replicatorsByDocID = nil;
}


- (NSString*) docIDForReplicator: (TDReplicator*)repl {
    return [[_replicatorsByDocID allKeysForObject: repl] lastObject];
}


#pragma mark - CRUD:


// Validation function for the _replicator database:
- (BOOL) validateRevision: (TD_Revision*)newRev context: (id<TD_ValidationContext>)context {
    // Ignore the change if it's one I'm making myself, or if it's a deletion:
    if (_updateInProgress || newRev.deleted)
        return YES;
    
    // First make sure the basic properties are valid:
    NSDictionary* newProperties = newRev.properties;
    LogTo(Sync, @"ReplicatorManager: Validating %@: %@", newRev, newProperties);
    if ([_dbManager validateReplicatorProperties: newProperties] >= 300) {
        context.errorMessage = @"Invalid replication parameters";
        return NO;
    }
    
    // Only certain keys can be changed or removed:
    NSSet* deletableProperties = [NSSet setWithObjects: @"_replication_state", nil];
    NSSet* mutableProperties = [NSSet setWithObjects: @"filter", @"query_params",
                                                      @"heartbeat", @"feed", @"reset", nil];
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
- (TDStatus) updateDoc: (TD_Revision*)currentRev
        withProperties: (NSDictionary*)updates 
{
    LogTo(Sync, @"ReplicatorManager: Updating %@ with %@", currentRev, updates);
    Assert(currentRev.revID);
    TDStatus status;
    do {
        // Create an updated revision by merging in the updates:
        NSDictionary* currentProperties = currentRev.properties;
        NSMutableDictionary* updatedProperties = [currentProperties mutableCopy];
        [updatedProperties addEntriesFromDictionary: updates];
        [updatedProperties removeObjectForKey: @"reset"];   // reset is one-shot, so take it out now
        
        if ($equal(updatedProperties, currentProperties)) {
            status = kTDStatusOK;     // this is a no-op change
            break;
        }
        TD_Revision* updatedRev = [TD_Revision revisionWithProperties: updatedProperties];
        
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


- (void) updateDoc: (TD_Revision*)rev forReplicator: (TDReplicator*)repl {
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
- (void) processInsertion: (TD_Revision*)rev {
    if (_replicatorsByDocID[rev.docID])
        return;
    LogTo(Sync, @"ReplicatorManager: %@ was created", rev);
    NSDictionary* properties = rev.properties;
    TDReplicator* repl = [_dbManager replicatorWithProperties: properties status: NULL];
    if (!repl) {
        Warn(@"TDReplicatorManager: Can't create replicator for %@", properties);
        return;
    }
    NSString* replicationID = properties[@"_replication_id"] ?: TDCreateUUID();
    repl.sessionID = replicationID;
    
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
- (void) processUpdate: (TD_Revision*)rev {
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
- (void) processDeletion: (TD_Revision*)rev ofReplicator: (TDReplicator*)repl {
    LogTo(Sync, @"ReplicatorManager: %@ was deleted", rev);
    [_replicatorsByDocID removeObjectForKey: rev.docID];
    [repl stop];
}


#pragma mark - NOTIFICATIONS:


- (void) processRevision: (TD_Revision*)rev {
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
            [self processInsertion: [TD_Revision revisionWithProperties: docProps]];
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
    TD_Revision* rev = (n.userInfo)[@"rev"];
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
    TD_Revision* rev = [_replicatorDB getDocumentWithID: docID revisionID: nil];
    
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
    TD_Database* db = n.object;
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
            TD_Revision* delRev = [[TD_Revision alloc] initWithDocID: docProps[@"_id"]
                                                             revID: nil deleted: YES];
            TDStatus status;
            if (![_replicatorDB putRevision: delRev
                             prevRevisionID: docProps[@"_rev"]
                              allowConflict: NO status: &status]) {
                Warn(@"TDReplicatorManager: Couldn't delete replication doc %@", docProps);
            }
        }
    }
}


@end
