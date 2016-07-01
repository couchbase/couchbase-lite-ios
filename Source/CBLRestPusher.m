//
//  CBLRestPusher.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/5/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLRestPusher.h"
#import "CBLRestReplicator+Internal.h"
#import "CBLDatabase.h"
#import "CBLDatabase+Replication.h"
#import "CBLDatabase+Insertion.h"
#import "CBL_Storage.h"
#import "CBL_Revision.h"
#import "CBLDatabaseChange.h"
#import "CBL_Attachment.h"
#import "CBLBatcher.h"
#import "CBLRemoteSession.h"
#import "CBLMultipartUploader.h"
#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBJSONEncoder.h"
#import "CBLRevision.h"
#import "CBLDocument.h"


#define kMaxBulkDocsObjectSize (5*1000*1000) // Max in-memory size of buffered bulk_docs dictionary
#define kEphemeralPurgeBatchSize    100     // # of revs to purge at once
#define kEphemeralPurgeDelay        1.0     // delay before purging revs


@interface CBLRestPusher ()
- (BOOL) uploadMultipartRevision: (CBL_Revision*)rev;
@end


@implementation CBLRestPusher


@synthesize createTarget=_createTarget;


- (BOOL) isPush {
    return YES;
}


// This is called before beginReplicating, if the target db might not exist
- (void) maybeCreateRemoteDB {
    if (!_settings.createTarget)
        return;
    LogTo(Sync, @"Remote db might not exist; creating it...");
    _creatingTarget = YES;
    [self asyncTaskStarted];
    [_remoteSession startRequest: @"PUT" path: @"" body: nil onCompletion: ^(id result, NSError* error) {
        _creatingTarget = NO;
        if (error && error.code != kCBLStatusDuplicate && error.code != kCBLStatusMethodNotAllowed) {
            LogTo(Sync, @"Failed to create remote db: %@", error.my_compactDescription);
            self.error = error;
            [self stop]; // this is fatal: no db to push to!
        } else {
            LogTo(Sync, @"Created remote db");
            _createTarget = NO;             // remember that I created the target
            [self beginReplicating];
        }
        [self asyncTasksFinished: 1];
    }];
}


- (CBL_RevisionList*) unpushedRevisions {
    NSError *error;
    CBL_RevisionList* revs = [_db unpushedRevisionsSince: _lastSequence
                                                  filter: _settings.filterBlock
                                                  params: _settings.filterParameters
                                                   error: &error];
    if (!revs)
        self.error = error;
    return revs;
}


- (void) beginReplicating {
    // If we're still waiting to create the remote db, do nothing now. (This method will be
    // re-invoked after that request finishes; see -maybeCreateRemoteDB above.)
    if (_creatingTarget)
        return;

    _pendingSequences = [NSMutableIndexSet indexSet];
    _maxPendingSequence = [self.lastSequence longLongValue];

    if ([_settings.options[kCBLReplicatorOption_PurgePushed] isEqual: @YES]) {
        _purgeQueue = [[CBLBatcher alloc] initWithCapacity: kEphemeralPurgeBatchSize
                                                     delay: kEphemeralPurgeDelay
                                                 processor: ^(NSArray *revs)
        {
            LogTo(Sync, @"Purging %lu docs ('purgePushed' option)", (unsigned long)revs.count);
            NSMutableDictionary* toPurge = [NSMutableDictionary dictionary];
            for( CBL_Revision* rev in revs)
                toPurge[rev.docID] = @[rev.revIDString];
            NSDictionary *result;
            [self.db.storage purgeRevisions: toPurge result: &result];
        }];
    }

    // Process existing changes since the last push:
    CBL_RevisionList* unpushedRevisions = self.unpushedRevisions;
    if (!unpushedRevisions)
        return;
    if (unpushedRevisions.count == 0 && !_settings.continuous) {
        // Nothing to push, so stop. Use a delayed-perform, because various things like tests
        // don't expect the replicator to stop during the call to -start, before any async
        // activity occurs.
        [self performSelector: @selector(stopped) withObject: nil afterDelay: 0.0];
        return;
    }
    for (CBL_Revision* rev in unpushedRevisions)
        [self addPending: rev];
    [self addRevsToInbox: unpushedRevisions];
    [_batcher flush];  // process up to the first 100 revs
    
    // Now listen for future changes (in continuous mode):
    if (_settings.continuous && !_observing) {
        _observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(dbChanged:)
                                                     name: CBL_DatabaseChangesNotification
                                                   object: _db];
    }

#ifdef GNUSTEP    // TODO: Multipart upload on GNUstep
    _dontSendMultipart = YES;
#endif
}


- (void) stopObserving {
    if (_observing) {
        _observing = NO;
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: CBL_DatabaseChangesNotification
                                                      object: _db];
    }
}


- (BOOL) goOffline {
    if (![super goOffline])
        return NO;
    [self stopObserving];
    return YES;
}


- (void) stop {
    LogTo(Sync, @"%@ STOPPING...", self);
    [_purgeQueue flushAll];
    [self stopObserving];
    [super stop];
}


// Adds a local revision to the "pending" set that are awaiting upload:
- (void) addPending: (CBL_Revision*)rev {
    SequenceNumber seq = [_db getRevisionSequence: rev];
    Assert(seq > 0);
    [_pendingSequences addIndex: (NSUInteger)seq];
    _maxPendingSequence = MAX(_maxPendingSequence, seq);
}

// Removes a revision from the "pending" set after it's been uploaded. Advances checkpoint.
- (void) removePending: (CBL_Revision*)rev {
    SequenceNumber seq = rev.sequence;
    bool wasFirst = (seq == (SequenceNumber)_pendingSequences.firstIndex);
    if (![_pendingSequences containsIndex: (NSUInteger)seq])
        Warn(@"%@ removePending: sequence %lld not in set, for rev %@", self, seq, rev);
    [_pendingSequences removeIndex: (NSUInteger)seq];

    if (wasFirst) {
        // If I removed the first pending sequence, can advance the checkpoint:
        SequenceNumber maxCompleted = _pendingSequences.firstIndex;
        if (maxCompleted == NSNotFound)
            maxCompleted = _maxPendingSequence;
        else
            --maxCompleted;
        self.lastSequence = $sprintf(@"%lld", maxCompleted);
    }

    if (_purgeQueue)
        [_purgeQueue queueObject: rev];
}

// I'm not going to do anything with this sequence, so increase the lastSequence up to it
- (void) skipSequence: (SequenceNumber)seq {
    if (seq < (SequenceNumber)_pendingSequences.firstIndex)
        if (seq > [self.lastSequence longLongValue])
            self.lastSequence = $sprintf(@"%lld", seq);
}


- (void) dbChanged: (NSNotification*)n {
    CBLDatabase* db = _db;
    CBLFilterBlock filter = _settings.filterBlock;
    NSArray* changes = (n.userInfo)[@"changes"];
    for (CBLDatabaseChange* change in changes) {
        CBL_Revision* rev = change.addedRevision;
        if (!rev)
            continue;  // ignore purges
        // Skip revisions that originally came from the database I'm syncing to,
        // or which don't match the filter:
        if (![change.source isEqual: _settings.remote] &&
                (!filter || [db runFilter: filter params: _settings.filterParameters
                               onRevision: rev]))
        {
            CBL_MutableRevision* nuRev = [rev mutableCopy];
            nuRev.body = nil; // save memory
            LogVerbose(Sync, @"%@: Queuing #%lld %@",
                  self, [db getRevisionSequence: nuRev], nuRev);
            [self addPending: nuRev];
            [self addToInbox: nuRev];
        } else {
            [self skipSequence: rev.sequence];
        }
    }
}


- (void) processInbox: (CBL_RevisionList*)changes {
    if ([_settings.options[kCBLReplicatorOption_AllNew] isEqual: @YES]) {
        // If 'allNew' option is set, upload new revs without checking first:
        [self uploadChanges: changes fromDiffs: nil];
        return;
    }

    // Generate a set of doc/rev IDs in the JSON format that _revs_diff wants:
    // <http://wiki.apache.org/couchdb/HttpPostRevsDiff>
    NSMutableDictionary<NSString*, NSMutableArray<NSString*>*>* diffs = $mdict();
    for (CBL_Revision* rev in changes) {
        NSString* docID = rev.docID;
        NSMutableArray<NSString*>* revs = diffs[docID];
        if (!revs) {
            revs = $marray();
            diffs[docID] = revs;
        }
        [revs addObject: rev.revIDString];
    }
    
    // Call _revs_diff on the target db:
    [self asyncTaskStarted];
    [_remoteSession startRequest: @"POST" path: @"_revs_diff" body: diffs
              onCompletion:^(NSDictionary* results, NSError* error) {
        if (error) {
            self.error = error;
            [self revisionFailed];
        } else if (results.count > 0) {
            [self uploadChanges: changes fromDiffs: results];
        } else {
            // None of the revisions are new to the remote
            for (CBL_Revision* rev in changes.allRevisions)
                [self removePending: rev];
        }
        [self asyncTasksFinished: 1];
    }];
}


// Process _revs_diff output (diffs) and trigger uploads for the appropriate revs (from changes).
// If diffs is nil, send everything.
- (void) uploadChanges: (CBL_RevisionList*)changes
             fromDiffs: (NSDictionary*)diffs

{
    // Go through the list of local changes again, selecting the ones the destination server
    // said were missing and mapping them to a JSON dictionary in the form _bulk_docs wants:
    CBLDatabase* db = _db;
    NSMutableArray* docsToSend = $marray();
    CBL_RevisionList* revsToSend = [[CBL_RevisionList alloc] init];
    size_t bufferedSize = 0;
    for (CBL_Revision* rev in changes.allRevisions) {
        @autoreleasepool {
            // Is this revision in the server's 'missing' list?
            NSDictionary* revResults = nil;
            if (diffs) {
                revResults = diffs[rev.docID];
                NSArray<NSString*>* missing = revResults[@"missing"];
                if (![missing containsObject: rev.revIDString]) {
                    [self removePending: rev];
                    continue;
                }
            }

            // Get the revision's properties:
            NSDictionary* properties;
            {
                CBLStatus status;
                CBL_Revision* loadedRev = [db revisionByLoadingBody: rev
                                                             status: &status];
                if (loadedRev && !loadedRev.properties) {
                    loadedRev = nil;
                    status = kCBLStatusBadJSON;
                }
                if (!loadedRev) {
                    if (status != kCBLStatusNotFound)
                        Warn(@"%@: Couldn't get local contents of %@ (status=%d)",
                             self, rev, status);
                    if (status < 500)
                        [self removePending: rev];
                    else
                        [self revisionFailed]; // db error, may be temporary
                    continue;
                }

                if ($castIf(NSNumber, loadedRev[@"_removed"]).boolValue) {
                    // Filter out _removed revision:
                    [self removePending: rev];
                    continue;
                }

                CBL_MutableRevision* populatedRev = [[_settings transformRevision: loadedRev] mutableCopy];

                // Add the revision history:
                NSArray<CBL_RevID*>* backTo = $castIf(NSArray, revResults[@"possible_ancestors"])
                                                    .cbl_asMaybeRevIDs;
                NSArray<CBL_RevID*>* history = [db getRevisionHistory: populatedRev
                                                         backToRevIDs: backTo];
                populatedRev[@"_revisions"] = [CBL_TreeRevID makeRevisionHistoryDict: history];
                properties = populatedRev.properties;

                // Strip any attachments already known to the target db:
                if (properties.cbl_attachments) {
                    // Look for the latest common ancestor and stub out older attachments:
                    int minRevPos = CBLFindCommonAncestor(populatedRev, backTo);
                    if (![db expandAttachmentsIn: populatedRev
                                       minRevPos: minRevPos + 1
                                    allowFollows: !_dontSendMultipart
                                          decode: NO
                                          status: &status]) {
                        LogTo(Sync, @"%@: Couldn't expand attachments of %@: status %d",
                              self, populatedRev, status);
                        [self revisionFailed];
                        continue;
                    }
                    properties = populatedRev.properties;
                    // If the rev has huge attachments, send it under separate cover:
                    if (!_dontSendMultipart && [self uploadMultipartRevision: populatedRev])
                        continue;
                }
            }
            Assert(properties.cbl_id);
            [revsToSend addRev: rev];
            [docsToSend addObject: properties];
            bufferedSize += [CBLJSON estimateMemorySize: properties];
            if (bufferedSize > kMaxBulkDocsObjectSize) {
                [self uploadBulkDocs: docsToSend changes: revsToSend];
                docsToSend = $marray();
                revsToSend = [[CBL_RevisionList alloc] init];
                bufferedSize = 0;
            }
        }
    }
    
    // Post the revisions to the destination:
    [self uploadBulkDocs: docsToSend changes: revsToSend];
}


// Post the revisions to the destination. "new_edits":false means that the server should
// use the given _rev IDs instead of making up new ones.
- (void) uploadBulkDocs: (NSArray*)docsToSend
                changes: (CBL_RevisionList*)changes
{
    // http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API
    NSUInteger numDocsToSend = docsToSend.count;
    if (numDocsToSend == 0)
        return;
    LogTo(Sync, @"%@: Sending %u revisions", self, (unsigned)numDocsToSend);
    LogVerbose(Sync, @"%@: Sending %@", self, changes.allRevisions);
    self.changesTotal += numDocsToSend;
    [self asyncTaskStarted];
    [_remoteSession startRequest: @"POST"
                      path: @"_bulk_docs"
                      body: $dict({@"docs", docsToSend},
                                  {@"new_edits", $false})
              onCompletion: ^(NSDictionary* response, NSError *error) {
                  if (error) {
                      self.error = error;
                  } else {
                      NSMutableSet* failedIDs = [NSMutableSet set];
                      // _bulk_docs response is really an array, not a dictionary!
                      for (NSDictionary* item in $castIf(NSArray, response)) {
                          CBLStatus status = CBLStatusFromBulkDocsResponseItem(item);
                          if (CBLStatusIsError(status)) {
                              // One of the docs failed to save.
                              Warn(@"%@: _bulk_docs got an error: %@", self, item);
                              // 403/Forbidden means validation failed; don't treat it as an error
                              // because I did my job in sending the revision. Other statuses are
                              // actual replication errors.
                              if (status != kCBLStatusForbidden && status != kCBLStatusUnauthorized) {
                                  [failedIDs addObject: item[@"id"]];
                                  if (CBLMayBeTransientError(CBLStatusToNSError(status)))
                                      [self revisionFailed];    // retry after replicator finishes
                                  // Don't set self.error ... we used to do this, but it stops the
                                  // replicator, so if the error were repeatable it prevented all
                                  // later documents from being pushed. (See #1279.)
                              }
                          }
                      }

                      // Remove from the pending list all the revs that didn't fail:
                      for (CBL_Revision* rev in changes.allRevisions) {
                          if (![failedIDs containsObject: rev.docID])
                              [self removePending: rev];
                      }
                      LogVerbose(Sync, @"%@: Sent %@", self, changes.allRevisions);
                  }
                  self.changesProcessed += numDocsToSend;
                  [self asyncTasksFinished: 1];
              }
     ];
}


CBLStatus CBLStatusFromBulkDocsResponseItem(NSDictionary* item) {
    NSString* errorStr = item[@"error"];
    if (!errorStr)
        return kCBLStatusOK;
    // 'status' property is nonstandard; Couchbase Lite returns it, others don't.
    CBLStatus status = $castIf(NSNumber, item[@"status"]).intValue;
    if (status >= 400)
        return status;
    // If no 'status' present, interpret magic hardcoded CouchDB error strings:
    if ($equal(errorStr, @"unauthorized"))
        return kCBLStatusUnauthorized;
    else if ($equal(errorStr, @"forbidden"))
        return kCBLStatusForbidden;
    else if ($equal(errorStr, @"conflict"))
        return kCBLStatusConflict;
    else if ($equal(errorStr, @"missing"))
        return kCBLStatusNotFound;
    else if ($equal(errorStr, @"not_found"))
        return kCBLStatusNotFound;
    else
        return kCBLStatusUpstreamError;
}

- (CBLMultipartWriter*)multipartWriterForRevision: (CBL_Revision*)rev
                                         boundary: (NSString*)boundary
                                            error: (NSError**)outError
{
    // Find all the attachments with "follows" instead of a body, and put 'em in a multipart stream.
    // It's important to scan the _attachments entries in the same order in which they will appear
    // in the JSON, because CouchDB expects the MIME bodies to appear in that same order (see #133).
    CBLMultipartWriter* bodyStream = nil;
    NSDictionary* attachments = rev.attachments;
    for (NSString* attachmentName in [CBJSONEncoder orderedKeys: attachments]) {
        NSDictionary* attachmentDict = attachments[attachmentName];
        if (attachmentDict[@"follows"]) {
            if (!bodyStream) {
                // Create the HTTP multipart stream:
                bodyStream = [[CBLMultipartWriter alloc] initWithContentType: @"multipart/related"
                                                                    boundary: boundary];
                [bodyStream setNextPartsHeaders: @{@"Content-Type": @"application/json"}];
                // Use canonical JSON encoder so that _attachments keys will be written in the
                // same order that this for loop is processing the attachments.
                NSError* error;
                NSData* json = [CBJSONEncoder canonicalEncoding: rev.properties error: &error];
                if (error) {
                    Warn(@"%@: Creating canonical JSON data got an error: %@", self, error.my_compactDescription);
                    if (outError)
                        *outError = error;
                    return nil;
                }

                if (self.canSendCompressedRequests)
                    [bodyStream addGZippedData: json];
                else
                    [bodyStream addData: json];
            }

            // Add attachment as another MIME part:
            CBLStatus status;
            CBL_Attachment* attachment = [_db attachmentForDict: attachmentDict
                                                          named: attachmentName
                                                         status: &status];
            if (attachment)
                status = [bodyStream addAttachment: attachment];
            if (CBLStatusIsError(status)) {
                if (status == kCBLStatusAttachmentNotFound)
                    LogTo(Sync, @"Skipping rev %@ due to missing attachment '%@'",
                          rev, attachmentName);
                else
                    Warn(@"CBLRestPusher: Invalid attachment '%@' in %@: %@",
                         attachmentName, rev, attachmentDict);
                CBLStatusToOutNSError(status, outError);
                return nil;
            }
        }
    }

    if (!bodyStream && outError)
        *outError = nil;
    return bodyStream;
}


/** Checks whether this revision has non-inlined attachments; if so, it schedules it to be
    uploaded separately, and returns YES. Otherwise returns NO, indicating that the caller is
    still responsible for uploading it. */
- (BOOL) uploadMultipartRevision: (CBL_Revision*)rev {
    // Pre-creating the body stream and check if it's available or not.
    NSError* error = nil;
    __block CBLMultipartWriter* bodyStream = [self multipartWriterForRevision: rev
                                                                     boundary: nil
                                                                        error: &error];
    if (!bodyStream) {
        if (error) {
            // On error creating the stream, note that we're skipping this revision, but still
            // return YES so that the caller won't try to upload it.
            [self revisionFailed];
            return YES;
        } else {
            return NO;
        }
    }
    NSString* boundary = bodyStream.boundary;
    
    // OK, we are going to upload this on its own:
    self.changesTotal++;
    [self asyncTaskStarted];

    NSString* path = $sprintf(@"%@?new_edits=false", CBLEscapeURLParam(rev.docID));
    __block CBLMultipartUploader* uploader = [[CBLMultipartUploader alloc]
                                  initWithURL: CBLAppendToURL(_settings.remote, path)
                              multipartWriter:^CBLMultipartWriter *{
                                  CBLMultipartWriter* writer = bodyStream;
                                  // Reset to nil so the writer will get regenerated if the block
                                  // gets re-called (e.g. when retrying). Make sure to use the same
                                  // multipart boundary string: it's already been encoded in the
                                  // Content-Type header so it has to match in the body!
                                  bodyStream = nil;
                                  if (!writer)
                                      writer = [self multipartWriterForRevision: rev
                                                                       boundary: boundary
                                                                          error: NULL];
                                  return writer;
                              }
                                 onCompletion: ^(CBLMultipartUploader* result, NSError *error) {
                  if (error) {
                      if ($equal(error.domain, CBLHTTPErrorDomain)
                                && error.code == kCBLStatusUnsupportedType) {
                          // Server doesn't like multipart, eh? Fall back to JSON.
                          _dontSendMultipart = YES;
                          [self uploadJSONRevision: rev];
                      } else {
                          self.error = error;
                          [self revisionFailed];
                      }
                  } else {
                      LogVerbose(Sync, @"%@: Sent multipart %@", self, rev);
                      [self removePending: rev];
                  }
                  self.changesProcessed++;
                  [self asyncTasksFinished: 1];

                  _uploading = NO;
                  [self startNextUpload];
              }
     ];
    LogVerbose(Sync, @"%@: Queuing %@ (multipart, %lldkb)", self, uploader, bodyStream.length/1024);
    if (!_uploaderQueue)
        _uploaderQueue = [[NSMutableArray alloc] init];
    [_uploaderQueue addObject: uploader];
    [self startNextUpload];
    return YES;
}


// Fallback to upload a revision if uploadMultipartRevision failed due to the server's rejecting
// multipart format.
- (void) uploadJSONRevision: (CBL_Revision*)originalRev {
    // Expand all attachments inline:
    CBL_MutableRevision* rev = originalRev.mutableCopy;
    CBLStatus status;
    if (![_db expandAttachmentsIn: rev minRevPos: 0 allowFollows: NO decode: NO
                           status: &status]) {
        self.error = CBLStatusToNSError(status);
        [self revisionFailed];
        return;
    }

    [self asyncTaskStarted];
    NSString* path = $sprintf(@"%@?new_edits=false", CBLEscapeURLParam(rev.docID));
    [_remoteSession startRequest: @"PUT"
                      path: path
                      body: rev.properties
              onCompletion: ^(id response, NSError *error) {
                  if (error) {
                      self.error = error;
                      [self revisionFailed];
                  } else {
                      LogVerbose(Sync, @"%@: Sent %@ (JSON), response=%@", self, rev, response);
                      [self removePending: rev];
                  }
                  [self asyncTasksFinished: 1];
              }];
}


- (void) startNextUpload {
    if (!_uploading && _uploaderQueue.count > 0) {
        _uploading = YES;
        CBLMultipartUploader* uploader = _uploaderQueue[0];
        LogVerbose(Sync, @"%@: Starting %@", self, uploader);
        [_remoteSession startRequest: uploader];
        [_uploaderQueue removeObjectAtIndex: 0];
    }
}


- (void) stopRemoteRequests {
    NSArray* queue = _uploaderQueue;
    _uploaderQueue = nil;
    _uploading = NO;
    [queue makeObjectsPerformSelector: @selector(stop)];

    [super stopRemoteRequests];

}


// Given a revision and an array of revIDs, finds the latest common ancestor revID
// and returns its generation #. If there is none, returns 0.
int CBLFindCommonAncestor(CBL_Revision* rev, NSArray<CBL_RevID*>* possibleRevIDStrings) {
    if (possibleRevIDStrings.count == 0)
        return 0;
    NSArray<CBL_RevID*>* history = [CBLDatabase parseCouchDBRevisionHistory: rev.properties];
    Assert(history, @"rev is missing _revisions property");
    return [history firstObjectCommonWithArray: possibleRevIDStrings].generation;
}


@end
