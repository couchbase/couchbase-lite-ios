//
//  TDPusher.m
//  TouchDB
//
//  Created by Jens Alfke on 12/5/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDPusher.h"
#import <TouchDB/TDDatabase.h>
#import "TDDatabase+Insertion.h"
#import <TouchDB/TDRevision.h>
#import "TDBatcher.h"
#import "TDMultipartUploader.h"
#import "TDInternal.h"
#import "TDMisc.h"
#import "TDCanonicalJSON.h"


static int findCommonAncestor(TDRevision* rev, NSArray* possibleIDs);


@interface TDPusher ()
- (BOOL) uploadMultipartRevision: (TDRevision*)rev;
@end


@implementation TDPusher


@synthesize createTarget=_createTarget;


- (BOOL) isPush {
    return YES;
}


- (TDFilterBlock) filter {
    return _filterName ? [_db filterNamed: _filterName] : NULL;
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
        if (error && error.code != kTDStatusDuplicate) {
            LogTo(Sync, @"Failed to create remote db: %@", error);
            self.error = error;
            [self stop];
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
    
    TDFilterBlock filter = self.filter;
    if (!filter && _filterName)
        Warn(@"%@: No TDFilterBlock registered for filter '%@'; ignoring", self, _filterName);
    
    // Include conflicts so all conflicting revisions are replicated too
    TDChangesOptions options = kDefaultTDChangesOptions;
    options.includeConflicts = YES;
    // Process existing changes since the last push:
    [self addRevsToInbox: [_db changesSinceSequence: [_lastSequence longLongValue]
                                            options: &options
                                             filter: filter
                                             params: _filterParameters]];
    [_batcher flush];  // process up to the first 100 revs
    
    // Now listen for future changes (in continuous mode):
    if (_continuous && !_observing) {
        _observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(dbChanged:)
                                                     name: TDDatabaseChangeNotification object: _db];
    }

#ifdef GNUSTEP    // TODO: Multipart upload on GNUstep
    _dontSendMultipart = YES;
#endif
}


- (void) stopObserving {
    if (_observing) {
        _observing = NO;
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: TDDatabaseChangeNotification
                                                      object: _db];
    }
}


- (void) retry {
    // This is called if I've gone idle but some revisions failed to be pushed.
    // I should start the _changes feed over again, so I can retry all the revisions.
    [super retry];

    [self beginReplicating];
}


- (BOOL) goOffline {
    if (![super goOffline])
        return NO;
    [self stopObserving];
    return YES;
}


- (void) stop {
    setObj(&_uploaderQueue, nil);
    _uploading = NO;
    [self stopObserving];
    [super stop];
}


- (void) dbChanged: (NSNotification*)n {
    NSDictionary* userInfo = n.userInfo;
    // Skip revisions that originally came from the database I'm syncing to:
    if ([userInfo[@"source"] isEqual: _remote])
        return;
    TDRevision* rev = userInfo[@"rev"];
    TDFilterBlock filter = self.filter;
    if (filter && !filter(rev, _filterParameters))
        return;
    [self addToInbox: rev];
}


- (void) processInbox: (TDRevisionList*)changes {
    // Generate a set of doc/rev IDs in the JSON format that _revs_diff wants:
    // <http://wiki.apache.org/couchdb/HttpPostRevsDiff>
    NSMutableDictionary* diffs = $mdict();
    for (TDRevision* rev in changes) {
        NSString* docID = rev.docID;
        NSMutableArray* revs = diffs[docID];
        if (!revs) {
            revs = $marray();
            diffs[docID] = revs;
        }
        [revs addObject: rev.revID];
    }
    
    // Call _revs_diff on the target db:
    [self asyncTaskStarted];
    [self sendAsyncRequest: @"POST" path: @"/_revs_diff" body: diffs
              onCompletion:^(NSDictionary* results, NSError* error) {
        if (error) {
            self.error = error;
            [self revisionFailed];
            [self stop];
        } else if (results.count) {
            // Go through the list of local changes again, selecting the ones the destination server
            // said were missing and mapping them to a JSON dictionary in the form _bulk_docs wants:
            __block SequenceNumber lastInboxSequence = 0;
            NSArray* docsToSend = [changes.allRevisions my_map: ^id(TDRevision* rev) {
                NSDictionary* properties;
                @autoreleasepool {
                    // Is this revision in the server's 'missing' list?
                    NSDictionary* revResults = results[rev.docID];
                    NSArray* missing = revResults[@"missing"];
                    if (![missing containsObject: [rev revID]])
                        return nil;
                    
                    // Get the revision's properties:
                    TDContentOptions options = kTDIncludeAttachments | kTDIncludeRevs;
                    if (!_dontSendMultipart)
                        options |= kTDBigAttachmentsFollow;
                    if ([_db loadRevisionBody: rev options: options] >= 300) {
                        Warn(@"%@: Couldn't get local contents of %@", self, rev);
                        [self revisionFailed];
                        return nil;
                    }
                    properties = rev.properties;
                    Assert(properties[@"_revisions"]);
                    
                    // Strip any attachments already known to the target db:
                    if (properties[@"_attachments"]) {
                        // Look for the latest common ancestor and stub out older attachments:
                        NSArray* possible = revResults[@"possible_ancestors"];
                        int minRevPos = findCommonAncestor(rev, possible);
                        [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: minRevPos + 1
                                       attachmentsFollow: NO];
                        properties = rev.properties;
                        // If the rev has huge attachments, send it under separate cover:
                        if (!_dontSendMultipart && [self uploadMultipartRevision: rev])
                            return nil;
                    }
                    [properties retain];  // (to survive impending autorelease-pool drain)
                }
                lastInboxSequence = rev.sequence;
                Assert(properties[@"_id"]);
                return [properties autorelease];
            }];
            
            // Post the revisions to the destination:
            [self uploadBulkDocs: docsToSend changes: changes lastSequence: lastInboxSequence];
            
        } else {
            // If none of the revisions are new to the remote, just bump the lastSequence:
            self.lastSequence = $sprintf(@"%lld", [changes.allRevisions.lastObject sequence]);
        }
        [self asyncTasksFinished: 1];
    }];
}


// Post the revisions to the destination. "new_edits":false means that the server should
// use the given _rev IDs instead of making up new ones.
- (void) uploadBulkDocs: (NSArray*)docsToSend
                changes: (TDRevisionList*)changes
           lastSequence: (SequenceNumber)lastInboxSequence
{
    NSUInteger numDocsToSend = docsToSend.count;
    if (numDocsToSend == 0)
        return;
    LogTo(Sync, @"%@: Sending %u revisions", self, (unsigned)numDocsToSend);
    LogTo(SyncVerbose, @"%@: Sending %@", self, changes.allRevisions);
    self.changesTotal += numDocsToSend;
    [self asyncTaskStarted];
    [self sendAsyncRequest: @"POST"
                      path: @"/_bulk_docs"
                      body: $dict({@"docs", docsToSend},
                                  {@"new_edits", $false})
              onCompletion: ^(NSDictionary* response, NSError *error) {
                  if (!error) {
                      // _bulk_docs response is really an array, not a dictionary!
                      for (NSDictionary* item in $castIf(NSArray, response)) {
                          if (item[@"error"]) {
                              // One of the docs failed to save:
                              Warn(@"%@: _bulk_docs got an error: %@", self, item);
                              error = TDStatusToNSError(kTDStatusUpstreamError, nil);
                          }
                      }
                  }
                  if (error) {
                      self.error = error;
                      [self revisionFailed];
                  } else {
                      LogTo(SyncVerbose, @"%@: Sent %@", self, changes.allRevisions);
                      self.lastSequence = $sprintf(@"%lld", lastInboxSequence);
                  }
                  self.changesProcessed += numDocsToSend;
                  [self asyncTasksFinished: 1];
              }
     ];
}


- (BOOL) uploadMultipartRevision: (TDRevision*)rev {
    // Find all the attachments with "follows" instead of a body, and put 'em in a multipart stream.
    // It's important to scan the _attachments entries in the same order in which they will appear
    // in the JSON, because CouchDB expects the MIME bodies to appear in that same order (see #133).
    TDMultipartWriter* bodyStream = nil;
    NSDictionary* attachments = rev[@"_attachments"];
    for (NSString* attachmentName in [TDCanonicalJSON orderedKeys: attachments]) {
        NSDictionary* attachment = attachments[attachmentName];
        if (attachment[@"follows"]) {
            if (!bodyStream) {
                // Create the HTTP multipart stream:
                bodyStream = [[[TDMultipartWriter alloc] initWithContentType: @"multipart/related"
                                                                      boundary: nil] autorelease];
                [bodyStream setNextPartsHeaders: $dict({@"Content-Type", @"application/json"})];
                // Use canonical JSON encoder so that _attachments keys will be written in the
                // same order that this for loop is processing the attachments.
                NSData* json = [TDCanonicalJSON canonicalData: rev.properties];
                [bodyStream addData: json];
            }
            NSString* disposition = $sprintf(@"attachment; filename=%@", TDQuoteString(attachmentName));
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

    NSString* path = $sprintf(@"/%@?new_edits=false", TDEscapeID(rev.docID));
    NSString* urlStr = [_remote.absoluteString stringByAppendingString: path];
    __block TDMultipartUploader* uploader = [[[TDMultipartUploader alloc]
                                  initWithURL: [NSURL URLWithString: urlStr]
                                     streamer: bodyStream
                               requestHeaders: self.requestHeaders
                                 onCompletion: ^(id response, NSError *error) {
                  if (error) {
                      if ($equal(error.domain, TDHTTPErrorDomain)
                                && error.code == kTDStatusUnsupportedType) {
                          // Server doesn't like multipart, eh? Fall back to JSON.
                          _dontSendMultipart = YES;
                          [self uploadJSONRevision: rev];
                      } else {
                          self.error = error;
                          [self revisionFailed];
                      }
                  } else {
                      LogTo(SyncVerbose, @"%@: Sent %@, response=%@", self, rev, response);
                      self.lastSequence = $sprintf(@"%lld", rev.sequence);
                  }
                  self.changesProcessed++;
                  [self asyncTasksFinished: 1];
                  [self removeRemoteRequest: uploader];

                  _uploading = NO;
                  [self startNextUpload];
              }
     ] autorelease];
    uploader.authorizer = _authorizer;
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
- (void) uploadJSONRevision: (TDRevision*)rev {
    // Get the revision's properties:
    NSError* error;
    if (![_db inlineFollowingAttachmentsIn: rev error: &error]) {
        self.error = error;
        [self revisionFailed];
        return;
    }

    [self asyncTaskStarted];
    NSString* path = $sprintf(@"/%@?new_edits=false", TDEscapeID(rev.docID));
    [self sendAsyncRequest: @"PUT"
                      path: path
                      body: rev.properties
              onCompletion: ^(id response, NSError *error) {
                  if (error) {
                      self.error = error;
                      [self revisionFailed];
                  } else {
                      LogTo(SyncVerbose, @"%@: Sent %@ (JSON), response=%@", self, rev, response);
                      self.lastSequence = $sprintf(@"%lld", rev.sequence);
                  }
                  [self asyncTasksFinished: 1];
              }];
}


- (void) startNextUpload {
    if (!_uploading && _uploaderQueue.count > 0) {
        _uploading = YES;
        TDMultipartUploader* uploader = _uploaderQueue[0];
        LogTo(SyncVerbose, @"%@: Starting %@", self, uploader);
        [uploader start];
        [_uploaderQueue removeObjectAtIndex: 0];
    }
}


// Given a revision and an array of revIDs, finds the latest common ancestor revID
// and returns its generation #. If there is none, returns 0.
static int findCommonAncestor(TDRevision* rev, NSArray* possibleRevIDs) {
    if (possibleRevIDs.count == 0)
        return 0;
    NSArray* history = [TDDatabase parseCouchDBRevisionHistory: rev.properties];
    NSString* ancestorID = [history firstObjectCommonWithArray: possibleRevIDs];
    if (!ancestorID)
        return 0;
    int generation;
    if (![TDRevision parseRevID: ancestorID intoGeneration: &generation andSuffix: NULL])
        generation = 0;
    return generation;
}


@end




TestCase(TDPusher_findCommonAncestor) {
    NSDictionary* revDict = $dict({@"ids", @[@"second", @"first"]}, {@"start", @2});
    TDRevision* rev = [TDRevision revisionWithProperties: $dict({@"_revisions", revDict})];
    CAssertEq(findCommonAncestor(rev, @[]), 0);
    CAssertEq(findCommonAncestor(rev, @[@"3-noway", @"1-nope"]), 0);
    CAssertEq(findCommonAncestor(rev, @[@"3-noway", @"1-first"]), 1);
    CAssertEq(findCommonAncestor(rev, @[@"3-noway", @"2-second", @"1-first"]), 2);
}
