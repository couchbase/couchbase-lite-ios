//
//  CBLSyncConnection+Push.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/27/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "CBLSyncConnection_Internal.h"
#import "CBLInternal.h"
#import <CommonCrypto/CommonDigest.h>


@implementation CBLSyncConnection (Push)


// Unless specified, all the methods below must be called on the _syncQueue.


#pragma mark - CHANGES:


// Starting point of a passive push (called by peer when it starts pulling.)
- (void) handleSubscribeToChanges: (BLIPRequest*)request {
    if (![self accessCheckForRequest: request])
        return;
    
    uint64_t since = MAX(0, [request[@"since"] longLongValue]);
    if (request[@"batch"])
        _changesBatchSize = MAX(0, [request[@"batch"] integerValue]);
    if (request[@"continuous"])
        _pushContinuousChanges = YES;

    NSString* filterName = request[@"filter"];
    if (filterName) {
        dispatch_sync(_dbQueue, ^{
            _pushFilter = [_db filterNamed: filterName];
        });
        if (!_pushFilter) {
            [request respondWithErrorCode: kBLIPError_NotFound message: @"No such filter"];
            return;
        }
        NSData* data = [request[@"filterParams"]  dataUsingEncoding: NSUTF8StringEncoding];
        if (_pushFilter && data) {
            id params = $castIf(NSDictionary, [CBLJSON JSONObjectWithData: data
                                                                  options: 0
                                                                    error: NULL]);
            _pushFilterParams = $castIf(NSDictionary, params);
        } else {
            _pushFilterParams = nil;
        }
    }

    [self sendChangesSince: since];
}


// Call on database queue!
- (CBLQueryEnumerator*) pendingDocumentsSince: (uint64_t)since limit: (NSUInteger)limit {
    CBLQuery* query = [_db createAllDocumentsQuery];
    query.allDocsMode = kCBLBySequence;
    query.startKey = @(since);
    query.inclusiveStart = NO;
    if (limit > 0)
        query.limit = limit;
    __typeof(_pushFilter) pushFilter = _pushFilter;
    if (pushFilter) {
        query.filterBlock = ^BOOL(CBLQueryRow* row) {
            return pushFilter(row.document.currentRevision, _pushFilterParams);
        };
    }
    NSError* error;
    CBLQueryEnumerator* e = [query run: &error];
    if (!e) {
        Warn(@"SyncHandler: Couldn't get changes from db: %@", error.my_compactDescription);
        self.error = error;
    }
    return e;
}


// Public API; called on database queue
- (CBLQueryEnumerator*) pendingDocuments {
    if (!_pushing)
        return nil;
    return [self pendingDocumentsSince: _localCheckpointSequence limit: 0];
}


// Starting point of an active push (called once checkpoints are loaded.)
- (void) sendChangesSince: (uint64_t)since {
    _changeListsInFlight++;
    [self updateState];
    if (_pushing && _pushProgress.indeterminate) {
        // Starting:
        _pushProgress.completedUnitCount = 0;
        _pushProgress.totalUnitCount = 0;
    }

    [self onDatabaseQueue: ^{
        // Query the database for the next batch of changes:
        CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
        CBLQueryEnumerator* e = [self pendingDocumentsSince: since limit: _changesBatchSize];
        if (!e) {
            [self onSyncQueue: ^{
                --_changeListsInFlight;
                [self updateState];
            }];
            return;
        }
        uint64_t lastSequence = 0;
        NSMutableArray* changes = [NSMutableArray new];
        for (CBLQueryRow* row in e) {
            lastSequence = row.sequenceNumber;
            [changes addObject: encodeChange(lastSequence, row.documentID,
                                             row.value[@"rev"], [row.value[@"deleted"] boolValue])];
        }
        time = CFAbsoluteTimeGetCurrent() - time;
        LogTo(Sync, @"Sending %lu changes since sequence #%lld (took %.4f sec)",
              (unsigned long)changes.count, since, time);

        if (changes.count == 0 && _pushContinuousChanges) {
            // Now go into continuous-push mode, waiting for db changes:
            LogTo(Sync, @"Now observing database change notifications");
            [[NSNotificationCenter defaultCenter] addObserver: self
                                                     selector: @selector(_dbChanged:)
                                                         name: kCBLDatabaseChangeNotification
                                                       object: _db];
        }

        [self onSyncQueue: ^{
            BOOL delayNext = (_changeListsInFlight >= kMaxChangeMessagesInFlight);
            [self sendChanges: changes
                       onSent: ^{
                           if (changes.count > 0 && !delayNext)
                               [self sendChangesSince: lastSequence];
                       }
                   onComplete: ^{
                       --_changeListsInFlight;
                       if (changes.count > 0 && delayNext)
                           [self sendChangesSince: lastSequence];
                       else if (_changeListsInFlight == 0)
                           [self updateState];
                   }
             ];
        }];
    }];
}


- (void) sendChanges: (NSArray*)changes
              onSent: (void(^)())onSent
          onComplete: (void(^)())onComplete
{
    BLIPRequest* request = [_connection request];
    request.profile = @"changes";
    request.bodyJSON = changes;
    request.urgent = kChangeMessagesAreUrgent;
    if (changes.count == 0) {
        request.noReply = YES;
        [request send];
        if (onComplete)
            onComplete();
    } else {
        request.onSent = onSent;
        [request send].onComplete = ^(BLIPResponse* response) {
            if ([self gotError: response])
                return;
            NSUInteger maxHistory = MAX(0, [response[@"maxHistory"] integerValue]);
            // The response contains an array that, for each change in the outgoing message,
            // contains either the list of known ancestors, or a null/false/0 if not interested.
            NSArray* responseArray = $castIf(NSArray, response.bodyJSON);
            if (responseArray.count > 0) {
                [self onDatabaseQueue: ^{
                    if (_pushing) {
                        // Update the totalUnitCount before we start sending docs
                        NSUInteger numToSend = 0;
                        for (NSArray* ancestors in responseArray) {
                            if ([ancestors isKindOfClass: [NSArray class]])
                                ++numToSend;
                        }
                        _pushProgress.totalUnitCount += numToSend;
                    }
                    NSUInteger index = 0;
                    for (NSArray* ancestors in responseArray) {
                        if ([ancestors isKindOfClass: [NSArray class]]) {
                            @autoreleasepool {
                                NSArray* change = changes[index];
                                [self sendDoc: change[1]
                                        revID: change[2]
                                     sequence: change[0]
                               knownAncestors: ancestors
                                   maxHistory: maxHistory
                                           to: _connection];
                            }
                        }
                        ++index;
                    }
                }];
            }
            // Find the sequences the peer _didn't_ ask for and mark them as synced:
            NSUInteger index = 0;
            for (NSArray* change in changes) {
                if (index >= responseArray.count
                        || [responseArray[index] isKindOfClass: [NSArray class]]) {
                    [self noteLocalSequenceIDPushed: change[0]];
                }
                index++;
            }
            if (onComplete)
                onComplete();
        };
    }
}


// Called on the database queue
- (void) _dbChanged: (NSNotification*)n {
    __typeof(_pushFilter) pushFilter = _pushFilter;
    NSMutableArray* changes = [NSMutableArray new];
    for (CBLDatabaseChange* change in (n.userInfo)[@"changes"]) {
        if ([change.source isEqual: _peerURL])
            continue;  // ignore echoes of changes rcvd from this peer
        CBL_Revision* rev = change.addedRevision;
        if (!rev)
            continue;  // ignore purges
        if (pushFilter && ![_db runFilter: pushFilter params: _pushFilterParams onRevision: rev])
            continue;  // filter block says ignore it
        [changes addObject: encodeChange(change.sequenceNumber, change.documentID,
                                         change.revisionID, change.isDeletion)];
    }
    if (changes.count > 0) {
        [self onSyncQueue: ^{
            if (_connection) {
                LogTo(Sync, @"Notified that %lu documents changed", (unsigned long)changes.count);
                [self sendChanges: changes onSent: nil onComplete: nil];
            }
        }];
    }
}


static NSArray* encodeChange(uint64_t sequence, NSString* docID, NSString* revID, BOOL deleted) {
    return [NSArray arrayWithObjects: @(sequence), docID, revID, (deleted ?@YES :nil), nil];
}


#pragma mark - DOCUMENTS/REVISIONS/ATTACHMENTS


// Must be called on database queue!
- (void) sendDoc: (NSString*)docID
           revID: (NSString*)revID
        sequence: (id)sequenceID
  knownAncestors: (NSArray*)knownIDs
      maxHistory: (NSUInteger)maxHistory
              to: (BLIPConnection*)socket
{
    LogVerbose(Sync, @"Sending revision {%@, %@}", docID, revID);
    CBLSavedRevision* rev = [_db[docID] revisionWithID: revID];
    NSData* revJSON = rev.JSONData;
    NSError* error;
    NSMutableString* historyStr = nil;
    NSArray* history = [rev getRevisionHistoryBackToRevisionIDs: knownIDs error: &error];
    NSUInteger historyCount = history.count;
    if (historyCount > 1) {
        // Concatenate ancestor rev IDs in _reverse_ order:
        historyStr = [NSMutableString new];
        NSInteger iMin = 0;
        if (maxHistory > 0)
            iMin = MAX(iMin, (NSInteger)historyCount - 1 - (NSInteger)maxHistory);
        for (NSInteger i = historyCount - 2; i >= iMin; i--) {
            [historyStr appendString: [history[i] revisionID]];
            if (i > iMin)
                [historyStr appendString: @","];
        }
    }
    [self onSyncQueue: ^{
        BLIPRequest* update = socket.request;
        update.profile = @"rev";
        update[@"sequence"] = [sequenceID description];
        update[@"history"] = historyStr;
        update.body = revJSON;
        update.compressed = (revJSON.length >= kMinLengthToCompress);

        if (_pushing) {
            [update send].onComplete = ^(BLIPResponse* response) {
                if ([self gotError: response])
                    return;
                LogVerbose(Sync, @"    ...sent revision {%@, %@}", docID, revID);
                [self noteLocalSequenceIDPushed: sequenceID];
                _pushProgress.completedUnitCount++;
            };
        } else {
            update.noReply = YES;
            [update send];
        }
    }];
}


- (void) handleGetAttachment: (BLIPRequest*)request {
    if (![self accessCheckForRequest: request])
        return;
    
    NSString* digest = request[@"digest"];
    [request deferResponse];
    [self onDatabaseQueue: ^{
        uint64_t length = [_db lengthOfAttachmentWithDigest: digest];
        NSInputStream* stream = [_db contentStreamOfAttachmentWithDigest: digest];
        LogVerbose(Sync, @"    Sending attachment %@ (%llukb)", digest, length/1024);
        [self onSyncQueue: ^{
            if (stream) {
                _pushProgress.totalUnitCount += length/1024;
                [_pushProgress becomeCurrentWithPendingUnitCount: length/1024];
                NSProgress* attProgress = [self addAttachmentProgressWithName: digest
                                                                       length: length
                                                                      pulling: NO];
                [_pushProgress resignCurrent];

                BLIPResponse* response = [request response];
                response.compressed = $equal(request[@"compress"], @"true");
                [response addStreamToBody: stream];
                __block CFAbsoluteTime lastProgressUpdateTime = CFAbsoluteTimeGetCurrent();
                response.onDataSent = ^(BLIPMessage* response, uint64_t totalBytes) {
                    if (ItsBeenAtLeast(kProgressUpdateInterval, &lastProgressUpdateTime))
                        attProgress.completedUnitCount = totalBytes;
                };
                __weak BLIPResponse* wresponse = response;
                response.onComplete = ^(BLIPResponse* response) {
                    [self removeAttachmentProgress: attProgress pulling: NO];
                    if (![self gotError: wresponse])
                        LogVerbose(Sync, @"    ...sent attachment %@", digest);
                };
                [response send];
            } else {
                [request respondWithError: [NSError errorWithDomain: @"HTTP" code: 404
                                                           userInfo: nil]];
            }
        }];
    }];
}


- (void) handleProveAttachment: (BLIPRequest*)request {
    if (![self accessCheckForRequest: request])
        return;
    
    NSString* digest = request[@"digest"];
    NSData* nonce = request.body;
    if (!digest || nonce.length == 0 || nonce.length > 255)
        return [request respondWithErrorCode: 400 message: @"Invalid nonce or digest"];
    NSInputStream* stream = [_db contentStreamOfAttachmentWithDigest: digest];
    if (!stream)
        return [request respondWithErrorCode: 404 message: @"Attachment digest unknown"];

    // Work the proof by digesting the length of the nonce + the nonce + the attachment data:
    CC_SHA1_CTX sha;
    CC_SHA1_Init(&sha);
    uint8_t nonceLen = (nonce.length & 0xFF);
    CC_SHA1_Update(&sha, &nonceLen, 1);
    CC_SHA1_Update(&sha, nonce.bytes, (CC_LONG)nonce.length);
    NSInteger len;
    [stream open];
    do {
        uint8_t buf[32768];
        len = [stream read: buf maxLength: sizeof(buf)];
        if (len > 0)
            CC_SHA1_Update(&sha, buf, (CC_LONG)len);
    } while (len > 0);
    if (len < 0) {
        Warn(@"Unable to send attachment proof; error reading body: %@", stream.streamError);
        [stream close];
        return [request respondWithErrorCode: 500 message: @"Couldn't read attachment data"];
    }
    [stream close];
    uint8_t proofDigest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(proofDigest, &sha);

    NSData* data = [NSData dataWithBytes: proofDigest length: sizeof(proofDigest)];
    NSString* proof = [@"sha1-" stringByAppendingString: [data base64EncodedStringWithOptions:0]];
    LogVerbose(Sync, @"    Returning proof %@ for nonce %@, attachment %@", proof, nonce, digest);
    [request respondWithString: proof];
}


#pragma mark - UTILITIES:


static BOOL ItsBeenAtLeast(NSTimeInterval minInterval, CFAbsoluteTime* time) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - *time < minInterval)
        return NO;
    *time = now;
    return YES;
}


@end
