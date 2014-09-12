//
//  CBL_Pusher.m
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

#import "CBL_Pusher.h"
#import "CBLDatabase.h"
#import "CBLDatabase+Insertion.h"
#import "CBL_Revision.h"
#import "CBLDatabaseChange.h"
#import "CBLBatcher.h"
#import "CBLMultipartUploader.h"
#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBJSONEncoder.h"
#import "CBLRevision.h"
#import "CBLDocument.h"


#define kMaxBulkDocsObjectSize (5*1000*1000) // Max in-memory size of buffered bulk_docs dictionary


static int findCommonAncestor(CBL_Revision* rev, NSArray* possibleIDs);


@interface CBL_Pusher ()
- (BOOL) uploadMultipartRevision: (CBL_Revision*)rev;
@end


@implementation CBL_Pusher


@synthesize createTarget=_createTarget;


- (BOOL) isPush {
    return YES;
}


- (CBLFilterBlock) filter {
    CBLFilterBlock filter = nil;
    if (_filterName) {
        CBLStatus status;
        filter = [_db compileFilterNamed: _filterName status: &status];
        if (!filter) {
            Warn(@"%@: No filter '%@' (err %d)", self, _filterName, status);
            if (!self.error) {
                self.error = CBLStatusToNSError(status, nil);
            }
            [self stop]; // this is fatal; don't know what to push
        }
    } else if (_docIDs) {
        NSArray* docIDs = _docIDs;
        filter = FILTERBLOCK({
            return [docIDs containsObject: revision.document.documentID];
        });
    }
    return filter;
}


// This is called before beginReplicating, if the target db might not exist
- (void) maybeCreateRemoteDB {
    if (!_createTarget)
        return;
    LogTo(Sync, @"Remote db might not exist; creating it...");
    _creatingTarget = YES;
    [self asyncTaskStarted];
    [self sendAsyncRequest: @"PUT" path: @"" body: nil onCompletion: ^(id result, NSError* error) {
        _creatingTarget = NO;
        if (error && error.code != kCBLStatusDuplicate) {
            LogTo(Sync, @"Failed to create remote db: %@", error);
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


- (void) beginReplicating {
    // If we're still waiting to create the remote db, do nothing now. (This method will be
    // re-invoked after that request finishes; see -maybeCreateRemoteDB above.)
    if (_creatingTarget)
        return;

    _pendingSequences = [NSMutableIndexSet indexSet];
    _maxPendingSequence = self.lastSequence.longLongValue;
    
    CBLFilterBlock filter = self.filter;
    if (!filter && self.error)
        return;

    // Include conflicts so all conflicting revisions are replicated too
    CBLChangesOptions options = kDefaultCBLChangesOptions;
    options.includeConflicts = YES;
    // Process existing changes since the last push:
    CBLDatabase* db = _db;
    [self addRevsToInbox: [db changesSinceSequence: [_lastSequence longLongValue]
                                           options: &options
                                            filter: filter
                                            params: _filterParameters]];
    [_batcher flush];  // process up to the first 100 revs
    
    // Now listen for future changes (in continuous mode):
    if (_continuous && !_observing) {
        _observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(dbChanged:)
                                                     name: CBL_DatabaseChangesNotification object: db];
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
    _uploaderQueue = nil;
    _uploading = NO;
    [self stopObserving];
    [super stop];
}


// Adds a local revision to the "pending" set that are awaiting upload:
- (void) addPending: (CBL_Revision*)rev {
    SequenceNumber seq = rev.sequence;
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
}


- (void) dbChanged: (NSNotification*)n {
    NSArray* changes = (n.userInfo)[@"changes"];
    for (CBLDatabaseChange* change in changes) {
        // Skip revisions that originally came from the database I'm syncing to:
        if (![change.source isEqual: _remote]) {
            CBL_Revision* rev = change.addedRevision;
            CBLFilterBlock filter = self.filter;
            if (filter && ![_db runFilter: filter params: _filterParameters onRevision: rev])
                continue;
            CBL_MutableRevision* nuRev = [rev mutableCopy];
            nuRev.body = nil; // save memory
            LogTo(SyncVerbose, @"%@: Queuing #%lld %@", self, nuRev.sequence, nuRev);
            [self addToInbox: nuRev];
        }
    }
}


- (void) processInbox: (CBL_RevisionList*)changes {
    // Generate a set of doc/rev IDs in the JSON format that _revs_diff wants:
    // <http://wiki.apache.org/couchdb/HttpPostRevsDiff>
    NSMutableDictionary* diffs = $mdict();
    for (CBL_Revision* rev in changes) {
        NSString* docID = rev.docID;
        NSMutableArray* revs = diffs[docID];
        if (!revs) {
            revs = $marray();
            diffs[docID] = revs;
        }
        [revs addObject: rev.revID];
        [self addPending: rev];
    }
    
    // Call _revs_diff on the target db:
    [self asyncTaskStarted];
    [self sendAsyncRequest: @"POST" path: @"_revs_diff" body: diffs
              onCompletion:^(NSDictionary* results, NSError* error) {
        if (error) {
            self.error = error;
            [self revisionFailed];
        } else if (results.count) {
            // Go through the list of local changes again, selecting the ones the destination server
            // said were missing and mapping them to a JSON dictionary in the form _bulk_docs wants:
            CBLDatabase* db = _db;
            NSMutableArray* docsToSend = $marray();
            CBL_RevisionList* revsToSend = [[CBL_RevisionList alloc] init];
            size_t bufferedSize = 0;
            for (CBL_Revision* rev in changes.allRevisions) {
                @autoreleasepool {
                    // Is this revision in the server's 'missing' list?
                    NSDictionary* revResults = results[rev.docID];
                    NSArray* missing = revResults[@"missing"];
                    if (![missing containsObject: [rev revID]]) {
                        [self removePending: rev];
                        continue;
                    }

                    // Get the revision's properties:
                    NSDictionary* properties;
                    {
                        CBLContentOptions options = kCBLIncludeAttachments;
                        if (!_dontSendMultipart && self.revisionBodyTransformationBlock==nil)
                            options |= kCBLBigAttachmentsFollow;
                        CBLStatus status;
                        CBL_Revision* loadedRev = [db revisionByLoadingBody: rev options: options
                                                                     status: &status];
                        if (status >= 300) {
                            Warn(@"%@: Couldn't get local contents of %@", self, rev);
                            [self revisionFailed];
                            continue;
                        }
                        CBL_MutableRevision* populatedRev = [[self transformRevision: loadedRev] mutableCopy];

                        // Add the revision history:
                        NSArray* possibleAncestors = revResults[@"possible_ancestors"];
                        populatedRev[@"_revisions"] = [db getRevisionHistoryDict: populatedRev
                                                               startingFromAnyOf: possibleAncestors];
                        properties = populatedRev.properties;

                        // Strip any attachments already known to the target db:
                        if (properties.cbl_attachments) {
                            // Look for the latest common ancestor and stub out older attachments:
                            int minRevPos = findCommonAncestor(populatedRev, possibleAncestors);
                            [CBLDatabase stubOutAttachmentsIn: populatedRev beforeRevPos: minRevPos + 1
                                            attachmentsFollow: NO];
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
            
        } else {
            // None of the revisions are new to the remote
            for (CBL_Revision* rev in changes.allRevisions)
                [self removePending: rev];
        }
        [self asyncTasksFinished: 1];
    }];
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
    LogTo(SyncVerbose, @"%@: Sending %@", self, changes.allRevisions);
    self.changesTotal += numDocsToSend;
    [self asyncTaskStarted];
    [self sendAsyncRequest: @"POST"
                      path: @"_bulk_docs"
                      body: $dict({@"docs", docsToSend},
                                  {@"new_edits", $false})
              onCompletion: ^(NSDictionary* response, NSError *error) {
                  if (!error) {
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
                                  NSString* docID = item[@"id"];
                                  [failedIDs addObject: docID];
                                  NSURL* url = docID ? [_remote URLByAppendingPathComponent: docID]
                                                     : nil;
                                  error = CBLStatusToNSError(status, url);
                              }
                          }
                      }

                      // Remove from the pending list all the revs that didn't fail:
                      for (CBL_Revision* rev in changes.allRevisions) {
                          if (![failedIDs containsObject: rev.docID])
                              [self removePending: rev];
                      }
                  }
                  if (error) {
                      self.error = error;
                      [self revisionFailed];
                  } else {
                      LogTo(SyncVerbose, @"%@: Sent %@", self, changes.allRevisions);
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


- (BOOL) uploadMultipartRevision: (CBL_Revision*)rev {
    // Find all the attachments with "follows" instead of a body, and put 'em in a multipart stream.
    // It's important to scan the _attachments entries in the same order in which they will appear
    // in the JSON, because CouchDB expects the MIME bodies to appear in that same order (see #133).
    CBLMultipartWriter* bodyStream = nil;
    NSDictionary* attachments = rev.attachments;
    for (NSString* attachmentName in [CBJSONEncoder orderedKeys: attachments]) {
        NSDictionary* attachment = attachments[attachmentName];
        if (attachment[@"follows"]) {
            if (!bodyStream) {
                // Create the HTTP multipart stream:
                bodyStream = [[CBLMultipartWriter alloc] initWithContentType: @"multipart/related"
                                                                    boundary: nil];
                [bodyStream setNextPartsHeaders: @{@"Content-Type": @"application/json"}];
                // Use canonical JSON encoder so that _attachments keys will be written in the
                // same order that this for loop is processing the attachments.
                NSError* error;
                NSData* json = [CBJSONEncoder canonicalEncoding: rev.properties error: &error];
                if (error) {
                    Warn(@"%@: Creating canonical JSON data got an error: %@", self, error);
                    return NO;
                }

                if (self.canSendCompressedRequests)
                    [bodyStream addGZippedData: json];
                else
                    [bodyStream addData: json];
            }
            // Add attachment as another MIME part:
            NSString* disposition = $sprintf(@"attachment; filename=%@",
                                             CBLQuoteString(attachmentName));
            NSString* contentType = attachment[@"type"];
            NSString* contentEncoding = attachment[@"encoding"];
            [bodyStream setNextPartsHeaders: $dict({@"Content-Disposition", disposition},
                                                   {@"Content-Type", contentType},
                                                   {@"Content-Encoding", contentEncoding})];
            [bodyStream addFileURL: [_db fileForAttachmentDict: attachment]];
        }
    }
    if (!bodyStream)
        return NO;
    
    // OK, we are going to upload this on its own:
    self.changesTotal++;
    [self asyncTaskStarted];

    NSString* path = $sprintf(@"%@?new_edits=false", CBLEscapeURLParam(rev.docID));
    __block CBLMultipartUploader* uploader = [[CBLMultipartUploader alloc]
                                  initWithURL: CBLAppendToURL(_remote, path)
                                     streamer: bodyStream
                               requestHeaders: self.requestHeaders
                                 onCompletion: ^(CBLMultipartUploader* result, NSError *error) {
                  [self removeRemoteRequest: uploader];
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
                      LogTo(SyncVerbose, @"%@: Sent multipart %@", self, rev);
                      [self removePending: rev];
                  }
                  self.changesProcessed++;
                  [self asyncTasksFinished: 1];

                  _uploading = NO;
                  [self startNextUpload];
              }
     ];
    [self addRemoteRequest: uploader];
    LogTo(SyncVerbose, @"%@: Queuing %@ (multipart, %lldkb)", self, uploader, bodyStream.length/1024);
    if (!_uploaderQueue)
        _uploaderQueue = [[NSMutableArray alloc] init];
    [_uploaderQueue addObject: uploader];
    [self startNextUpload];
    return YES;
}


// Fallback to upload a revision if uploadMultipartRevision failed due to the server's rejecting
// multipart format.
- (void) uploadJSONRevision: (CBL_Revision*)rev {
    // Get the revision's properties:
    NSError* error;
    if (![_db inlineFollowingAttachmentsIn: rev error: &error]) {
        self.error = error;
        [self revisionFailed];
        return;
    }

    [self asyncTaskStarted];
    NSString* path = $sprintf(@"%@?new_edits=false", CBLEscapeURLParam(rev.docID));
    [self sendAsyncRequest: @"PUT"
                      path: path
                      body: rev.properties
              onCompletion: ^(id response, NSError *error) {
                  if (error) {
                      self.error = error;
                      [self revisionFailed];
                  } else {
                      LogTo(SyncVerbose, @"%@: Sent %@ (JSON), response=%@", self, rev, response);
                      [self removePending: rev];
                  }
                  [self asyncTasksFinished: 1];
              }];
}


- (void) startNextUpload {
    if (!_uploading && _uploaderQueue.count > 0) {
        _uploading = YES;
        CBLMultipartUploader* uploader = _uploaderQueue[0];
        LogTo(SyncVerbose, @"%@: Starting %@", self, uploader);
        [uploader start];
        [_uploaderQueue removeObjectAtIndex: 0];
    }
}


// Given a revision and an array of revIDs, finds the latest common ancestor revID
// and returns its generation #. If there is none, returns 0.
static int findCommonAncestor(CBL_Revision* rev, NSArray* possibleRevIDs) {
    if (possibleRevIDs.count == 0)
        return 0;
    NSArray* history = [CBLDatabase parseCouchDBRevisionHistory: rev.properties];
    Assert(history, @"rev is missing _revisions property");
    NSString* ancestorID = [history firstObjectCommonWithArray: possibleRevIDs];
    if (!ancestorID)
        return 0;
    int generation;
    if (![CBL_Revision parseRevID: ancestorID intoGeneration: &generation andSuffix: NULL])
        generation = 0;
    return generation;
}


@end




TestCase(CBL_Pusher_findCommonAncestor) {
    NSDictionary* revDict = $dict({@"ids", @[@"second", @"first"]}, {@"start", @2});
    CBL_Revision* rev = [CBL_Revision revisionWithProperties: $dict({@"_revisions", revDict})];
    CAssertEq(findCommonAncestor(rev, @[]), 0);
    CAssertEq(findCommonAncestor(rev, @[@"3-noway", @"1-nope"]), 0);
    CAssertEq(findCommonAncestor(rev, @[@"3-noway", @"1-first"]), 1);
    CAssertEq(findCommonAncestor(rev, @[@"3-noway", @"2-second", @"1-first"]), 2);
}
