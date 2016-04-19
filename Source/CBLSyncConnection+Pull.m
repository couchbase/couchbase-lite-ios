//
//  CBLSyncConnection+Pull.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/27/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "CBLSyncConnection_Internal.h"
#import "CBL_BlobStoreWriter.h"
#import "CBL_Body.h"
#import "MYBuffer.h"


UsingLogDomain(Sync);


@interface PendingRev : NSObject
@property NSData* body;
@property NSDictionary* attachments;
@property NSArray* history;
@property id sequenceID;
@end

@implementation PendingRev
@synthesize body, attachments, history, sequenceID;
@end


@implementation CBLSyncConnection (Pull)


// Unless specified, all the methods below must be called on the _syncQueue.


#pragma mark - CHANGES


// Starting point of an active pull (called once checkpoints are loaded.)
- (void) requestChangesSince: (id)sinceSequence
                 inBatchesOf: (NSUInteger)batchSize
                  continuous: (BOOL)continuous
{
    LogVerbose(Sync, @"    Sending request for changes since '%@'", sinceSequence);
    _pullCatchingUp = YES;
    BLIPRequest* request = _connection.request;
    request.profile = @"subChanges";
    if (sinceSequence) {
        NSData* json = [CBLJSON dataWithJSONObject: sinceSequence
                                           options: CBLJSONWritingAllowFragments error: NULL];
        if (json)
            request[@"since"] = [[NSString alloc] initWithData:json encoding: NSUTF8StringEncoding];
    } else {
        request[@"deleted"] = @"false"; // Optimization: On first sync, ignore already-deleted docs
    }
    if (batchSize)
        request[@"batch"] = $sprintf(@"%lu", (unsigned long)batchSize);
    if (continuous)
        request[@"continuous"] = @"true";
    if (_pullFilterName) {
        request[@"filter"] = _pullFilterName;
        for (NSString* param in _pullFilterParams) {
            if (!request[param])
                request[param] = _pullFilterParams[param];
        }
    }
    __weak BLIPResponse* response = [request send];
    response.onComplete = ^(BLIPResponse* response) {
        [self gotError: response]; // checks for error
    };
}


// Starting point of a passive pull: peer is pushing its changes to me
- (void) handleIncomingChanges: (BLIPRequest*)request {
    NSArray* changes = $castIf(NSArray, request.bodyJSON);
    // (Note: even if we got 0 changes (i.e. caught up) we still need to go through the db queue
    // before announcing it, so previously queued change processing blocks get to run first.)
    LogTo(Sync, @"Received %u changes", (unsigned)changes.count);
    if (![self accessCheckForRequest: request])
        return;
    [request deferResponse];
    [self onDatabaseQueue: ^{
        CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
        NSUInteger numRequested = 0;
        NSMutableArray* responseInfo = nil;
        NSMutableArray* revsToInsert = $marray();
        if (changes.count > 0) {
            responseInfo = [NSMutableArray arrayWithCapacity: changes.count];
            NSArray* none = @[];
            NSUInteger realSize = 0;
            for (NSArray* change in changes) {
                NSString* docID = change[1];
                NSString* revID = change[2];
                NSArray* ancestors = [_db getPossibleAncestorsOfDocID: docID revID: revID
                                                                limit: kMaxPossibleAncestorsToSend];
                if ([ancestors.firstObject isEqualToString: revID]) {
                    LogVerbose(Sync, @"    ...already have {%@, %@}", docID, revID);
                    [responseInfo addObject: @0];
#if 0
                } else if (change.count >= 4 && [change[3] boolValue]) {
                    // Deleted rev: just make it up
                    NSDictionary* body = @{@"_id": docID, @"_rev": revID, @"_deleted": @YES};
                    PendingRev* rev = [[PendingRev alloc] init];
                    rev.body = [CBLJSON dataWithJSONObject: body options: 0 error: NULL];
                    rev.history = @[];
                    rev.sequenceID = change[0];
                    [revsToInsert addObject: rev];
                    numRequested++;
                    [responseInfo addObject: @0];
#endif
                } else {
                    [responseInfo addObject: ancestors ?: none];
                    LogVerbose(Sync, @"    Requesting {%@, %@}; I have %@", docID, revID, ancestors);
                    numRequested++;
                    realSize = responseInfo.count;
                }
            }
            [responseInfo removeObjectsInRange: NSMakeRange(realSize, responseInfo.count - realSize)];
        }
        NSUInteger maxHistory = _db.maxRevTreeDepth;
        time = CFAbsoluteTimeGetCurrent() - time;
        LogTo(Sync, @"Looked up %u revisions (%lu new) in %.4f sec",
              (unsigned)changes.count, (unsigned long)numRequested, time);

        [self onSyncQueue: ^{
            if (changes.count == 0) {
                LogTo(Sync, @"Caught up with incoming changes!");
                _pullCatchingUp = NO;
                _updateStateSoon();
            } else {
                //FIX: Shouldn't update this until the revs are saved to the db
                _remoteCheckpointSequence = changes.lastObject[0];
                [self noteLastSequenceChanged];

                _awaitingRevs += numRequested;
                if (_pullProgress.indeterminate || _state == kSyncIdle) {
                    // Starting, or was idle:
                    _pullProgress.completedUnitCount = 0;
                    _pullProgress.totalUnitCount = numRequested;
                } else {
                    _pullProgress.totalUnitCount += numRequested;
                }
                BLIPResponse* response = request.response;
                response[@"maxHistory"] = $sprintf(@"%lu", (unsigned long)maxHistory);
                response.bodyJSON = responseInfo;
                [response send];
                // The next step is that the peer will send docs, invoking -handleIncomingRevision
            }
            for (PendingRev* rev in revsToInsert) {
                _awaitingRevs--;
                _insertingRevs++;
                [self queueInsertPendingRev: rev];
            }
        }];
    }];
}


#pragma mark - DOCUMENTS/REVISIONS/ATTACHMENTS


// Received a "rev" request
- (void) handleIncomingRevision: (BLIPRequest*)request {
    _awaitingRevs--;
    if (![self accessCheckForRequest: request])
        return;
    _insertingRevs++;

    // Look for "_attachments" property, trying not to parse JSON if we can avoid it:
    NSDictionary* attachments = nil;
    NSString* docID;
    NSData* json = request.body;
    if (memmem(json.bytes, json.length, "\"_attachments\":", 15) != NULL) {
        NSDictionary* props = [NSJSONSerialization JSONObjectWithData: json options: 0 error: NULL];
        attachments = $castIf(NSDictionary, props[@"_attachments"]);
        docID = props.cbl_id;
    }
    
    if (attachments.count == 0) {
        [self queueRevisionToInsert: request withAttachments: nil];
        return;
    }

    LogVerbose(Sync, @"Checking %lu attachments of doc '%@'...",
          (unsigned long)attachments.count, docID);
    [request deferResponse];

    // OK, this document has attachments, so we have to move to the DB queue to look them up:
    [self onDatabaseQueue: ^{
        NSMutableDictionary* needDigests = [NSMutableDictionary new];
        for (NSString* name in attachments) {
            NSDictionary* attachment = attachments[name];
            NSString* digest = attachment[@"digest"];
            if (digest && ![_db hasAttachmentWithDigest: digest]) {
                NSMutableDictionary* mattachment = [attachment mutableCopy];
                mattachment[@"name"] = name;
                needDigests[digest] = mattachment;
            }
        }

        [self onSyncQueue: ^{
            if (needDigests.count == 0) {
                // Already have these attachments, so go ahead and insert:
                [self queueRevisionToInsert: request withAttachments: nil];
                [request respondWithData: nil contentType: nil];
            } else {
                // Alright, need to request some attachments before we can insert the revision:
                LogVerbose(Sync, @"Still need attachments {%@} of doc '%@'...",
                      [needDigests.allKeys componentsJoinedByString: @", "], docID);
                NSMutableDictionary* attWritersByDigest = $mdict();
                __block BOOL ok = YES;
                for (NSString* digest in needDigests) {
                    [self requestAttachment: needDigests[digest]
                                      named: needDigests[digest][@"name"]
                                 onComplete: ^(CBL_BlobStoreWriter* writer) {
                        if (writer)
                            attWritersByDigest[digest] = writer;
                        else
                            ok = NO;
                        [needDigests removeObjectForKey: digest];
                        if (needDigests.count == 0) {
                            // Got all the attachments! Now we can insert:
                            if (ok) {
                                [self queueRevisionToInsert: request
                                            withAttachments: attWritersByDigest];
                                [request respondWithData: nil contentType: nil];
                            } else {
                                --_insertingRevs;
                                _updateStateSoon();
                                [self failedToGetRevision: @"missing attachment(s)"];
                                [request respondWithErrorCode: 500
                                                      message: @"Couldn't get attachments"];
                            }
                        }
                    }];
                }
            }
        }];
    }];
}


- (void) requestAttachment: (NSDictionary*)attachment
                     named: (NSString*)name
                onComplete: (void (^)(CBL_BlobStoreWriter*))onComplete
{
    NSString* digest = attachment[@"digest"];
    NSNumber* lengthObj = (attachment[@"encoded_length"] ?: attachment[@"length"]);
    uint64_t length = [lengthObj unsignedLongLongValue];
    LogVerbose(Sync, @"Requesting attachment with digest %@ (%llu bytes)", digest, length);
    _pullProgress.totalUnitCount += length/1024;
    [_pullProgress becomeCurrentWithPendingUnitCount: length/1024];
    NSProgress* attProgress = [self addAttachmentProgressWithName: name
                                                           length: length
                                                          pulling: YES];
    [_pullProgress resignCurrent];

    //FIX: Calling CBL stuff on the wrong queue. But the BlobStoreWriter doesn't care what queue
    // it's called on as long as it's not re-entrant. (Except for -install, but we don't call that)
    CBL_BlobStoreWriter* writer = [_db attachmentWriter];

    BLIPRequest* request = [_connection request];
    request.profile = @"getAttachment";
    request[@"digest"] = digest;
    request[@"compress"] = ShouldCompressAttachment(name, attachment) ? @"true" : nil;
    BLIPResponse* response = [request send];
    __block uint64_t bytesReceived = 0;
    __block CFAbsoluteTime lastProgressUpdateTime = CFAbsoluteTimeGetCurrent();
    response.onDataReceived = ^(BLIPMessage* response, id<MYReader> reader) {
        uint8_t buffer[4096];
        while (true) {
            size_t len = [reader readBytes: buffer maxLength: sizeof(buffer)];
            if (len <= 0)
                break;
            NSData* data = [[NSData alloc] initWithBytesNoCopy: buffer length: len freeWhenDone: NO];
            [writer appendData: data];
            bytesReceived += len;
        }
        if (ItsBeenAtLeast(kProgressUpdateInterval, &lastProgressUpdateTime))
            attProgress.completedUnitCount = MIN(bytesReceived, length);
    };
    response.onComplete = ^(BLIPResponse* response) {
        NSError* error = response.error;
        if (error == nil) {
            [writer finish];
            LogVerbose(Sync, @"Received attachment with digest %@ (%llu bytes)",
                  digest, writer.bytesWritten);
            [self removeAttachmentProgress: attProgress pulling: YES];
            if ([writer.SHA1DigestString isEqualToString: digest]) {
                onComplete(writer);
            } else {
                Warn(@"Attachment received has digest %@; should have been %@ (%llu bytes)",
                     writer.SHA1DigestString, digest, writer.bytesWritten);
                [writer cancel];
                onComplete(nil);
            }
        } else {
            [writer cancel];
            if (error.code == 404 && [error.domain isEqualToString: @"HTTP"]) {
                Warn(@"Peer doesn't have body of attachment %@ (got 404 error)", digest);
                onComplete(nil);
            } else {
                [self gotError: response]; // fatal
            }
        }
    };
}


- (void) failedToGetRevision: (NSString*)reason {
    Warn(@"Failed to add doc: %@", reason);
    _pullProgress.completedUnitCount++;
}


#pragma mark - INSERTING REVISIONS:


- (void) queueRevisionToInsert: (BLIPRequest*)request withAttachments: (NSDictionary*)attachments {
    PendingRev* rev = [[PendingRev alloc] init];
    NSString* history = request[@"history"];
    if (history.length > 0)
        rev.history = [history componentsSeparatedByString: @","];
    rev.body = request.body;
    rev.sequenceID = request[@"sequence"];
    rev.attachments = attachments;
    [self queueInsertPendingRev: rev];
}


- (void) queueInsertPendingRev: (PendingRev*)rev {
    if (!_insertDBQueue) {
#if PARALLEL_INSERTS
        dispatch_sync(_dbQueue, ^{
            _insertDBQueue = dispatch_queue_create("Sync DB insert", DISPATCH_QUEUE_SERIAL);
            CBLManager* mgr = [_db.manager copy];
            mgr.dispatchQueue = _insertDBQueue;
            _insertDB = mgr[_db.name];
            //FIX: TODO: Close the db & manager after replication is done
        });
#else
        _insertDBQueue = _dbQueue;
        _insertDB = _db;
#endif
    }

    if (!_revsToInsert) {
        _revsToInsert = [NSMutableArray arrayWithCapacity: 500];
        _updateStateSoon();
        NSArray* currentRevsToInsert = _revsToInsert;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(kInsertBatchInterval * NSEC_PER_SEC)),
                       _syncQueue,
                       ^{
                           if (_revsToInsert == currentRevsToInsert)
                               [self insertRevisions];
                       });
    }
    [_revsToInsert addObject: rev];
    if (_revsToInsert.count >= kMaxRevsToInsert)
        [self insertRevisions];
}


- (void) insertRevisions {
    NSArray* revs = _revsToInsert;
    _revsToInsert = nil;
    _updateStateSoon();

    dispatch_async(_insertDBQueue, ^{
        // DO NOT USE _db IN THIS BLOCK! Use _insertDB instead!
        CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
        __block NSUInteger inserted = 0;
        [_insertDB inTransaction:^BOOL{
            for (PendingRev* rev in revs) {
                @autoreleasepool {
                    if (rev.attachments)
                        [_insertDB rememberAttachmentWritersForDigests: rev.attachments];
                    NSError* error;
                    if ([_insertDB forceInsertRevisionWithJSON: rev.body
                                               revisionHistory: rev.history
                                                        source: _connection.URL
                                                         error: &error]) {
                        if (WillLogVerbose(Sync)) {
                            NSDictionary* doc = [CBLJSON JSONObjectWithData: rev.body options: 0
                                                                      error: NULL];
                            LogVerbose(Sync, @"    Inserted {'%@' %@}, sequence #%@, +%lu ancestors",
                                  doc.cbl_id, doc.cbl_rev, rev.sequenceID, (unsigned long)rev.history.count);
                        }
                        ++inserted;
                    } else if (error.code == 403 && [error.domain isEqualToString: CBLHTTPErrorDomain]) {
                        LogVerbose(Sync, @"    Revision rejected by local validator");
                        // Validation failure doesn't count as an error. Don't retry.
                    } else {
                        Warn(@"SyncHandler: Couldn't insert rev: %@", error.my_compactDescription);
                        [self failedToGetRevision: @"db insertion failed"];
                    }
                }
            }
            return YES;
        }];
        time = CFAbsoluteTimeGetCurrent() - time;
        LogTo(Sync, @"Inserted %3u revisions in %.4f sec (%.0f/sec)",
              (unsigned)revs.count, time, revs.count/time);
#ifdef TIME_DB_QUEUE
        _dbQueueTotalInsertTime += time;
#endif

        [self onSyncQueue: ^{
            _pullProgress.completedUnitCount += inserted;
            _insertingRevs -= revs.count;
            _updateStateSoon();
        }];
    });
}


#pragma mark - UTILITIES:


static BOOL ItsBeenAtLeast(NSTimeInterval minInterval, CFAbsoluteTime* time) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - *time < minInterval)
        return NO;
    *time = now;
    return YES;
}


//NOTE: This comes from CBL_Attachment.m in the feature/deltas branch.
static BOOL ShouldCompressAttachment(NSString* name, NSDictionary* metadata) {
    if (metadata[@"encoding"] != nil)
        return NO;
    NSNumber* length = $castIf(NSNumber, metadata[@"length"]);
    if (length && length.unsignedLongLongValue < kMinLengthToCompress)
        return NO;

    NSString* contentType = metadata[@"content_type"];

    static NSSet* sCompressibleExtensions;
    static NSArray* sCompressibleSubtypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sCompressibleExtensions = [NSSet setWithObjects: @"txt", @"rtf", @"html", @"htm", @"xml",
                                   @"json", @"yaml", @"yml", @"csv", @"tex", @"svg", @"plist", @"pdf", nil];
        sCompressibleSubtypes = @[@"json", @"xml", @"html", @"yaml", @"pdf"];
    });

    // Filename extensions that indicate compressible data:
    if ([sCompressibleExtensions containsObject: name.pathExtension.lowercaseString])
        return YES;
    // Any textual MIME type is compressible:
    if ([contentType hasPrefix: @"text/"])
        return YES;
    // Look for types like "application/json" or "application/rss+xml":
    if ([contentType hasPrefix: @"application/"])
        for (NSString* subtype in sCompressibleSubtypes)
            if ([contentType rangeOfString: subtype].length > 0)
                return YES;

    return NO; // Be conservative, default to storing as-is
}


@end
