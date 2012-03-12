//
//  TDPuller.m
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDPuller.h"
#import "TDDatabase+Insertion.h"
#import "TDDatabase+Replication.h"
#import "TDRevision.h"
#import "TDChangeTracker.h"
#import "TDBatcher.h"
#import "TDMultipartDownloader.h"
#import "TDSequenceMap.h"
#import "TDInternal.h"
#import "TDMisc.h"
#import "ExceptionUtils.h"


// Maximum number of revisions to fetch simultaneously
#define kMaxOpenHTTPConnections 8


@interface TDPuller () <TDChangeTrackerClient>
- (void) pullRemoteRevisions;
- (void) pullRemoteRevision: (TDRevision*)rev;
- (void) insertDownloads: (NSArray*)downloads;
@end

static NSString* joinQuotedEscaped(NSArray* strings);


@implementation TDPuller


- (void)dealloc {
    [_changeTracker stop];
    [_changeTracker release];
    [_revsToPull release];
    [_deletedRevsToPull release];
    [_downloadsToInsert release];
    [_pendingSequences release];
    [super dealloc];
}


- (void) beginReplicating {
    Assert(!_changeTracker);
    if (!_downloadsToInsert) {
        _downloadsToInsert = [[TDBatcher alloc] initWithCapacity: 100 delay: 0.25
                                                  processor: ^(NSArray *downloads) {
                                                      [self insertDownloads: downloads];
                                                  }];
    }
    
    [_pendingSequences release];
    _pendingSequences = [[TDSequenceMap alloc] init];
    LogTo(SyncVerbose, @"%@ starting ChangeTracker with since=%@", self, _lastSequence);
    _changeTracker = [[TDChangeTracker alloc]
                                   initWithDatabaseURL: _remote
                                                  mode: (_continuous ? kLongPoll :kOneShot)
                                          lastSequence: _lastSequence
                                                client: self];
    _changeTracker.filterName = _filterName;
    _changeTracker.filterParameters = _filterParameters;
    [_changeTracker start];
    if (!_continuous)
        [self asyncTaskStarted];
}


- (void) stop {
    if (!_running)
        return;
    _changeTracker.client = nil;  // stop it from calling my -changeTrackerStopped
    [_changeTracker stop];
    setObj(&_changeTracker, nil);
    setObj(&_revsToPull, nil);
    setObj(&_deletedRevsToPull, nil);
    [super stop];
}


- (BOOL) goOffline {
    if (![super goOffline])
        return NO;
    [_changeTracker stop];
    return YES;
}


// Got a _changes feed entry from the TDChangeTracker.
- (void) changeTrackerReceivedChange: (NSDictionary*)change {
    NSString* lastSequenceID = [[change objectForKey: @"seq"] description];
    NSString* docID = [change objectForKey: @"id"];
    if (!docID)
        return;
    if (![TDDatabase isValidDocumentID: docID]) {
        Warn(@"%@: Received invalid doc ID from _changes: %@", self, change);
        return;
    }
    BOOL deleted = [[change objectForKey: @"deleted"] isEqual: (id)kCFBooleanTrue];
    NSArray* changes = $castIf(NSArray, [change objectForKey: @"changes"]);
    for (NSDictionary* changeDict in changes) {
        @autoreleasepool {
            // Push each revision info to the inbox
            NSString* revID = $castIf(NSString, [changeDict objectForKey: @"rev"]);
            if (!revID)
                continue;
            TDPulledRevision* rev = [[TDPulledRevision alloc] initWithDocID: docID revID: revID
                                                                    deleted: deleted];
            // Remember its remote sequence ID (opaque), and make up a numeric sequence based
            // on the order in which it appeared in the _changes feed:
            rev.remoteSequenceID = lastSequenceID;
            [self addToInbox: rev];
            [rev release];
        }
    }
    self.changesTotal += changes.count;
}


- (void) changeTrackerStopped:(TDChangeTracker *)tracker {
    NSError* error = tracker.error;
    LogTo(Sync, @"%@: ChangeTracker stopped; error=%@", self, error.description);
    
    [_changeTracker release];
    _changeTracker = nil;
    
    if (TDIsOfflineError(error))
        [self goOffline];
    else if (!_error && error)
        self.error = error;
    
    [_batcher flush];

    if (!_continuous)
        [self asyncTasksFinished: 1];
}


// Process a bunch of remote revisions from the _changes feed at once
- (void) processInbox: (TDRevisionList*)inbox {
    // Ask the local database which of the revs are not known to it:
    LogTo(SyncVerbose, @"%@: Looking up %@", self, inbox);
    NSString* lastInboxSequence = [inbox.allRevisions.lastObject remoteSequenceID];
    NSUInteger total = _changesTotal - inbox.count;
    if (![_db findMissingRevisions: inbox]) {
        Warn(@"%@ failed to look up local revs", self);
        inbox = nil;
    }
    if (_changesTotal != total + inbox.count)
        self.changesTotal = total + inbox.count;
    
    if (inbox.count == 0) {
        // Nothing to do; just count all the revisions as processed.
        // Instead of adding and immediately removing the revs to _pendingSequences,
        // just do the latest one (equivalent but faster):
        LogTo(SyncVerbose, @"%@: no new remote revisions to fetch", self);
        SequenceNumber seq = [_pendingSequences addValue: lastInboxSequence];
        [_pendingSequences removeSequence: seq];
        self.lastSequence = _pendingSequences.checkpointedValue;
        return;
    }
    
    LogTo(Sync, @"%@ fetching %u remote revisions...", self, inbox.count);
    LogTo(SyncVerbose, @"%@ fetching remote revisions %@", self, inbox.allRevisions);
    
    // Dump the revs into the queues of revs to pull from the remote db:
    for (TDPulledRevision* rev in inbox.allRevisions) {
        NSMutableArray** pQueue = rev.deleted ? &_deletedRevsToPull : &_revsToPull;
        if (!*pQueue)
            *pQueue = [[NSMutableArray alloc] initWithCapacity: 100];
        [*pQueue addObject: rev];
        rev.sequence = [_pendingSequences addValue: rev.remoteSequenceID];
    }
    
    [self pullRemoteRevisions];
}


// Start up some HTTP GETs, within our limit on the maximum simultaneous number
- (void) pullRemoteRevisions {
    while (_httpConnectionCount < kMaxOpenHTTPConnections) {
        // Prefer to pull an existing revision over a deleted one:
        NSMutableArray* queue = _revsToPull;
        if (queue.count == 0) {
            queue = _deletedRevsToPull;
            if (queue.count == 0)
                break;  // both queues are empty
        }
        [self pullRemoteRevision: [queue objectAtIndex: 0]];
        [queue removeObjectAtIndex: 0];
    }
}


// Fetches the contents of a revision from the remote db, including its parent revision ID.
// The contents are stored into rev.properties.
- (void) pullRemoteRevision: (TDRevision*)rev
{
    [self asyncTaskStarted];
    ++_httpConnectionCount;
    
    // Construct a query. We want the revision history, and the bodies of attachments that have
    // been added since the latest revisions we have locally.
    // See: http://wiki.apache.org/couchdb/HTTP_Document_API#Getting_Attachments_With_a_Document
    NSString* path = $sprintf(@"/%@?rev=%@&revs=true&attachments=true",
                              TDEscapeID(rev.docID), TDEscapeID(rev.revID));
    NSArray* knownRevs = [_db getPossibleAncestorRevisionIDs: rev];
    if (knownRevs.count > 0)
        path = [path stringByAppendingFormat: @"&atts_since=%@", joinQuotedEscaped(knownRevs)];
    
    LogTo(SyncVerbose, @"%@: GET .%@", self, path);
    NSString* urlStr = [_remote.absoluteString stringByAppendingString: path];
    [[[TDMultipartDownloader alloc] initWithURL: [NSURL URLWithString: urlStr]
                                       database: _db
                                       revision: rev
                                   onCompletion:
        ^(TDMultipartDownloader* download, NSError *error) {
            // OK, now we've got the response revision:
            if (error) {
                self.error = error;
                self.changesProcessed++;
            } else {
                rev.properties = download.document;
                // Add to batcher ... eventually it will be fed to -insertRevisions:.
                [_downloadsToInsert queueObject: download];
                [self asyncTaskStarted];
            }
            
            // Note that we've finished this task:
            [self asyncTasksFinished: 1];
            --_httpConnectionCount;
            // Start another task if there are still revisions waiting to be pulled:
            [self pullRemoteRevisions];
        }
     ] autorelease];
}


// This will be called when _downloadsToInsert fills up:
- (void) insertDownloads:(NSArray *)downloads {
    LogTo(Sync, @"%@ inserting %u revisions...", self, downloads.count);
    
    /* Updating self.lastSequence is tricky. It needs to be the received sequence ID of the revision for which we've successfully received and inserted (or rejected) it and all previous received revisions. That way, next time we can start tracking remote changes from that sequence ID and know we haven't missed anything. */
    /* FIX: The current code below doesn't quite achieve that: it tracks the latest sequence ID we've successfully processed, but doesn't handle failures correctly across multiple calls to -insertRevisions. I think correct behavior will require keeping an NSMutableIndexSet to track the fake-sequences of all processed revisions; then we can find the first missing index in that set and not advance lastSequence past the revision with that fake-sequence. */
    
    downloads = [downloads sortedArrayUsingComparator: ^(id dl1, id dl2) {
        return TDSequenceCompare( [[dl1 revision] sequence], [[dl2 revision] sequence]);
    }];
    
    [_db beginTransaction];
    BOOL success = NO;
    @try{
        for (TDMultipartDownloader* download in downloads) {
            @autoreleasepool {
                TDPulledRevision* rev = (TDPulledRevision*)download.revision;
                SequenceNumber fakeSequence = rev.sequence;
                NSArray* history = [TDDatabase parseCouchDBRevisionHistory: rev.properties];
                if (!history) {
                    Warn(@"%@: Missing revision history in response for %@", self, rev);
                    self.error = TDHTTPError(502, nil);
                    continue;
                }
                LogTo(SyncVerbose, @"%@ inserting %@ %@",
                      self, rev.docID, [history my_compactDescription]);

                // Insert the revision:
                int status = [_db forceInsert: rev revisionHistory: history source: _remote];
                if (status >= 300) {
                    if (status == 403)
                        LogTo(Sync, @"%@: Remote rev failed validation: %@", self, rev);
                    else {
                        Warn(@"%@ failed to write %@: status=%d", self, rev, status);
                        self.error = TDHTTPError(status, nil);
                        continue;
                    }
                }
                
                // Mark this revision's fake sequence as processed:
                [_pendingSequences removeSequence: fakeSequence];
            }
        }
        
        LogTo(Sync, @"%@ finished inserting %u revisions", self, downloads.count);
        
        // Checkpoint:
        self.lastSequence = _pendingSequences.checkpointedValue;
        
        success = YES;
    } @catch (NSException *x) {
        MYReportException(x, @"%@: Exception inserting revisions", self);
    } @finally {
        [_db endTransaction: success];
    }
    
    [self asyncTasksFinished: downloads.count];
    self.changesProcessed += downloads.count;
}


@end



@implementation TDPulledRevision

@synthesize remoteSequenceID=_remoteSequenceID;

- (void) dealloc {
    [_remoteSequenceID release];
    [super dealloc];
}

@end



static NSString* joinQuotedEscaped(NSArray* strings) {
    if (strings.count == 0)
        return @"[]";
    NSData* json = [NSJSONSerialization dataWithJSONObject: strings options: 0 error: NULL];
    return TDEscapeURLParam([json my_UTF8ToString]);
}
