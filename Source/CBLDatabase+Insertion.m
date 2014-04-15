//
//  CBLDatabase+Insertion.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/27/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+Attachments.h"
#import "CBLDatabase.h"
#import "CouchbaseLitePrivate.h"
#import "CBLDocument.h"
#import "CBL_Revision.h"
#import "CBLCanonicalJSON.h"
#import "CBL_Attachment.h"
#import "CBLDatabaseChange.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "Test.h"
#import "ExceptionUtils.h"

#import <CBForest/CBForest.h>

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"

#ifdef GNUSTEP
#import <openssl/sha.h>
#else
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>
#endif


@interface CBLValidationContext : NSObject <CBLValidationContext>
{
    @private
    CBLDatabase* _db;
    CBL_Revision* _currentRevision, *_newRevision;
    int _errorType;
    NSString* _errorMessage;
    NSArray* _changedKeys;
}
- (instancetype) initWithDatabase: (CBLDatabase*)db
                         revision: (CBL_Revision*)currentRevision
                      newRevision: (CBL_Revision*)newRevision;
@property (readonly) CBLSavedRevision* currentRevision;
@property (readonly) NSString* rejectionMessage;
@end



@implementation CBLDatabase (Insertion)


#pragma mark - DOCUMENT & REV IDS:


+ (BOOL) isValidDocumentID: (NSString*)str {
    // http://wiki.apache.org/couchdb/HTTP_Document_API#Documents
    if (str.length == 0)
        return NO;
    if ([str characterAtIndex: 0] == '_')
        return [str hasPrefix: @"_design/"];
    return YES;
    // "_local/*" is not a valid document ID. Local docs have their own API and shouldn't get here.
}


/** Generates a new document ID at random. */
+ (NSString*) generateDocumentID {
    return CBLCreateUUID();
}


/** Given an existing revision ID, generates an ID for the next revision.
    Returns nil if prevID is invalid. */
- (NSString*) generateIDForRevision: (CBL_Revision*)rev
                           withJSON: (NSData*)json
                        attachments: (NSDictionary*)attachments
                             prevID: (NSString*) prevID
{
    // Revision IDs have a generation count, a hyphen, and a hex digest.
    unsigned generation = 0;
    if (prevID) {
        generation = [CBL_Revision generationFromRevID: prevID];
        if (generation == 0)
            return nil;
    }
    
    // Generate a digest for this revision based on the previous revision ID, document JSON,
    // and attachment digests. This doesn't need to be secure; we just need to ensure that this
    // code consistently generates the same ID given equivalent revisions.
    MD5_CTX ctx;
    unsigned char digestBytes[MD5_DIGEST_LENGTH];
    MD5_Init(&ctx);
    
    NSData* prevIDUTF8 = [prevID dataUsingEncoding: NSUTF8StringEncoding];
    NSUInteger length = prevIDUTF8.length;
    if (length > 0xFF)
        return nil;
    uint8_t lengthByte = length & 0xFF;
    MD5_Update(&ctx, &lengthByte, 1);       // prefix with length byte
    if (length > 0)
        MD5_Update(&ctx, prevIDUTF8.bytes, length);
    
    uint8_t deletedByte = rev.deleted != NO;
    MD5_Update(&ctx, &deletedByte, 1);
    
    for (NSString* attName in [attachments.allKeys sortedArrayUsingSelector: @selector(compare:)]) {
        CBL_Attachment* attachment = attachments[attName];
        MD5_Update(&ctx, &attachment->blobKey, sizeof(attachment->blobKey));
    }
    
    MD5_Update(&ctx, json.bytes, json.length);
    MD5_Final(digestBytes, &ctx);

    char hex[11 + 2*MD5_DIGEST_LENGTH + 1];
    char *dst = hex + sprintf(hex, "%u-", generation+1);
    for( size_t i=0; i<MD5_DIGEST_LENGTH; i+=1 )
        dst += sprintf(dst,"%02x", digestBytes[i]); // important: generates lowercase!
    return [[NSString alloc] initWithBytes: hex
                                    length: dst - hex
                                  encoding: NSASCIIStringEncoding];
}


/** Adds a new document ID to the 'docs' table. */
- (SInt64) insertDocumentID: (NSString*)docID {
    Assert([CBLDatabase isValidDocumentID: docID]);  // this should be caught before I get here
    if (![_fmdb executeUpdate: @"INSERT INTO docs (docid) VALUES (?)", docID])
        return -1;
    SInt64 row = _fmdb.lastInsertRowId;
    Assert(![_docIDs objectForKey: docID]);
    [_docIDs setObject: @(row) forKey: docID];
    return row;
}


/** Extracts the history of revision IDs (in reverse chronological order) from the _revisions key */
+ (NSArray*) parseCouchDBRevisionHistory: (NSDictionary*)docProperties {
    NSDictionary* revisions = $castIf(NSDictionary,
                                      docProperties[@"_revisions"]);
    if (!revisions)
        return nil;
    // Extract the history, expanding the numeric prefixes:
    NSArray* revIDs = $castIf(NSArray, revisions[@"ids"]);
    __block int start = [$castIf(NSNumber, revisions[@"start"]) intValue];
    if (start)
        revIDs = [revIDs my_map: ^(id revID) {return $sprintf(@"%d-%@", start--, revID);}];
    return revIDs;
}


#pragma mark - INSERTION:


/** Returns the JSON to be stored into the 'json' column for a given CBL_Revision.
    This has all the special keys like "_id" stripped out. */
- (NSData*) encodeDocumentJSON: (CBL_Revision*)rev {
    static NSSet* sSpecialKeysToRemove, *sSpecialKeysToLeave;
    if (!sSpecialKeysToRemove) {
        sSpecialKeysToRemove = [[NSSet alloc] initWithObjects: @"_id", @"_rev", @"_attachments",
            @"_deleted", @"_revisions", @"_revs_info", @"_conflicts", @"_deleted_conflicts",
            @"_local_seq", nil];
        sSpecialKeysToLeave = [[NSSet alloc] initWithObjects:
            @"_removed",
            @"_replication_id", @"_replication_state", @"_replication_state_time", nil];
    }

    NSDictionary* origProps = rev.properties;
    if (!origProps)
        return nil;
    
    // Don't leave in any "_"-prefixed keys except for the ones in sSpecialKeysToLeave.
    // Keys in sSpecialKeysToRemove (_id, _rev, ...) are left out, any others trigger an error.
    NSMutableDictionary* properties = [[NSMutableDictionary alloc] initWithCapacity: origProps.count];
    for (NSString* key in origProps) {
        if (![key hasPrefix: @"_"]  || [sSpecialKeysToLeave member: key]) {
            properties[key] = origProps[key];
        } else if (![sSpecialKeysToRemove member: key]) {
            Log(@"CBLDatabase: Invalid top-level key '%@' in document to be inserted", key);
            return nil;
        }
    }
    
    // Create canonical JSON -- this is important, because the JSON data returned here will be used
    // to create the new revision ID, and we need to guarantee that equivalent revision bodies
    // result in equal revision IDs.
    NSData* json = [CBLCanonicalJSON canonicalData: properties];
    return json;
}


- (CBL_Revision*) winnerWithDocID: (SInt64)docNumericID
                      oldWinner: (NSString*)oldWinningRevID
                     oldDeleted: (BOOL)oldWinnerWasDeletion
                         newRev: (CBL_Revision*)newRev
{
    if (!oldWinningRevID)
        return newRev;
    NSString* newRevID = newRev.revID;
    if (!newRev.deleted) {
        if (oldWinnerWasDeletion || CBLCompareRevIDs(newRevID, oldWinningRevID) > 0)
            return newRev;   // this is now the winning live revision
    } else if (oldWinnerWasDeletion) {
        if (CBLCompareRevIDs(newRevID, oldWinningRevID) > 0)
            return newRev;  // doc still deleted, but this beats previous deletion rev
    } else {
        // Doc was alive. How does this deletion affect the winning rev ID?
        BOOL deleted;
        NSString* winningRevID = [self winningRevIDOfDocNumericID: docNumericID
                                                        isDeleted: &deleted
                                                       isConflict: NULL];
        if (!$equal(winningRevID, oldWinningRevID)) {
            if ($equal(winningRevID, newRev.revID))
                return newRev;
            else {
                CBL_Revision* winningRev = [[CBL_Revision alloc] initWithDocID: newRev.docID
                                                                      revID: winningRevID
                                                                    deleted: NO];
                return winningRev;
            }
        }
    }
    return nil; // no change
}


- (void) notifyChange: (CBL_Revision*)inRev doc: (CBForestVersions*)doc source: (NSURL*)source {
    CBL_Revision* winningRev = inRev;
    if (!$equal(doc.revID, inRev.revID))
        winningRev = [[CBL_Revision alloc] initWithDocID: doc.docID revID: doc.revID
                                                 deleted: (doc.flags & kCBForestDocDeleted) != 0];
    BOOL inConflict = (doc.flags & kCBForestDocConflicted) != 0;
    [self notifyChange: [[CBLDatabaseChange alloc] initWithAddedRevision: inRev
                                                         winningRevision: winningRev
                                                              inConflict: inConflict
                                                                  source: source]];
}


- (CBL_Revision*) putRevision: (CBL_Revision*)oldRev
               prevRevisionID: (NSString*)inputPrevRevID
                allowConflict: (BOOL)allowConflict
                       status: (CBLStatus*)outStatus
{
    LogTo(CBLDatabase, @"PUT rev=%@, prevRevID=%@, allowConflict=%d", oldRev,
          inputPrevRevID, allowConflict);
    Assert(outStatus);
    NSString* inputDocID = oldRev.docID;
    BOOL deleted = oldRev.deleted;
    if (!oldRev || (inputPrevRevID && !inputDocID) || (deleted && !inputDocID)
                || (inputDocID && ![CBLDatabase isValidDocumentID: inputDocID])) {
        *outStatus = kCBLStatusBadID;
        return nil;
    }
    NSString* docID = inputDocID ?: [[self class] generateDocumentID];
    NSString* prevRevID = inputPrevRevID;

    // Get the ForestDB document:
    NSError* error;
    CBForestVersions* doc = (CBForestVersions*) [_forest documentWithID: docID
                                                                options: kCBForestDBCreateDoc
                                                                  error: &error];
    if (!doc) {
        *outStatus = kCBLStatusDBError;
        return nil;
    }
    doc.maxDepth = (unsigned)self.maxRevTreeDepth;

    CBForestRevisionFlags prevRevFlags = [doc flagsOfRevision: prevRevID];
    if (prevRevID) {
        // Updating an existing revision; make sure it exists and is a leaf:
        CBForestRevisionFlags revFlags = [doc flagsOfRevision: prevRevID];
        if (!(revFlags & kCBForestRevisionKnown)) {
            *outStatus = kCBLStatusNotFound;
            return nil;
        } else if (!(revFlags & kCBForestRevisionLeaf)) {
            *outStatus = kCBLStatusConflict;
            return nil;
        }
    } else {
        // No parent revision given:
        if (deleted) {
            // Didn't specify a revision to delete: NotFound or a Conflict, depending
            *outStatus = doc.exists ? kCBLStatusConflict : kCBLStatusNotFound;
            return nil;
        }
        // If doc exists, it must be in a deleted state:
        if ((prevRevFlags & kCBForestRevisionKnown) && !(prevRevFlags & kCBForestRevisionDeleted)) {
            *outStatus = kCBLStatusConflict;
            return nil;
        }
        prevRevID = doc.revID;
    }

    // Run any validation blocks:
    if ([self.shared hasValuesOfType: @"validation" inDatabaseNamed: _name]) {
        CBL_Revision* fakeNewRev = [oldRev mutableCopyWithDocID: oldRev.docID revID: nil];
        CBL_Revision* prevRev = nil;
        if (prevRevID) {
            prevRev = [[CBL_Revision alloc] initWithDocID: docID revID: prevRevID
                                                  deleted: NO];
        }
        *outStatus = [self validateRevision: fakeNewRev
                           previousRevision: prevRev
                                parentRevID: prevRevID];
        if (CBLStatusIsError(*outStatus))
            return nil;
    }


    NSDictionary* attachments = [self attachmentsFromRevision: oldRev status: outStatus];
    if (!attachments)
        return nil;

    // Bump the revID and update the JSON:
    NSData* json = nil;
    if (oldRev.properties) {
        json = [self encodeDocumentJSON: oldRev];
        if (!json) {
            *outStatus = kCBLStatusBadJSON;
            return nil;
        }
    }
    NSString* newRevID = [self generateIDForRevision: oldRev
                                            withJSON: json
                                         attachments: attachments
                                              prevID: prevRevID];
    if (!newRevID) {
        *outStatus = kCBLStatusBadID;  // invalid previous revID (no numeric prefix)
        return nil;
    }
    Assert(docID);
    CBL_MutableRevision* newRev = [oldRev mutableCopyWithDocID: docID revID: newRevID];
    [CBLDatabase stubOutAttachments: attachments inRevision: newRev];

    // Add it!!
    if (![doc addRevision: json
                 deletion: oldRev.deleted
                   withID: newRevID
                 parentID: prevRevID
            allowConflict: allowConflict]) {
        *outStatus = kCBLStatusDBError;
        return nil;
    }
    if (![doc save: &error]) {
        *outStatus = kCBLStatusDBError;
        return nil;
    }
    newRev.sequence = doc.sequence;

    /* FIX: What's the replacement for this?
    // Store any attachments:
    *outStatus = [self processAttachments: attachments
                              forRevision: newRev
                       withParentSequence: parentSequence];
    if (CBLStatusIsError(*outStatus))
        return nil;
     */

    LogTo(CBLDatabase, @"--> created %@", newRev);

    // Epilogue: A change notification is sent:
    [self notifyChange: newRev doc: doc source: nil];
    *outStatus = deleted ?kCBLStatusOK : kCBLStatusCreated;
    return newRev;
}


/** Add an existing revision of a document (probably being pulled) plus its ancestors. */
- (CBLStatus) forceInsert: (CBL_Revision*)inRev
          revisionHistory: (NSArray*)history  // in *reverse* order, starting with rev's revID
                   source: (NSURL*)source
{
    CBL_MutableRevision* rev = inRev.mutableCopy;
    rev.sequence = 0;
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    if (![CBLDatabase isValidDocumentID: docID] || !revID)
        return kCBLStatusBadID;
    
    NSUInteger historyCount = history.count;
    if (historyCount == 0) {
        history = @[revID];
        historyCount = 1;
    } else if (!$equal(history[0], revID)) {
        return kCBLStatusBadID;
    }

    // First get the CBForest doc:
    NSError* error;
    CBForestVersions* doc = (CBForestVersions*)[_forest documentWithID: docID
                                                               options: kCBForestDBCreateDoc
                                                                 error: &error];
    if (!doc)
        return kCBLStatusDBError;
    doc.maxDepth = (unsigned)self.maxRevTreeDepth;

    // Add the revision & ancestry to the doc:
    NSData* json = [self encodeDocumentJSON: inRev];
    if (!json)
        return kCBLStatusBadJSON;
    NSInteger common = [doc addRevision: json
                               deletion: inRev.deleted
                                history: history];
    if (common < 0)
        return kCBLStatusDBError;   //FIX: Get a more detailed status
    if (common == 0)
        return kCBLStatusOK;      // No-op: No new revisions were inserted.

    // Validate against the common ancestor:
    if (([self.shared hasValuesOfType: @"validation" inDatabaseNamed: _name])) {
        NSString* commonAncestor = history[common];
        CBForestRevisionFlags flags = [doc flagsOfRevision: commonAncestor];
        BOOL deleted = (flags & kCBForestRevisionDeleted) != 0;
        CBL_Revision* prev = [[CBL_Revision alloc] initWithDocID: docID
                                                           revID: commonAncestor
                                                         deleted: deleted];
        NSString* parentRevID = (history.count > 1) ? history[1] : nil;
        CBLStatus status = [self validateRevision: rev
                                 previousRevision: prev
                                      parentRevID: parentRevID];
        if (CBLStatusIsError(status))
            return status;
    }

    // Save updated doc back to the database:
    if (![doc save: &error])
        return kCBLStatusDBError;
    [self notifyChange: inRev doc: doc source: source];
    return kCBLStatusCreated;
}


#if DEBUG
// Grotesque hack, for some attachment unit-tests only!
- (CBLStatus) _setNoAttachments: (BOOL)noAttachments forSequence: (SequenceNumber)sequence {
    if (![_fmdb executeUpdate: @"UPDATE revs SET no_attachments=? WHERE sequence=?",
                               @(noAttachments), @(sequence)])
        return self.lastDbError;
    return kCBLStatusOK;
}
#endif


#pragma mark - PURGING / COMPACTING:


- (CBLStatus) compact {
    // Can't delete any rows because that would lose revision tree history.
    // But we can remove the JSON of non-current revisions, which is most of the space.
    Log(@"CBLDatabase: Deleting JSON of old revisions...");
    if (![_fmdb executeUpdate: @"UPDATE revs SET json=null WHERE current=0"])
        return self.lastDbError;

    Log(@"Deleting old attachments...");
    CBLStatus status = [self garbageCollectAttachments];

    Log(@"Flushing SQLite WAL...");
    if (![_fmdb executeUpdate: @"PRAGMA wal_checkpoint(RESTART)"])
        return self.lastDbError;

    Log(@"Vacuuming SQLite database...");
    if (![_fmdb executeUpdate: @"VACUUM"])
        return self.lastDbError;

    Log(@"Closing and re-opening database...");
    [_fmdb close];
    if (![self openFMDB: nil])
        return self.lastDbError;

    Log(@"...Finished database compaction.");
    return status;
}


- (CBLStatus) purgeRevisions: (NSDictionary*)docsToRevs
                     result: (NSDictionary**)outResult
{
    // <http://wiki.apache.org/couchdb/Purge_Documents>
    NSMutableDictionary* result = $mdict();
    if (outResult)
        *outResult = result;
    if (docsToRevs.count == 0)
        return kCBLStatusOK;
    return [self _inTransaction: ^CBLStatus {
        for (NSString* docID in docsToRevs) {
            SInt64 docNumericID = [self getDocNumericID: docID];
            if (!docNumericID) {
                continue;  // no such document; skip it
            }
            NSArray* revsPurged;
            NSArray* revIDs = $castIf(NSArray, docsToRevs[docID]);
            if (!revIDs) {
                return kCBLStatusBadParam;
            } else if (revIDs.count == 0) {
                revsPurged = @[];
            } else if ([revIDs containsObject: @"*"]) {
                // Delete all revisions if magic "*" revision ID is given:
                if (![_fmdb executeUpdate: @"DELETE FROM revs WHERE doc_id=?",
                                           @(docNumericID)]) {
                    return self.lastDbError;
                }
                revsPurged = @[@"*"];
                
            } else {
                // Iterate over all the revisions of the doc, in reverse sequence order.
                // Keep track of all the sequences to delete, i.e. the given revs and ancestors,
                // but not any non-given leaf revs or their ancestors.
                CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT revid, sequence, parent FROM revs "
                                                       "WHERE doc_id=? ORDER BY sequence DESC",
                                  @(docNumericID)];
                if (!r)
                    return self.lastDbError;
                NSMutableSet* seqsToPurge = [NSMutableSet set];
                NSMutableSet* seqsToKeep = [NSMutableSet set];
                NSMutableSet* revsToPurge = [NSMutableSet set];
                while ([r next]) {
                    NSString* revID = [r stringForColumnIndex: 0];
                    id sequence = @([r longLongIntForColumnIndex: 1]);
                    id parent = @([r longLongIntForColumnIndex: 2]);
                    if (([seqsToPurge containsObject: sequence] || [revIDs containsObject:revID]) &&
                            ![seqsToKeep containsObject: sequence]) {
                        // Purge it and maybe its parent:
                        [seqsToPurge addObject: sequence];
                        [revsToPurge addObject: revID];
                        if ([parent longLongValue] > 0)
                            [seqsToPurge addObject: parent];
                    } else {
                        // Keep it and its parent:
                        [seqsToPurge removeObject: sequence];
                        [revsToPurge removeObject: revID];
                        [seqsToKeep addObject: parent];
                    }
                }
                [r close];
                [seqsToPurge minusSet: seqsToKeep];

                LogTo(CBLDatabase, @"Purging doc '%@' revs (%@); asked for (%@)",
                      docID, [revsToPurge.allObjects componentsJoinedByString: @", "],
                      [revIDs componentsJoinedByString: @", "]);

                if (seqsToPurge.count) {
                    // Now delete the sequences to be purged.
                    NSString* sql = $sprintf(@"DELETE FROM revs WHERE sequence in (%@)",
                                           [seqsToPurge.allObjects componentsJoinedByString: @","]);
                    _fmdb.shouldCacheStatements = NO;
                    BOOL ok = [_fmdb executeUpdate: sql];
                    _fmdb.shouldCacheStatements = YES;
                    if (!ok)
                        return self.lastDbError;
                    if ((NSUInteger)_fmdb.changes != seqsToPurge.count)
                        Warn(@"purgeRevisions: Only %i sequences deleted of (%@)",
                             _fmdb.changes, [seqsToPurge.allObjects componentsJoinedByString:@","]);
                }
                revsPurged = revsToPurge.allObjects;
            }
            result[docID] = revsPurged;
        }
        return kCBLStatusOK;
    }];
}


- (CBLStatus) pruneRevsToMaxDepth: (NSUInteger)maxDepth numberPruned: (NSUInteger*)outPruned {
    // TODO: This implementation is a bit simplistic. It won't do quite the right thing in
    // histories with branches, if one branch stops much earlier than another. The shorter branch
    // will be deleted entirely except for its leaf revision. A more accurate pruning
    // would require an expensive full tree traversal. Hopefully this way is good enough.
    if (maxDepth == 0)
        maxDepth = self.maxRevTreeDepth;

    *outPruned = 0;
    // First find which docs need pruning, and by how much:
    NSMutableDictionary* toPrune = $mdict();
    NSString* sql = @"SELECT doc_id, MIN(revid), MAX(revid) FROM revs GROUP BY doc_id";
    CBL_FMResultSet* r = [_fmdb executeQuery: sql];
    while ([r next]) {
        UInt64 docNumericID = [r longLongIntForColumnIndex: 0];
        unsigned minGen = [CBL_Revision generationFromRevID: [r stringForColumnIndex: 1]];
        unsigned maxGen = [CBL_Revision generationFromRevID: [r stringForColumnIndex: 2]];
        if ((maxGen - minGen + 1) > maxDepth)
            toPrune[@(docNumericID)] = @(maxGen - maxDepth);
    }
    [r close];

    if (toPrune.count == 0)
        return kCBLStatusOK;

    // Now prune:
    return [self _inTransaction:^CBLStatus{
        for (id docNumericID in toPrune) {
            NSString* minIDToKeep = $sprintf(@"%d-", [toPrune[docNumericID] intValue] + 1);
            if (![_fmdb executeUpdate: @"DELETE FROM revs WHERE doc_id=? AND revid < ? AND current=0",
                                       docNumericID, minIDToKeep])
                return self.lastDbError;
            *outPruned += _fmdb.changes;
        }
        return kCBLStatusOK;
    }];
}


#pragma mark - VALIDATION:


- (CBLStatus) validateRevision: (CBL_Revision*)newRev
              previousRevision: (CBL_Revision*)oldRev
                   parentRevID: (NSString*)parentRevID
{
    NSDictionary* validations = [self.shared valuesOfType: @"validation" inDatabaseNamed: _name];
    if (validations.count == 0)
        return kCBLStatusOK;
    CBLSavedRevision* publicRev = [[CBLSavedRevision alloc] initWithDatabase: self revision: newRev];
    [publicRev _setParentRevisionID: parentRevID];
    CBLValidationContext* context = [[CBLValidationContext alloc] initWithDatabase: self
                                                                        revision: oldRev
                                                                     newRevision: newRev];
    CBLStatus status = kCBLStatusOK;
    for (NSString* validationName in validations) {
        CBLValidationBlock validation = [self validationNamed: validationName];
        @try {
            validation(publicRev, context);
        } @catch (NSException* x) {
            MYReportException(x, @"validation block '%@'", validationName);
            status = kCBLStatusCallbackError;
            break;
        }
        if (context.rejectionMessage != nil) {
            LogTo(CBLValidation, @"Failed update of %@: %@:\n  Old doc = %@\n  New doc = %@",
                  oldRev, context.rejectionMessage, oldRev.properties, newRev.properties);
            status = kCBLStatusForbidden;
            break;
        }
    }
    return status;
}


@end






@implementation CBLValidationContext

- (instancetype) initWithDatabase: (CBLDatabase*)db
                         revision: (CBL_Revision*)currentRevision
                      newRevision: (CBL_Revision*)newRevision
{
    self = [super init];
    if (self) {
        _db = db;
        _currentRevision = currentRevision;
        _newRevision = newRevision;
        _errorType = kCBLStatusForbidden;
        _errorMessage = @"invalid document";
    }
    return self;
}


@synthesize rejectionMessage=_rejectionMessage;


- (CBL_Revision*) current_Revision {
    if (_currentRevision)
        _currentRevision = [_db revisionByLoadingBody: _currentRevision options: 0 status: NULL];
    return _currentRevision;
}


- (CBLSavedRevision*) currentRevision {
    CBL_Revision* cur = self.current_Revision;
    return cur ? [[CBLSavedRevision alloc] initWithDatabase: _db revision: cur] : nil;
}

- (void) reject {
    if (!_rejectionMessage)
        _rejectionMessage = @"invalid document";
}

- (void) rejectWithMessage: (NSString*)message {
    NSParameterAssert(message);
    if (!_rejectionMessage)
        _rejectionMessage = [message copy];
}


- (NSArray*) changedKeys {
    if (!_changedKeys) {
        NSMutableArray* changedKeys = [[NSMutableArray alloc] init];
        NSDictionary* cur = self.current_Revision.properties;
        NSDictionary* nuu = _newRevision.properties;
        for (NSString* key in cur.allKeys) {
            if (!$equal(cur[key], nuu[key])
                    && ![key isEqualToString: @"_rev"])
                [changedKeys addObject: key];
        }
        for (NSString* key in nuu.allKeys) {
            if (!cur[key]
                    && ![key isEqualToString: @"_rev"] && ![key isEqualToString: @"_id"])
                [changedKeys addObject: key];
        }
        _changedKeys = changedKeys;
    }
    return _changedKeys;
}

- (BOOL) validateChanges: (CBLChangeEnumeratorBlock)enumerator {
    NSDictionary* cur = self.current_Revision.properties;
    NSDictionary* nuu = _newRevision.properties;
    for (NSString* key in self.changedKeys) {
        if (!enumerator(key, cur[key], nuu[key])) {
            [self rejectWithMessage: $sprintf(@"Illegal change to '%@' property", key)];
            return NO;
        }
    }
    return YES;
}


@end
