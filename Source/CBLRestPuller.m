//
//  CBLRestPuller.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLRestPuller.h"
#import "CBLRestPusher.h"
#import "CBLRestReplicator+Internal.h"
#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+Replication.h"
#import "CBL_Revision.h"
#import "CBL_Body.h"
#import "CBL_Attachment.h"
#import "CBLChangeTracker.h"
#import "CBLAuthorizer.h"
#import "CBLBatcher.h"
#import "CBLMultipartDownloader.h"
#import "CBLBulkDownloader.h"
#import "CBLAttachmentDownloader.h"
#import "CBLCookieStorage.h"
#import "CBLSequenceMap.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBLJSON.h"
#import "CBLProgressGroup.h"
#import "CBL_AttachmentTask.h"
#import "ExceptionUtils.h"
#import "MYURLUtils.h"


// Maximum number of revisions to fetch simultaneously. (CFNetwork will only send about 5
// simultaneous requests, but by keeping a larger number in its queue we ensure that it doesn't
// run out, even if the CBL thread doesn't always have time to run.)
#define kMaxOpenHTTPConnections 12

// Maximum number of revs to fetch in a single _all_docs request (CouchDB only, not SG)
#define kMaxRevsToGetInBulkWithAllDocs 50u

// Maximum number of revs we want to be handling at once -- that's all revs that we've heard about
// from the change tracker but haven't yet inserted into the database. Once we hit this limit we
// pause the change tracker. The pause doesn't take effect immediately since the change tracker is
// reading asynchronously, so we'll get some more revs dumped on us, but we won't get a whole lot
// above this limit.
#define kMaxPendingDocs 200u

// Delay time of the CBLBatcher that stores revisions to be inserted into the database.
#define kInsertionBatcherDelay 0.25


@interface CBLRestPuller () <CBLChangeTrackerClient>
@end


@implementation CBLRestPuller


- (void)dealloc {
    [_changeTracker stop];
}


- (void) beginReplicating {
    if (!_downloadsToInsert) {
        // Note: This is a ref cycle, because the block has a (retained) reference to 'self',
        // and _downloadsToInsert retains the block, and of course I retain _downloadsToInsert.
        _downloadsToInsert = [[CBLBatcher alloc] initWithCapacity: 200 delay: kInsertionBatcherDelay
                                                  processor: ^(NSArray *downloads) {
                                                      [self insertDownloads: downloads];
                                                  }];
    }
    if (!_pendingSequences) {
        _pendingSequences = [[CBLSequenceMap alloc] init];
        if (_lastSequence != nil) {
            // Prime _pendingSequences so its checkpointedValue will reflect the last known seq:
            SequenceNumber seq = [_pendingSequences addValue: _lastSequence];
            [_pendingSequences removeSequence: seq];
            AssertEqual(_pendingSequences.checkpointedValue, _lastSequence);
        }
    }
    
    _caughtUp = NO;
    [self asyncTaskStarted];   // task: waiting to catch up
    [self startChangeTracker];
    [self downloadWaitingAttachments];
}


- (void) startChangeTracker {
    Assert(!_changeTracker);
    NSTimeInterval pollInterval = _settings.pollInterval;
    CBLChangeTrackerMode mode = kOneShot;
    if (_settings.continuous && pollInterval == 0.0 && self.canUseWebSockets)
        mode = kWebSocket;
    LogVerbose(Sync, @"%@ starting ChangeTracker: mode=%d, since=%@", self, mode, _lastSequence);
    _changeTracker = [[CBLChangeTracker alloc] initWithDatabaseURL: _settings.remote
                                                              mode: mode
                                                         conflicts: YES
                                                      lastSequence: _lastSequence
                                                            client: self];
    _changeTracker.continuous = _settings.continuous;
    _changeTracker.activeOnly = (_lastSequence == nil && _db.documentCount == 0);
    _changeTracker.filterName = _settings.filterName;
    _changeTracker.filterParameters = _settings.filterParameters;
    _changeTracker.docIDs = _settings.docIDs;
    _changeTracker.authorizer = self.authorizer;
    _changeTracker.cookieStorage = self.cookieStorage;

    unsigned heartbeat = $castIf(NSNumber, _settings.options[kCBLReplicatorOption_Heartbeat]).unsignedIntValue;
    if (heartbeat >= 15000)
        _changeTracker.heartbeat = heartbeat / 1000.0;
    if (pollInterval > 0.0)
        _changeTracker.pollInterval = pollInterval;

    NSMutableDictionary* headers = $mdict({@"User-Agent", [CBL_ReplicatorSettings userAgentHeader]});
    [headers addEntriesFromDictionary: _settings.requestHeaders];
    _changeTracker.requestHeaders = headers;
    
    [_changeTracker start];
    if (!_changeTracker.continuous)
        [self asyncTaskStarted];
}


- (BOOL) canUseWebSockets {
    id option = _settings.options[kCBLReplicatorOption_UseWebSocket];
    if (option)
        return [option boolValue];
    return [self serverIsSyncGatewayVersion: @"0.91"]
        && _settings.remote.my_proxySettings == nil;    // WebSocket class doesn't support proxies yet
}


- (void) stop {
    if (self.status == kCBLReplicatorStopped)
        return;
    LogTo(Sync, @"%@ STOPPING...", self);
    if (_changeTracker) {
        BOOL continous = _changeTracker.continuous;
        _changeTracker.client = nil;  // stop it from calling my -changeTrackerStopped
        [_changeTracker stop];
        _changeTracker = nil;
        if (!continous)
            [self asyncTasksFinished: 1]; // balances -asyncTaskStarted in -startChangeTracker
        if (!_caughtUp)
            [self asyncTasksFinished: 1]; // balances -asyncTaskStarted in -beginReplicating
    }
    _revsToPull = nil;
    _deletedRevsToPull = nil;
    _bulkRevsToPull = nil;

    [_downloadsToInsert flushAll];

    [super stop];
}


- (void) retry {
    // This is called if I've gone idle but some revisions failed to be pulled.
    // I should start the _changes feed over again, so I can retry all the revisions.
    [_changeTracker stop];
    [super retry];
}


- (void) stopped {
    _downloadsToInsert = nil;
    [super stopped];
}


- (BOOL) goOnline {
    if ([super goOnline])
        return YES;
    // If we were already online (i.e. server is reachable) but got a reachability-change event,
    // tell the tracker to retry in case it's in retry mode after a transient failure. (I.e. the
    // state of the network might be better now.)
    if (_running && _online) {
        [_changeTracker retry];
        [self downloadWaitingAttachments];
    }
    return NO;
}


- (BOOL) goOffline {
    if (![super goOffline])
        return NO;
    [_changeTracker stop];
    return YES;
}


- (void) pauseOrResume {
    NSUInteger pending = _batcher.count + _pendingSequences.count;
    _changeTracker.paused = (pending >= kMaxPendingDocs);
}


- (BOOL) changeTrackerApproveSSLTrust: (SecTrustRef)serverTrust
                              forHost: (NSString*)host
                                 port: (UInt16)port
{
    return [self checkSSLServerTrust: serverTrust forHost: host port: port];
}


- (void) changeTrackerReceivedHTTPHeaders:(NSDictionary *)headers {
    if (!_serverType) {
        _serverType = headers[@"Server"];
        LogTo(Sync, @"%@: Server is %@", self, _serverType);
    }
}


- (void) changeTrackerReceivedSequence: (id)remoteSequenceID
                                 docID: (NSString*)docID
                                revIDs: (NSArray*)revIDs
                               deleted: (BOOL)deleted
{
    // Process each change from the feed:
    if (![CBLDatabase isValidDocumentID: docID])
        return;
    
    self.changesTotal += revIDs.count;
    for (NSString* revID in revIDs) {
        // Push each revision info to the inbox
        CBLPulledRevision* rev = [[CBLPulledRevision alloc] initWithDocID: docID
                                                                  revID: revID
                                                                deleted: deleted];
        // Remember its remote sequence ID (opaque), and make up a numeric sequence
        // based on the order in which it appeared in the _changes feed:
        rev.remoteSequenceID = remoteSequenceID;
        if (revIDs.count > 1)
            rev.conflicted = true;
        LogVerbose(Sync, @"%@: Received #%@ %@", self, remoteSequenceID, rev);
        [self addToInbox: rev];
    }

    [self pauseOrResume];
}


- (void) changeTrackerCaughtUp {
    if (!_caughtUp) {
        LogTo(Sync, @"%@: Caught up with changes!", self);
        _caughtUp = YES;
        [self asyncTasksFinished: 1];  // balances -asyncTaskStarted in -beginReplicating
    }
}


- (void) changeTrackerFinished {
    [self changeTrackerCaughtUp];
}


// The change tracker reached EOF or an error.
- (void) changeTrackerStopped:(CBLChangeTracker *)tracker {
    if (tracker != _changeTracker)
        return;
    NSError* error = tracker.error;
    LogTo(Sync, @"%@: ChangeTracker stopped; error=%@", self, error.my_compactDescription);
    
    BOOL continous = _changeTracker.continuous;
    _changeTracker = nil;
    
    if (error) {
        if (CBLIsOfflineError(error))
            [self goOffline];
        else if (!self.error)
            self.error = error;
    }
    
    [_batcher flushAll];
    if (!continous)
        [self asyncTasksFinished: 1]; // balances -asyncTaskStarted in -startChangeTracker
    if (!_caughtUp)
        [self asyncTasksFinished: 1]; // balances -asyncTaskStarted in -beginReplicating
}


#pragma mark - REVISION CHECKING:


// Process a bunch of remote revisions from the _changes feed at once
- (void) processInbox: (CBL_RevisionList*)inbox {
    if (!_canBulkGet)
        _canBulkGet = [self serverIsSyncGatewayVersion: @"0.81"];

    // Ask the local database which of the revs are not known to it:
    LogTo(SyncPerf, @"%@: Processing %u changes", self, (unsigned)inbox.count);
    LogVerbose(Sync, @"%@: Looking up %@", self, inbox);
    id lastInboxSequence = [inbox.allRevisions.lastObject remoteSequenceID];
    NSUInteger originalCount = inbox.count;
    CBLStatus status;
    if (![_db.storage findMissingRevisions: inbox status: &status]) {
        Warn(@"%@ failed to look up local revs; status=%d", self, status);
        inbox = nil;
    }
    NSUInteger missingCount = inbox.count;
    if (missingCount < originalCount) {
        // Some of the revisions originally in the inbox aren't missing; treat those as processed:
        self.changesProcessed += originalCount - missingCount;
    }
    
    if (missingCount == 0) {
        // Nothing to do; just count all the revisions as processed.
        // Instead of adding and immediately removing the revs to _pendingSequences,
        // just do the latest one (equivalent but faster):
        LogVerbose(Sync, @"%@: no new remote revisions to fetch", self);
        SequenceNumber seq = [_pendingSequences addValue: lastInboxSequence];
        [_pendingSequences removeSequence: seq];
        self.lastSequence = _pendingSequences.checkpointedValue;
        [self pauseOrResume];
        return;
    }
    
    LogTo(SyncPerf, @"%@: Queuing download requests for %u revisions", self, (unsigned)inbox.count);
    LogVerbose(Sync, @"%@ queuing remote revisions %@", self, inbox.allRevisions);
    
    // Dump the revs into the queues of revs to pull from the remote db:
    unsigned numBulked = 0;
    for (CBLPulledRevision* rev in inbox.allRevisions) {
        if (_canBulkGet || (rev.generation == 1 && !rev.deleted && !rev.conflicted)) {
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
          self, (unsigned)inbox.count, ((CBLPulledRevision*)inbox[0]).remoteSequenceID,
          numBulked, (unsigned)(inbox.count-numBulked));
    
    [self pullRemoteRevisions];
    [self pauseOrResume];
}


// Add a revision to the appropriate queue of revs to individually GET
- (void) queueRemoteRevision: (CBL_Revision*)rev {
    if (rev.deleted)
    {
        if (!_deletedRevsToPull)
            _deletedRevsToPull = [[NSMutableArray alloc] initWithCapacity:100];
        
        [_deletedRevsToPull addObject:rev];
    }
    else
    {
        if (!_revsToPull)
            _revsToPull = [[NSMutableArray alloc] initWithCapacity:100];
        
        [_revsToPull addObject:rev];
    }
}


// Start up some HTTP GETs, within our limit on the maximum simultaneous number
- (void) pullRemoteRevisions {
    while (_db && _httpConnectionCount < kMaxOpenHTTPConnections) {
        NSUInteger nBulk = _bulkRevsToPull.count;
        if (!_canBulkGet)
            nBulk = MIN(nBulk, kMaxRevsToGetInBulkWithAllDocs);
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
- (void) pullRemoteRevision: (CBL_Revision*)rev
{
    [self asyncTaskStarted];
    ++_httpConnectionCount;
    
    // Construct a query. We want the revision history, and the bodies of attachments.
    // See: http://wiki.apache.org/couchdb/HTTP_Document_API#GET
    // See: http://wiki.apache.org/couchdb/HTTP_Document_API#Getting_Attachments_With_a_Document
    NSString* path = $sprintf(@"%@?rev=%@&revs=true",
                              CBLEscapeURLParam(rev.docID), CBLEscapeURLParam(rev.revID));
    CBLDatabase* db = _db;
    if (_settings.downloadAttachments) {
        // If the document has attachments, add an 'atts_since' param with a list of
        // already-known revisions, so the server can skip sending the bodies of any
        // attachments we already have locally:
        NSArray* knownRevs = [db.storage getPossibleAncestorRevisionIDs: rev
                                                                  limit: kMaxNumberOfAttsSince
                                                        onlyAttachments: YES];
        if (knownRevs.count > 0)
            path = [path stringByAppendingFormat: @"&attachments=true&atts_since=%@",
                                joinQuotedEscaped(knownRevs)];
        else
            path = [path stringByAppendingString: @"&attachments=true"];
    }
    LogTo(SyncPerf, @"%@: Getting %@", self, rev);
    LogVerbose(Sync, @"%@: GET %@", self, path);
    
    __weak CBLRestPuller *weakSelf = self;
    __block CBLMultipartDownloader *dl;
    dl = [[CBLMultipartDownloader alloc] initWithURL: CBLAppendToURL(_settings.remote, path)
                                            database: db
                                        onCompletion:
        ^(CBLMultipartDownloader* result, NSError *error) {
            __strong CBLRestPuller *strongSelf = weakSelf;
            if (!strongSelf) return; // already dealloced
            // OK, now we've got the response:
            LogTo(SyncPerf, @"%@: Got %@", strongSelf, rev);
            if (error) {
                if (isDocumentError(error)) {
                    // Revision is missing or not accessible:
                    [strongSelf revision: rev failedWithError: error];
                } else {
                    // Request failed:
                    strongSelf.error = error;
                    [strongSelf revisionFailed];
                }
            } else {
                // Add to batcher ... eventually it will be fed to -insertRevisions:.
                CBL_Revision* gotRev = [CBL_Revision revisionWithProperties: result.document];
                gotRev.sequence = rev.sequence;
                [strongSelf queueDownloadedRevision:gotRev];
            }
            
            // Note that we've finished this task:
            [strongSelf asyncTasksFinished:1];
            --strongSelf->_httpConnectionCount;
            // Start another task if there are still revisions waiting to be pulled:
            [strongSelf pullRemoteRevisions];
        }
     ];
    [self startRemoteRequest: dl];
}


// Get a bunch of revisions in one bulk request. Will use _bulk_get if possible.
- (void) pullBulkRevisions: (NSArray*)bulkRevs {
    NSUInteger nRevs = bulkRevs.count;
    if (nRevs == 0)
        return;
    LogTo(Sync, @"%@ bulk-fetching %u remote revisions...", self, (unsigned)nRevs);
    LogVerbose(Sync, @"%@ bulk-fetching remote revisions: %@", self, bulkRevs);

    if (!_canBulkGet) {
        // _bulk_get is not supported, so fall back to _all_docs:
        [self pullBulkWithAllDocs: bulkRevs];
        return;
    }

    LogTo(SyncPerf, @"%@: bulk-getting %u remote revisions...", self, (unsigned)nRevs);
    LogVerbose(Sync, @"%@: POST _bulk_get", self);
    NSMutableArray* remainingRevs = [bulkRevs mutableCopy];
    [self asyncTaskStarted];
    ++_httpConnectionCount;
    __weak CBLRestPuller *weakSelf = self;
    __block CBLBulkDownloader *dl;
    __block BOOL first = YES;
    __unused CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    dl = [[CBLBulkDownloader alloc] initWithDbURL: _settings.remote
                                         database: _db
                                        revisions: bulkRevs
                                      attachments: _settings.downloadAttachments
                                       onDocument:
          ^(NSDictionary* props) {
              // Got a revision!
              __strong CBLRestPuller *strongSelf = weakSelf;
              if (!strongSelf) return; // already dealloced
              if (first) {
                  first = NO;
                  LogTo(SyncPerf, @"%@: Received first revision from bulk-get (%.3f sec)",
                        self, CFAbsoluteTimeGetCurrent()-start);
              }
              // Find the matching revision in 'remainingRevs' and get its sequence:
              CBL_Revision* rev;
              if (props.cbl_id)
                  rev = [CBL_Revision revisionWithProperties: props];
              else
                  rev = [[CBL_Revision alloc] initWithDocID: props[@"id"]
                                                      revID: props[@"rev"] deleted: NO];
              NSUInteger pos = [remainingRevs indexOfObject: rev];
              if (pos == NSNotFound) {
                  Warn(@"%@: Received unexpected rev %@; ignoring", self, rev);
                  return;
              }
              rev.sequence = [remainingRevs[pos] sequence];
              [remainingRevs removeObjectAtIndex: pos];

              if (props.cbl_id) {
                  // Add to batcher ... eventually it will be fed to -insertRevisions:.
                  [strongSelf queueDownloadedRevision:rev];
              } else {
                  CBLStatus status = CBLStatusFromBulkDocsResponseItem(props);
                  [strongSelf revision: rev failedWithError: CBLStatusToNSError(status)];
              }
          }
                                   onCompletion:
          ^(CBLBulkDownloader* result, NSError *error) {
              // The entire _bulk_get is finished:
              __strong CBLRestPuller *strongSelf = weakSelf;
              if (!strongSelf) return; // already dealloced
              LogTo(SyncPerf, @"%@: finished bulk-getting %u remote revisions (%.3f sec)",
                    self, (unsigned)nRevs, CFAbsoluteTimeGetCurrent()-start);

              if (error) {
                  strongSelf.error = error;
                  [strongSelf revisionFailed];
              } else if (remainingRevs.count > 0) {
                  Warn(@"%@: %u revs not returned from _bulk_get: %@",
                       self, (unsigned)remainingRevs.count, remainingRevs);
              }
              strongSelf.changesProcessed += remainingRevs.count;
              
              // Note that we've finished this task:
              [strongSelf asyncTasksFinished:1];
              
              --strongSelf->_httpConnectionCount;
              // Start another task if there are still revisions waiting to be pulled:
              [strongSelf pullRemoteRevisions];
          }
     ];

    if (self.canSendCompressedRequests)
        [dl compressBody];

    [self startRemoteRequest: dl];
}


// Get as many revisions as possible in one _all_docs request.
// This is compatible with CouchDB, but it only works for revs of generation 1 without attachments.
- (void) pullBulkWithAllDocs: (NSArray*)bulkRevs {
    // http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API
    LogTo(SyncPerf, @"%@: Using _all_docs to get %u remote revisions...",
          self, (unsigned)bulkRevs.count);
    [self asyncTaskStarted];
    ++_httpConnectionCount;
    CBL_RevisionList* remainingRevs = [[CBL_RevisionList alloc] initWithArray: bulkRevs];
    [self sendAsyncRequest: @"POST"
                      path: @"_all_docs?include_docs=true"
                      body: $dict({@"keys", remainingRevs.allDocIDs})
              onCompletion:^(id result, NSError *error) {
                  if (error) {
                      self.error = error;
                      [self revisionFailed];
                      self.changesProcessed += bulkRevs.count;
                  } else {
                      // Process the resulting rows' documents.
                      // We only add a document if it doesn't have attachments, and if its
                      // revID matches the one we asked for.
                      NSArray* rows = $castIf(NSArray, result[@"rows"]);
                      LogTo(SyncPerf, @"%@: Got %u remote revisions with _all_docs",
                            self, (unsigned)rows.count);
                      LogTo(Sync, @"%@ checking %u bulk-fetched remote revisions",
                            self, (unsigned)rows.count);
                      for (NSDictionary* row in rows) {
                          NSDictionary* doc = $castIf(NSDictionary, row[@"doc"]);
                          if (doc && !doc.cbl_attachments) {
                              CBL_Revision* rev = [CBL_Revision revisionWithProperties: doc];
                              CBL_Revision* removedRev = [remainingRevs removeAndReturnRev: rev];
                              if (removedRev) {
                                  rev.sequence = removedRev.sequence;
                                  [self queueDownloadedRevision: rev];
                              }
                          } else {
                              CBLStatus status = CBLStatusFromBulkDocsResponseItem(row);
                              if (CBLStatusIsError(status) && row[@"key"]) {
                                  CBL_Revision* rev = [remainingRevs revWithDocID: row[@"key"]];
                                  if (rev) {
                                      [remainingRevs removeRev: rev];
                                      [self revision: rev
                                            failedWithError: CBLStatusToNSError(status)];
                                  }
                              }
                          }
                      }
                      
                      // Any leftover revisions that didn't get matched will be fetched individually:
                      if (remainingRevs.count) {
                          LogTo(Sync, @"%@ bulk-fetch didn't work for %u of %u revs; getting individually",
                                self, (unsigned)remainingRevs.count, (unsigned)bulkRevs.count);
                          for (CBL_Revision* rev in remainingRevs)
                              [self queueRemoteRevision: rev];
                          [self pullRemoteRevisions];
                      }
                  }
                  
                  // Note that we've finished this task:
                  [self asyncTasksFinished: 1];
                  --_httpConnectionCount;
                  // Start another task if there are still revisions waiting to be pulled:
                  [self pullRemoteRevisions];
              }
     ];
}

- (void) revision: (CBL_Revision*)rev failedWithError: (NSError*)error {
    if (CBLMayBeTransientError(error))
        [self revisionFailed]; // retry later
    else {
        LogVerbose(Sync, @"Giving up on %@: %@", rev, error.my_compactDescription);
        [_pendingSequences removeSequence: rev.sequence];
        [self pauseOrResume];
    }
    self.changesProcessed++;
}

// This invokes the tranformation block if one is installed and queues the resulting CBL_Revision
- (void) queueDownloadedRevision: (CBL_Revision*)rev {
    if (_settings.revisionBodyTransformationBlock) {
        // Add 'file' properties to attachments pointing to their bodies:
        [rev[@"_attachments"] enumerateKeysAndObjectsUsingBlock:^(NSString* name,
                                                                  NSMutableDictionary* attachment,
                                                                  BOOL *stop) {
            [attachment removeObjectForKey: @"file"];
            if (attachment[@"follows"] && !attachment[@"data"]) {
                NSString* filePath = [_db pathForPendingAttachmentWithDict: attachment];
                if (filePath)
                    attachment[@"file"] = filePath;
            }
        }];

        CBL_Revision* xformed = [_settings transformRevision: rev];
        if (xformed == nil) {
            LogTo(Sync, @"%@: Transformer rejected revision %@", self, rev);
            [_pendingSequences removeSequence: rev.sequence];
            self.lastSequence = _pendingSequences.checkpointedValue;
            [self pauseOrResume];
            return;
        }
        rev = xformed;

        // Clean up afterwards
        [rev[@"_attachments"] enumerateKeysAndObjectsUsingBlock:^(NSString* name,
                                                                  NSMutableDictionary* attachment,
                                                                  BOOL *stop) {
            [attachment removeObjectForKey: @"file"];
        }];
    }
    [self asyncTaskStarted];
    [_downloadsToInsert queueObject: rev];
}

// This will be called when _downloadsToInsert fills up:
- (void) insertDownloads:(NSArray *)downloads {
    LogTo(SyncPerf, @"%@: inserting %u revisions into db...", self, (unsigned)downloads.count);
    LogVerbose(Sync, @"%@ inserting %u revisions...", self, (unsigned)downloads.count);
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
        
    downloads = [downloads sortedArrayUsingSelector: @selector(compareSequences:)];
    [_db.storage inTransaction: ^CBLStatus {
        for (CBL_Revision* rev in downloads) {
            @autoreleasepool {
                SequenceNumber fakeSequence = rev.sequence;
                [rev forgetSequence];
                NSArray* history = [CBLDatabase parseCouchDBRevisionHistory: rev.properties];
                if (!history && rev.generation > 1) {
                    Warn(@"%@: Missing revision history in response for %@", self, rev);
                    self.error = CBLStatusToNSErrorWithInfo(kCBLStatusUpstreamError,
                                                            @"Missing revision history in response",
                                                            _settings.remote, nil);
                    [self revisionFailed];
                    continue;
                }
                LogVerbose(Sync, @"%@ inserting %@ %@",
                           self, rev.docID, [history my_compactDescription]);

                // Insert the revision:
                NSError* error;
                int status = [_db forceInsert: rev revisionHistory: history
                                       source: _settings.remote
                                        error: &error];
                if (CBLStatusIsError(status)) {
                    if (status == kCBLStatusForbidden) {
                        // Considered a success, since the doc was delivered to the app.
                        LogTo(Sync, @"%@: Remote rev failed validation: %@ (reason: %@)",
                              self, rev, error.localizedFailureReason);
                    } else if (status == kCBLStatusBadAttachment) {
                        // Revision with broken _attachments metadata (i.e. bogus revpos)
                        // should not stop replication. Warn and skip it. (#1001)
                        Warn(@"%@: Revision %@ has invalid attachment metadata: %@",
                             self, rev, rev[@"_attachments"]);
                    } else if (status == kCBLStatusDBBusy) {
                        return status;  // abort transaction; _inTransaction will retry
                    } else {
                        Warn(@"%@ failed to write %@: status=%d", self, rev, status);
                        [self revisionFailed];
                        self.error = CBLStatusToNSError(status);
                        continue; // don't mark as processed
                    }
                }
                
                // Mark this revision's fake sequence as processed:
                [_pendingSequences removeSequence: fakeSequence];
            }
        }
        
        LogVerbose(Sync, @"%@ finished inserting %u revisions",
              self, (unsigned)downloads.count);
        return kCBLStatusOK;
    }];

    // Checkpoint:
    self.lastSequence = _pendingSequences.checkpointedValue;

    time = CFAbsoluteTimeGetCurrent() - time;
    LogTo(SyncPerf, @"%@: inserted %u revs in %.3f sec (%.1f/sec)",
          self, (unsigned)downloads.count, time, downloads.count/time);
    LogTo(Sync, @"%@ inserted %u revs in %.3f sec (%.1f/sec)",
          self, (unsigned)downloads.count, time, downloads.count/time);
    
    [self asyncTasksFinished: downloads.count];
    self.changesProcessed += downloads.count;
    [self pauseOrResume];
}


#pragma mark - DOWNLOADING ATTACHMENTS:


// Start downloading if online, else add to _waitingAttachments
- (void) downloadAttachment: (CBL_AttachmentTask*)task {
    __block CBLAttachmentDownloader* dl = _attachmentDownloads[task.ID];
    if (dl) {
        // Already being downloaded, so just transfer task's progress object(s) to existing dl:
        [dl addTask: task];
    } else if (!_running || !_online) {
        // Replicator isn't online, so remember it for later:
        [self addToWaitingAttachments: task];
    } else {
        // Not being downloaded, so create a downloader:
        __weak CBLRestPuller *weakSelf = self;
        dl = [[CBLAttachmentDownloader alloc] initWithDbURL: _settings.remote
                                                   database: _db
                                                 attachment: task
                                               onCompletion:
              ^(id result, NSError *error) {
                  // On completion or error:
                  __strong CBLRestPuller *strongSelf = weakSelf;
                  if (!strongSelf) return; // already dealloced
                  [strongSelf->_attachmentDownloads removeObjectForKey: task.ID];
                  if (error) {
                      if (strongSelf->_running && !strongSelf->_online) {
                          // I've gone offline, so save the tasks for later:
                          [task.progress setIndeterminate];
                          [self addToWaitingAttachments: task];
                      } else {
                          // Otherwise give up:
                          [task.progress failedWithError: error];
                      }
                  }
                  [strongSelf asyncTasksFinished: 1];
              }];
        if (!dl)
            return; // already been downloaded

        // Remember the downloader, then start it:
        if (!_attachmentDownloads)
            _attachmentDownloads = [NSMutableDictionary new];
        _attachmentDownloads[task.ID] = dl;

        [self asyncTaskStarted];
        [self startRemoteRequest: dl];
    }
}

- (void) addToWaitingAttachments: (CBL_AttachmentTask*)task {
    if (!_waitingAttachments)
        _waitingAttachments = [NSMutableArray new];
    [_waitingAttachments addObject: task];
}

// Start all attachment requests in _waitingAttachments
- (void) downloadWaitingAttachments {
    if (_running && _online) {
        NSArray* waiting = _waitingAttachments;
        _waitingAttachments = nil;
        for (CBL_AttachmentTask* attachment in waiting)
            [self downloadAttachment: attachment];
    }
}


#pragma mark - UTILITY FUNCTIONS:


static NSString* joinQuotedEscaped(NSArray* strings) {
    if (strings.count == 0)
        return @"[]";
    NSString* json = [CBLJSON stringWithJSONObject: strings options: 0 error: NULL];
    return CBLEscapeURLParam(json);
}


// Returns YES if an error refers to an inaccessible document, not the request itself,
// and shouldn't cause the replication to stop.
static BOOL isDocumentError(NSError* error) {
    if (![error.domain isEqualToString: CBLHTTPErrorDomain])
        return NO;
    NSInteger code = error.code;
    return code == kCBLStatusNotFound || code == kCBLStatusForbidden || code == kCBLStatusGone;
}


@end



#pragma mark -

@implementation CBLPulledRevision

@synthesize remoteSequenceID=_remoteSequenceID, conflicted=_conflicted;

@end

