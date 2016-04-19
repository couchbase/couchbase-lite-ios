//
//  CBLSyncConnection+Checkpoints.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/27/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "CBLSyncConnection_Internal.h"
#import "CBL_Body.h"


@implementation CBLSyncConnection (Checkpoints)


// Unless specified, all the methods below must be called on the _syncQueue.


/** This is the _local document ID stored on the remote server to keep track of state. */
- (NSString*) effectiveRemoteCheckpointDocID {
    if (self.remoteCheckpointDocID)
        return self.remoteCheckpointDocID;
    // Simplistic default implementation:
    NSArray* spec = @[_db.privateUUID, _peerURL.absoluteString, @(_pushing)];
    NSData* data = [NSJSONSerialization dataWithJSONObject: spec options: 0  error: NULL];
    return CBLHexSHA1Digest(data);
}


- (void) getCheckpoint {
    Assert(_pushing || _pulling);
    LogVerbose(Sync, @"Requesting checkpoint...");
    BLIPRequest* request = [_connection request];
    request.profile = @"getCheckpoint";
    NSString* checkpointID = self.effectiveRemoteCheckpointDocID;
    request[@"client"] = checkpointID;
    [request send].onComplete = ^(BLIPResponse* response) {
        // Got response, now compare received & locally-stored checkpoints:
        NSDictionary* checkpoint = nil;
        NSError* error = response.error;
        if (error) {
            if (![error.domain isEqualToString: @"HTTP"] || error.code != 404) {
                [self gotError: response]; // fatal
                return;
            }
            LogVerbose(Sync, @"No checkpoint on server");
        } else {
            LogVerbose(Sync, @"Received checkpoint: %@", response.body.my_UTF8ToString);
            checkpoint = $castIf(NSDictionary, response.bodyJSON);
        }
        id lastSequenceID = checkpoint[@"lastSequence"];
        __block NSString* savedSequenceStr;
        dispatch_sync(_dbQueue, ^{
            savedSequenceStr = [_db lastSequenceWithCheckpointID: checkpointID];
        });
        if (_pushing) {
            uint64_t lastSequence = $castIf(NSNumber, lastSequenceID).unsignedLongLongValue;
            uint64_t savedSequence = savedSequenceStr.longLongValue;
            if (lastSequence != savedSequence) {
                LogTo(Sync, @"lastSequence mismatch: I had %llu, remote had %llu",
                      savedSequence, lastSequence);
                lastSequence = 0;
            }
            _localCheckpointSequence = lastSequence;
        } else {
            NSData* json = [savedSequenceStr dataUsingEncoding: NSUTF8StringEncoding];
            id savedSequence = nil;
            if (json) {
                savedSequence = [CBLJSON JSONObjectWithData: json
                                                    options: CBLJSONReadingAllowFragments
                                                      error: NULL];
            }
            if (!$equal(lastSequenceID, savedSequence)) {
                LogTo(Sync, @"lastSequence mismatch: I had %@, remote had %@",
                      savedSequence, lastSequenceID);
                lastSequenceID = nil;
            }
            _remoteCheckpointSequence = lastSequenceID;
        }
        _remoteCheckpointRevID = response[@"rev"];

        // Now can start the actual push or pull:
        if (_pulling) {
            [self requestChangesSince: _remoteCheckpointSequence
                          inBatchesOf: kDefaultChangeBatchSize
                           continuous: _pullContinuousChanges];
            [self updateState: kSyncActive];
        }
        if (_pushing) {
            [self sendChangesSince: _localCheckpointSequence];
        }
    };
}


- (BOOL) updateCheckpoint {
    Assert(_pushing || _pulling);
    if (!_lastSequenceChanged)
        return NO;
    if (_savingCheckpoint) {
        // If a save is already in progress, don't do anything. (The completion block will trigger
        // another save after the first one finishes.)
        _overdueForSave = YES;
        return YES;
    }
    _lastSequenceChanged = _overdueForSave = NO;
    _savingCheckpoint = YES;

    id lastSequence = _pushing ? @(_localCheckpointSequence) : _remoteCheckpointSequence;
    NSString* checkpointID = self.remoteCheckpointDocID;
    BLIPRequest* request = [_connection request];
    request.profile = @"setCheckpoint";
    request[@"client"] = checkpointID;
    request[@"rev"] = _remoteCheckpointRevID;
    request.bodyJSON = $dict({@"lastSequence", lastSequence});
    LogTo(Sync, @"Saving checkpoint: %@", request.body.my_UTF8ToString);
    [request send].onComplete = ^(BLIPResponse* response) {
        _savingCheckpoint = NO;
        if ([self gotError: response])
            return; // connection will close
        _remoteCheckpointRevID = response[@"rev"];
        dispatch_sync(_dbQueue, ^{
            [_db setLastSequence: [lastSequence description]
                withCheckpointID: checkpointID];
        });
        LogTo(Sync, @"Saved remote checkpoint '%@'", lastSequence);
        if (_overdueForSave && _lastSequenceChanged)
            [self updateCheckpoint];      // start a save that was waiting on me
        else if (_closeAfterSave)
            [_connection close];
    };
    return YES;
}


- (void) noteLastSequenceChanged {
    if ((_pushing || _pulling) && !_lastSequenceChanged) {
        _lastSequenceChanged = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5*NSEC_PER_SEC)), _syncQueue, ^{
            [self updateCheckpoint];
        });
    }
}


- (void) noteLocalSequenceIDPushed: (id)sequenceID {
    uint64_t seqNum = [sequenceID longLongValue];
    if (seqNum > _localCheckpointSequence) {
        //FIX: Shouldn't update this till all intermediate sequences are delivered
        _localCheckpointSequence = seqNum;
        [self noteLastSequenceChanged];
    }
}


static NSString* localDocIDForCheckpointRequest(BLIPRequest* request) {
    NSString* clientID = request[@"client"];
    if (!clientID) {
        [request respondWithErrorCode: 400 message: @"Missing 'client' property"];
        return nil;
    }
    return [@"remotecheckpoint/" stringByAppendingString: clientID];
}


- (void) handleGetCheckpoint: (BLIPRequest*)request {
    NSString* docID = localDocIDForCheckpointRequest(request);
    if (!docID) {
        [request respondWithErrorCode: 400 message: @"Bad Request"];
        return;
    }
    if (![self accessCheckForRequest: request])
        return;
    [request deferResponse];
    
    [self onDatabaseQueue:^{
        NSDictionary* checkpoint = [_db existingLocalDocumentWithID: docID];
        NSString* revID = nil;
        if (checkpoint) {
            NSMutableDictionary* mcheck = [checkpoint mutableCopy];
            revID = mcheck[@"_rev"];
            [mcheck removeObjectForKey: @"_rev"];
            [mcheck removeObjectForKey: @"_id"];
            checkpoint = mcheck;
        } else {
            checkpoint = @{};
        }
        [self onSyncQueue:^{
            BLIPResponse* response = request.response;
            response[@"rev"] = revID;
            response.bodyJSON = checkpoint;
            [response send];
        }];
    }];
}


- (void) handleSetCheckpoint: (BLIPRequest*)request {
    NSString* docID = localDocIDForCheckpointRequest(request);
    if (!docID)
        return;
    NSMutableDictionary* checkpoint = [$castIf(NSDictionary, request.bodyJSON) mutableCopy];
    if (!docID || !checkpoint) {
        [request respondWithErrorCode: 400 message: @"Bad Request"];
        return;
    }
    if (![self accessCheckForRequest: request])
        return;
    NSString* revID = request[@"rev"];
    if (revID)
        checkpoint.cbl_revStr = revID;
    [request deferResponse];

    [self onDatabaseQueue:^{
        NSError* error;
        BOOL ok = [_db putLocalDocument: checkpoint withID: docID error: &error];
        NSString* newRevID = nil;
        // Workaround for -putLocalDocument: not returning the new revID:
        if (ok)
            newRevID = [_db existingLocalDocumentWithID: docID][@"_rev"];

        [self onSyncQueue:^{
            if (ok) {
                BLIPResponse* response = request.response;
                response[@"rev"] = newRevID;
                [response send];
            } else {
                [request respondWithError: error];
            }
        }];
    }];
}


@end
