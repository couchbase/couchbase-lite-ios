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
#import <TouchDB/TDRevision.h>
#import "TDConnectionChangeTracker.h"
#import "TDAuthorizer.h"
#import "TDBatcher.h"
#import "TDMultipartDownloader.h"
#import "TDSequenceMap.h"
#import "TDInternal.h"
#import "TDMisc.h"
#import "ExceptionUtils.h"


// Maximum number of revisions to fetch simultaneously
#define kMaxOpenHTTPConnections 8

// ?limit= param for _changes feed: max # of revs to get in one batch. Smaller values reduce
// latency since we can't parse till the entire result arrives in longpoll mode. But larger
// values are more efficient because they use fewer HTTP requests.
#define kChangesFeedLimit 100u

// Maximum number of revs to fetch in a single bulk request
#define kMaxRevsToGetInBulk 50u

// Maximum number of revision IDs to pass in an "?atts_since=" query param
#define kMaxNumberOfAttsSince 50u


@interface TDPuller () <TDChangeTrackerClient>
@end


static NSString* joinQuotedEscaped(NSArray* strings);


@implementation TDPuller


- (void)dealloc {
    [_changeTracker stop];
    [_changeTracker release];
    [_revsToPull release];
    [_deletedRevsToPull release];
    [_bulkRevsToPull release];
    [_downloadsToInsert release];
    [_pendingSequences release];
    [_endingSequence release];
    [_seenSequences release];
    [super dealloc];
}


- (void) beginReplicating {
    if (!_downloadsToInsert) {
        // Note: This is a ref cycle, because the block has a (retained) reference to 'self',
        // and _downloadsToInsert retains the block, and of course I retain _downloadsToInsert.
        _downloadsToInsert = [[TDBatcher alloc] initWithCapacity: 200 delay: 1.0
                                                  processor: ^(NSArray *downloads) {
                                                      [self insertDownloads: downloads];
                                                  }];
    }
    
    // Get the current sequence number so we know when the pull has "caught up":
    [self asyncTaskStarted];
    [self sendAsyncRequest: @"GET" path: @"/" body: nil
              onCompletion:^(id result, NSError *error) {
                  if (error)
                      self.error = error;
                  else
                      [self gotEndingSequence: [result[@"update_seq"] description]];
                  [self asyncTasksFinished: 1];
              }];
    
    [_pendingSequences release];
    _pendingSequences = [[TDSequenceMap alloc] init];
    
    _seenSequences = [[NSMutableArray alloc] init];
    if (_lastSequence)
        [_seenSequences addObject: _lastSequence];
    
    [self startChangeTracker];
}


- (void) startChangeTracker {
    Assert(!_changeTracker);
    TDChangeTrackerMode mode = _continuous ? kLongPoll : kOneShot;
    
    LogTo(SyncVerbose, @"%@ starting ChangeTracker: mode=%d, since=%@", self, mode, _lastSequence);
    _changeTracker = [[TDConnectionChangeTracker alloc] initWithDatabaseURL: _remote
                                                                       mode: mode
                                                                  conflicts: YES
                                                               lastSequence: _lastSequence
                                                                     client: self];
    // Limit the number of changes to return, so we can parse the feed in parts:
    _changeTracker.limit = kChangesFeedLimit;
    _changeTracker.filterName = _filterName;
    _changeTracker.filterParameters = _filterParameters;
    _changeTracker.authorizer = _authorizer;
    unsigned heartbeat = $castIf(NSNumber, _options[@"heartbeat"]).unsignedIntValue;
    if (heartbeat >= 15000)
        _changeTracker.heartbeat = heartbeat / 1000.0;
    
    NSMutableDictionary* headers = $mdict({@"User-Agent", [TDRemoteRequest userAgentHeader]});
    [headers addEntriesFromDictionary: _requestHeaders];
    _changeTracker.requestHeaders = headers;
    
    [_changeTracker start];
    if (!_continuous)
        [self asyncTaskStarted];
}


- (void) stop {
    if (!_running)
        return;
    if (_changeTracker) {
        _changeTracker.client = nil;  // stop it from calling my -changeTrackerStopped
        [_changeTracker stop];
        if (!_continuous)
            [self asyncTasksFinished: 1]; // balances -asyncTaskStarted in -startChangeTracker
    }
    setObj(&_changeTracker, nil);
    setObj(&_revsToPull, nil);
    setObj(&_deletedRevsToPull, nil);
    setObj(&_bulkRevsToPull, nil);
    [super stop];
    
    [_downloadsToInsert flushAll];
}


- (void) stopped {
    setObj(&_downloadsToInsert, nil);
    [super stopped];
}


- (BOOL) goOnline {
    if ([super goOnline])
        return YES;
    // If we were already online (i.e. server is reachable) but got a reachability-change event,
    // tell the tracker to retry in case it's in retry mode after a transient failure. (I.e. the
    // state of the network might be better now.)
    if (_running && _online)
        [_changeTracker retry];
    return NO;
}


- (BOOL) goOffline {
    if (![super goOffline])
        return NO;
    [_changeTracker stop];
    return YES;
}


// Got a _changes feed entry from the TDChangeTracker.
- (void) changeTrackerReceivedChange: (NSDictionary*)change {
    NSString* lastSequenceID = [change[@"seq"] description];
    NSString* docID = change[@"id"];
    if (docID) {
        if ([TDDatabase isValidDocumentID: docID]) {
            BOOL deleted = [change[@"deleted"] isEqual: (id)kCFBooleanTrue];
            NSArray* changes = $castIf(NSArray, change[@"changes"]);
            for (NSDictionary* changeDict in changes) {
                @autoreleasepool {
                    // Push each revision info to the inbox
                    NSString* revID = $castIf(NSString, changeDict[@"rev"]);
                    if (!revID)
                        continue;
                    TDPulledRevision* rev = [[TDPulledRevision alloc] initWithDocID: docID revID: revID
                                                                            deleted: deleted];
                    // Remember its remote sequence ID (opaque), and make up a numeric sequence based
                    // on the order in which it appeared in the _changes feed:
                    rev.remoteSequenceID = lastSequenceID;
                    if (changes.count > 1)
                        rev.conflicted = true;
                    [self addToInbox: rev];
                    [rev release];
                }
            }
            self.changesTotal += changes.count;
        } else {
            Warn(@"%@: Received invalid doc ID from _changes: %@", self, change);
        }
    }
    [self checkIfCaughtUp: lastSequenceID];
}


// The change tracker reached EOF or an error.
- (void) changeTrackerStopped:(TDChangeTracker *)tracker {
    if (tracker != _changeTracker)
        return;
    NSError* error = tracker.error;
    LogTo(Sync, @"%@: ChangeTracker stopped; error=%@", self, error.description);
    
    [_changeTracker release];
    _changeTracker = nil;
    
    if (error) {
        if (TDIsOfflineError(error))
            [self goOffline];
        else if (!_error)
            self.error = error;
    }
    
    [_batcher flushAll];
    if (!_continuous)
        [self asyncTasksFinished: 1]; // balances -asyncTaskStarted in -startChangeTracker
}


#pragma mark - CAUGHT-UP CHECK (FOR NON-CONTINUOUS REPLICATION):


// Check whether 'sequence' has reached the _endingSequence, and if so, stop.
- (void) checkIfCaughtUp: (NSString*)sequence {
    if (!_endingSequence) {
        // Don't know the ending sequence yet, so remember all sequences we've seen:
        [_seenSequences addObject: sequence];
    } else if ($equal(sequence, _endingSequence)) {
        [self caughtUp];
    }
}

// Found out what the ending sequence is. Remember it, and check if it's already been received:
- (void) gotEndingSequence: (NSString*)endingSequence {
    LogTo(Sync, @"Ending sequence = %@", endingSequence);
    if (_endingSequence)
        return;
    _endingSequence = [endingSequence copy];
    if ([_seenSequences containsObject: _endingSequence]) 
        [self caughtUp];
    setObj(&_seenSequences, nil);
}


- (void) caughtUp {
    LogTo(Sync, @"** Caught up, at sequence %@", _endingSequence);
    if (!_continuous)
        [_changeTracker stop];
    // Might be useful to notify this fact to observers even in a continuous replication.
}


#pragma mark - REVISION CHECKING:


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
    
    LogTo(SyncVerbose, @"%@ queuing remote revisions %@", self, inbox.allRevisions);
    
    // Dump the revs into the queues of revs to pull from the remote db:
    unsigned numBulked = 0;
    for (TDPulledRevision* rev in inbox.allRevisions) {
        if (rev.generation == 1 && !rev.deleted && !rev.conflicted) {
            // Optimistically pull 1st-gen revs in bulk:
            if (!_bulkRevsToPull) 
                _bulkRevsToPull = [[NSMutableArray alloc] initWithCapacity: 100];
            [_bulkRevsToPull addObject: rev];
            ++numBulked;
        } else {
            [self queueRemoteRevision: rev];
        }
        rev.sequence = [_pendingSequences addValue: rev.remoteSequenceID];
    }
    LogTo(Sync, @"%@ queued %u remote revisions from seq=%@ (%u in bulk, %u individually)",
          self, (unsigned)inbox.count, ((TDPulledRevision*)inbox[0]).remoteSequenceID,
          numBulked, (unsigned)(inbox.count-numBulked));
    
    [self pullRemoteRevisions];
}


// Add a revision to the appropriate queue of revs to individually GET
- (void) queueRemoteRevision: (TDRevision*)rev {
    NSMutableArray** pQueue = (rev.deleted) ? &_deletedRevsToPull : &_revsToPull;
    if (!*pQueue)
        *pQueue = [[NSMutableArray alloc] initWithCapacity: 100];
    [*pQueue addObject: rev];
}


// Start up some HTTP GETs, within our limit on the maximum simultaneous number
- (void) pullRemoteRevisions {
    while (_httpConnectionCount < kMaxOpenHTTPConnections) {
        NSUInteger nBulk = MIN(_bulkRevsToPull.count, kMaxRevsToGetInBulk);
        if (nBulk == 1) {
            // Rather than pulling a single revision in 'bulk', just pull it normally:
            [self queueRemoteRevision: _bulkRevsToPull[0]];
            [_bulkRevsToPull removeObjectAtIndex: 0];
            nBulk = 0;
        }
        if (nBulk > 0) {
            // Prefer to pull bulk revisions:
            NSRange r = NSMakeRange(0, nBulk);
            [self pullBulkRevisions: [_bulkRevsToPull subarrayWithRange: r]];
            [_bulkRevsToPull removeObjectsInRange: r];
        } else {
            // Prefer to pull an existing revision over a deleted one:
            NSMutableArray* queue = _revsToPull;
            if (queue.count == 0) {
                queue = _deletedRevsToPull;
                if (queue.count == 0)
                    break;  // both queues are empty
            }
            [self pullRemoteRevision: queue[0]];
            [queue removeObjectAtIndex: 0];
        }
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
    // See: http://wiki.apache.org/couchdb/HTTP_Document_API#GET
    // See: http://wiki.apache.org/couchdb/HTTP_Document_API#Getting_Attachments_With_a_Document
    NSString* path = $sprintf(@"/%@?rev=%@&revs=true&attachments=true",
                              TDEscapeID(rev.docID), TDEscapeID(rev.revID));
    NSArray* knownRevs = [_db getPossibleAncestorRevisionIDs: rev limit: kMaxNumberOfAttsSince];
    if (knownRevs.count > 0)
        path = [path stringByAppendingFormat: @"&atts_since=%@", joinQuotedEscaped(knownRevs)];
    
    LogTo(SyncVerbose, @"%@: GET .%@", self, path);
    NSString* urlStr = [_remote.absoluteString stringByAppendingString: path];
    __block TDMultipartDownloader* dl = [[[TDMultipartDownloader alloc]
                                    initWithURL: [NSURL URLWithString: urlStr]
                                       database: _db
                                 requestHeaders: self.requestHeaders
                                   onCompletion:
        ^(TDMultipartDownloader* download, NSError *error) {
            // OK, now we've got the response revision:
            if (error) {
                self.error = error;
                self.changesProcessed++;
            } else {
                TDRevision* gotRev = [TDRevision revisionWithProperties: download.document];
                gotRev.sequence = rev.sequence;
                // Add to batcher ... eventually it will be fed to -insertRevisions:.
                [_downloadsToInsert queueObject: gotRev];
                [self asyncTaskStarted];
            }
            
            // Note that we've finished this task:
            [self removeRemoteRequest: dl];
            [self asyncTasksFinished: 1];
            --_httpConnectionCount;
            // Start another task if there are still revisions waiting to be pulled:
            [self pullRemoteRevisions];
        }
     ] autorelease];
    [self addRemoteRequest: dl];
    dl.authorizer = _authorizer;
    [dl start];
}


// Get a bunch of revisions in one bulk request.
- (void) pullBulkRevisions: (NSArray*)bulkRevs {
    // http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API
    NSUInteger nRevs = bulkRevs.count;
    if (nRevs == 0)
        return;
    LogTo(Sync, @"%@ bulk-fetching %u remote revisions...", self, (unsigned)nRevs);
    LogTo(SyncVerbose, @"%@ bulk-fetching remote revisions: %@", self, bulkRevs);
    
    [self asyncTaskStarted];
    ++_httpConnectionCount;
    NSMutableArray* remainingRevs = [[bulkRevs mutableCopy] autorelease];
    NSArray* keys = [bulkRevs my_map: ^(TDRevision* rev) { return rev.docID; }];
    [self sendAsyncRequest: @"POST"
                      path: @"/_all_docs?include_docs=true"
                      body: $dict({@"keys", keys})
              onCompletion:^(id result, NSError *error) {
                  if (error) {
                      self.error = error;
                      self.changesProcessed += bulkRevs.count;
                  } else {
                      // Process the resulting rows' documents.
                      // We only add a document if it doesn't have attachments, and if its
                      // revID matches the one we asked for.
                      NSArray* rows = $castIf(NSArray, result[@"rows"]);
                      LogTo(Sync, @"%@ checking %u bulk-fetched remote revisions",
                            self, (unsigned)rows.count);
                      for (NSDictionary* row in rows) {
                          NSDictionary* doc = $castIf(NSDictionary, row[@"doc"]);
                          if (doc && !doc[@"_attachments"]) {
                              TDRevision* rev = [TDRevision revisionWithProperties: doc];
                              NSUInteger pos = [remainingRevs indexOfObject: rev];
                              if (pos != NSNotFound) {
                                  rev.sequence = [remainingRevs[pos] sequence];
                                  [remainingRevs removeObjectAtIndex: pos];
                                  [_downloadsToInsert queueObject: rev];
                                  [self asyncTaskStarted];
                              }
                          }
                      }
                  }
                  
                  // Any leftover revisions that didn't get matched will be fetched individually:
                  if (remainingRevs.count) {
                      LogTo(Sync, @"%@ bulk-fetch didn't work for %u of %u revs; getting individually",
                            self, (unsigned)remainingRevs.count, (unsigned)nRevs);
                      for (TDRevision* rev in remainingRevs)
                          [self queueRemoteRevision: rev];
                      [self pullRemoteRevisions];
                  }

                  // Note that we've finished this task:
                  [self asyncTasksFinished: 1];
                  --_httpConnectionCount;
                  // Start another task if there are still revisions waiting to be pulled:
                  [self pullRemoteRevisions];
              }
     ];
}


// This will be called when _downloadsToInsert fills up:
- (void) insertDownloads:(NSArray *)downloads {
    LogTo(SyncVerbose, @"%@ inserting %u revisions...", self, (unsigned)downloads.count);
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
        
    [_db beginTransaction];
    BOOL success = NO;
    @try{
        downloads = [downloads sortedArrayUsingSelector: @selector(compareSequences:)];
        for (TDRevision* rev in downloads) {
            @autoreleasepool {
                SequenceNumber fakeSequence = rev.sequence;
                NSArray* history = [TDDatabase parseCouchDBRevisionHistory: rev.properties];
                if (!history && rev.generation > 1) {
                    Warn(@"%@: Missing revision history in response for %@", self, rev);
                    self.error = TDStatusToNSError(kTDStatusUpstreamError, nil);
                    continue;
                }
                LogTo(SyncVerbose, @"%@ inserting %@ %@",
                      self, rev.docID, [history my_compactDescription]);

                // Insert the revision:
                int status = [_db forceInsert: rev revisionHistory: history source: _remote];
                if (TDStatusIsError(status)) {
                    if (status == kTDStatusForbidden)
                        LogTo(Sync, @"%@: Remote rev failed validation: %@", self, rev);
                    else {
                        Warn(@"%@ failed to write %@: status=%d", self, rev, status);
                        self.error = TDStatusToNSError(status, nil);
                        continue;
                    }
                }
                
                // Mark this revision's fake sequence as processed:
                [_pendingSequences removeSequence: fakeSequence];
            }
        }
        
        LogTo(SyncVerbose, @"%@ finished inserting %u revisions",
              self, (unsigned)downloads.count);
        
        // Checkpoint:
        self.lastSequence = _pendingSequences.checkpointedValue;
        
        success = YES;
    } @catch (NSException *x) {
        MYReportException(x, @"%@: Exception inserting revisions", self);
    } @finally {
        [_db endTransaction: success];
    }
    
    time = CFAbsoluteTimeGetCurrent() - time;
    LogTo(Sync, @"%@ inserted %u revs in %.3f sec (%.1f/sec)",
          self, (unsigned)downloads.count, time, downloads.count/time);
    
    [self asyncTasksFinished: downloads.count];
    self.changesProcessed += downloads.count;
}


@end



#pragma mark -

@implementation TDPulledRevision

@synthesize remoteSequenceID=_remoteSequenceID, conflicted=_conflicted;

- (void) dealloc {
    [_remoteSequenceID release];
    [super dealloc];
}

@end



static NSString* joinQuotedEscaped(NSArray* strings) {
    if (strings.count == 0)
        return @"[]";
    NSString* json = [TDJSON stringWithJSONObject: strings options: 0 error: NULL];
    return TDEscapeURLParam(json);
}
