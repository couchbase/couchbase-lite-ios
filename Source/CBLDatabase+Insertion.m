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
@property int errorType;
@property (copy) NSString* errorMessage;
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
    NSString* digest = CBLHexFromBytes(digestBytes, sizeof(digestBytes));
    return [NSString stringWithFormat: @"%u-%@", generation+1, digest];
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
            @"_replication_id", @"_replication_state", @"_replication_state_time", nil];
    }

    NSDictionary* origProps = rev.properties;
    if (!origProps)
        return nil;
    
    // Don't leave in any "_"-prefixed keys except for the ones in sSpecialKeysToLeave.
    // Keys in sSpecialKeysToIgnore (_id, _rev, ...) are left out, any others trigger an error.
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


// Raw row insertion. Returns new sequence, or 0 on error
- (SequenceNumber) insertRevision: (CBL_Revision*)rev
                     docNumericID: (SInt64)docNumericID
                   parentSequence: (SequenceNumber)parentSequence
                          current: (BOOL)current
                   hasAttachments: (BOOL)hasAttachments
                             JSON: (NSData*)json
{
    if (![_fmdb executeUpdate: @"INSERT INTO revs (doc_id, revid, parent, current, deleted, "
                                                  "no_attachments, json) "
                                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                               @(docNumericID),
                               rev.revID,
                               (parentSequence ? @(parentSequence) : nil ),
                               @(current),
                               @(rev.deleted),
                               @(!hasAttachments),
                               json])
        return 0;
    return rev.sequence = _fmdb.lastInsertRowId;
}


/** Top-level method to add a new revision of a document. */
- (CBL_Revision*) putRevision: (CBL_Revision*)oldRev
               prevRevisionID: (NSString*)inputPrevRevID   // rev ID being replaced, nil if insert
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

    __block CBL_MutableRevision* newRev = nil;
    __block CBL_Revision* winningRev = nil;
    __block BOOL maybeConflict = NO;

    *outStatus = [self _inTransaction: ^CBLStatus {
        // Remember, this block may be called multiple times if I have to retry the transaction.
        newRev = nil;
        winningRev = nil;
        maybeConflict = NO;
        NSString* prevRevID = inputPrevRevID;
        NSString* docID = oldRev.docID;

        //// PART I: In which are performed lookups and validations prior to the insert...

        // Get the doc's numeric ID (doc_id) and its current winning revision:
        SInt64 docNumericID = docID ? [self getDocNumericID: docID] : 0;
        BOOL oldWinnerWasDeletion = NO;
        BOOL wasConflicted = NO;
        NSString* oldWinningRevID = nil;
        if (docNumericID > 0) {
            // Look up which rev is the winner, before this insertion
            //OPT: This rev ID could be cached in the 'docs' row
            oldWinningRevID = [self winningRevIDOfDocNumericID: docNumericID
                                                     isDeleted: &oldWinnerWasDeletion
                                                    isConflict: &wasConflicted];
        }

        SequenceNumber parentSequence = 0;
        if (prevRevID) {
            // Replacing: make sure given prevRevID is current & find its sequence number:
            if (docNumericID <= 0)
                return kCBLStatusNotFound;
            parentSequence = [self getSequenceOfDocument: docNumericID revision: prevRevID
                                             onlyCurrent: !allowConflict];
            if (parentSequence == 0) {
                // Not found: kCBLStatusNotFound or a kCBLStatusConflict, depending on whether there is any current revision
                if (!allowConflict && [self existsDocumentWithID: docID revisionID: nil])
                    return kCBLStatusConflict;
                else
                    return kCBLStatusNotFound;
            }

            if ([self.shared hasValuesOfType: @"validation" inDatabaseNamed: _name]) {
                // Fetch the previous revision and validate the new one against it:
                CBL_Revision* prevRev = [[CBL_Revision alloc] initWithDocID: docID revID: prevRevID
                                                                  deleted: NO];
                CBLStatus status = [self validateRevision: oldRev previousRevision: prevRev];
                if (CBLStatusIsError(status))
                    return status;
            }
            
        } else {
            // Inserting first revision.
            if (deleted && docID) {
                // Didn't specify a revision to delete: NotFound or a Conflict, depending
                return [self existsDocumentWithID: docID revisionID: nil] ? kCBLStatusConflict
                                                                          : kCBLStatusNotFound;
            }
            
            // Validate:
            CBLStatus status = [self validateRevision: oldRev previousRevision: nil];
            if (CBLStatusIsError(status))
                return status;

            if (docID) {
                // Inserting first revision, with docID given (PUT):
                if (docNumericID <= 0) {
                    // Doc ID doesn't exist at all; create it:
                    docNumericID = [self insertDocumentID: docID];
                    if (docNumericID <= 0)
                        return self.lastDbError;
                } else {
                    // Doc ID exists; check whether current winning revision is deleted:
                    if (oldWinnerWasDeletion) {
                        prevRevID = oldWinningRevID;
                        parentSequence = [self getSequenceOfDocument: docNumericID
                                                            revision: prevRevID
                                                         onlyCurrent: NO];
                    } else if (oldWinningRevID) {
                        // The current winning revision is not deleted, so this is a conflict
                        return kCBLStatusConflict;
                    }
                }
            } else {
                // Inserting first revision, with no docID given (POST): generate a unique docID:
                docID = [[self class] generateDocumentID];
                docNumericID = [self insertDocumentID: docID];
                if (docNumericID <= 0)
                    return self.lastDbError;
            }
        }

        // There may be a conflict if (a) the document was already in conflict, or
        // (b) a conflict is created by adding a non-deletion child of a non-winning rev.
        maybeConflict = wasConflicted || (!deleted && !$equal(prevRevID, oldWinningRevID));

        //// PART II: In which we prepare for insertion...
        
        // Get the attachments:
        CBLStatus status;
        NSDictionary* attachments = [self attachmentsFromRevision: oldRev status: &status];
        if (!attachments)
            return status;

        // Bump the revID and update the JSON:
        NSData* json = nil;
        if (oldRev.properties) {
            json = [self encodeDocumentJSON: oldRev];
            if (!json)
                return kCBLStatusBadJSON;
            if (json.length == 2 && memcmp(json.bytes, "{}", 2)==0)
                json = nil;
        }
        NSString* newRevID = [self generateIDForRevision: oldRev
                                                withJSON: json
                                             attachments: attachments
                                                  prevID: prevRevID];
        if (!newRevID)
            return kCBLStatusBadID;  // invalid previous revID (no numeric prefix)
        Assert(docID);
        newRev = [oldRev mutableCopyWithDocID: docID revID: newRevID];
        [CBLDatabase stubOutAttachments: attachments inRevision: newRev];
        
        // Don't store a SQL null in the 'json' column -- I reserve it to mean that the revision data
        // is missing due to compaction or replication.
        // Instead, store an empty zero-length blob.
        if (json == nil)
            json = [NSData data];
        
        //// PART III: In which the actual insertion finally takes place:
        
        SequenceNumber sequence = [self insertRevision: newRev
                                          docNumericID: docNumericID
                                        parentSequence: parentSequence
                                               current: YES
                                        hasAttachments: (oldRev[@"_attachments"] != nil)
                                                  JSON: json];
        if (!sequence) {
            // The insert failed. If it was due to a constraint violation, that means a revision
            // already exists with identical contents and the same parent rev. We can ignore this
            // insert call, then.
            if (_fmdb.lastErrorCode != SQLITE_CONSTRAINT)
                return self.lastDbError;
            LogTo(CBLDatabase, @"Duplicate rev insertion: %@ / %@", docID, newRevID);
            newRev.body = nil;
            return kCBLStatusOK;
        }
        
        // Make replaced rev non-current:
        if (parentSequence > 0) {
            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                                       @(parentSequence)])
                return self.lastDbError;
        }

        // Store any attachments:
        status = [self processAttachments: attachments
                              forRevision: newRev
                       withParentSequence: parentSequence];
        if (CBLStatusIsError(status))
            return status;

        // Figure out what the new winning rev ID is:
        winningRev = [self winnerWithDocID: docNumericID
                                 oldWinner: oldWinningRevID oldDeleted: oldWinnerWasDeletion
                                    newRev: newRev];

        // Success!
        return deleted ? kCBLStatusOK : kCBLStatusCreated;
    }];
    
    if (CBLStatusIsError(*outStatus)) 
        return nil;
    
    //// EPILOGUE: A change notification is sent...
    [self notifyChange: [[CBLDatabaseChange alloc] initWithAddedRevision: newRev
                                                         winningRevision: winningRev
                                                           maybeConflict: maybeConflict
                                                                  source: nil]];
    return newRev;
}


/** Add an existing revision of a document (probably being pulled) plus its ancestors. */
- (CBLStatus) forceInsert: (CBL_Revision*)inRev
          revisionHistory: (NSArray*)history  // in *reverse* order, starting with rev's revID
                   source: (NSURL*)source
{
    CBL_MutableRevision* rev = inRev.mutableCopy;
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    if (![CBLDatabase isValidDocumentID: docID] || !revID)
        return kCBLStatusBadID;
    
    NSUInteger historyCount = history.count;
    if (historyCount == 0) {
        history = @[revID];
        historyCount = 1;
    } else if (!$equal(history[0], revID))
        return kCBLStatusBadID;
    
    __block CBL_Revision* winningRev = nil;
    __block BOOL maybeConflict = NO;
    CBLStatus status = [self _inTransaction: ^CBLStatus {
        // First look up the document's row-id and all locally-known revisions of it:
        CBL_RevisionList* localRevs = nil;
        SInt64 docNumericID = [self getDocNumericID: docID];
        if (docNumericID > 0) {
            localRevs = [self getAllRevisionsOfDocumentID: docID
                                                numericID: docNumericID
                                              onlyCurrent: NO];
            if (!localRevs)
                return self.lastDbError;
        } else {
            docNumericID = [self insertDocumentID: docID];
            if (docNumericID <= 0)
                return self.lastDbError;
        }

        // Validate against the latest common ancestor:
        if (([self.shared hasValuesOfType: @"validation" inDatabaseNamed: _name])) {
            CBL_Revision* oldRev = nil;
            for (NSUInteger i = 1; i<historyCount; ++i) {
                oldRev = [localRevs revWithDocID: docID revID: history[i]];
                if (oldRev)
                    break;
            }
            CBLStatus status = [self validateRevision: rev previousRevision: oldRev];
            if (CBLStatusIsError(status))
                return status;
        }
        
        // Look up which rev is the winner, before this insertion
        //OPT: This rev ID could be cached in the 'docs' row
        BOOL oldWinnerWasDeletion;
        NSString* oldWinningRevID = [self winningRevIDOfDocNumericID: docNumericID
                                                           isDeleted: &oldWinnerWasDeletion
                                                          isConflict: &maybeConflict];

        // Walk through the remote history in chronological order, matching each revision ID to
        // a local revision. When the list diverges, start creating blank local revisions to fill
        // in the local history:
        SequenceNumber sequence = 0;
        SequenceNumber localParentSequence = 0;
        NSString* localParentRevID = nil;
        for (NSInteger i = historyCount - 1; i>=0; --i) {
            NSString* revID = history[i];
            CBL_Revision* localRev = [localRevs revWithDocID: docID revID: revID];
            if (localRev) {
                // This revision is known locally. Remember its sequence as the parent of the next one:
                sequence = localRev.sequence;
                Assert(sequence > 0);
                localParentSequence = sequence;
                localParentRevID = revID;
                
            } else {
                // This revision isn't known, so add it:

                if (sequence == localParentSequence) {
                    // This is the point where we branch off of the existing rev tree.
                    // If the branch wasn't from the single existing leaf, this creates a conflict.
                    maybeConflict = maybeConflict || (!rev.deleted && !$equal(localParentRevID, revID));
                }

                CBL_MutableRevision* newRev;
                NSData* json = nil;
                BOOL current = NO;
                if (i==0) {
                    // Hey, this is the leaf revision we're inserting:
                    newRev = rev;
                    json = [self encodeDocumentJSON: rev];
                    if (!json)
                        return kCBLStatusBadJSON;
                    current = YES;
                } else {
                    // It's an intermediate parent, so insert a stub:
                    newRev = [[CBL_MutableRevision alloc] initWithDocID: docID revID: revID
                                                                deleted: NO];
                }

                // Insert it:
                sequence = [self insertRevision: newRev
                                   docNumericID: docNumericID
                                 parentSequence: sequence
                                        current: current 
                                 hasAttachments: (newRev[@"_attachments"] != nil)
                                           JSON: json];
                if (sequence <= 0)
                    return self.lastDbError;

                if (i==0) {
                    // Write any changed attachments for the new revision. As the parent sequence use
                    // the latest local revision (this is to copy attachments from):
                    CBLStatus status;
                    NSDictionary* attachments = [self attachmentsFromRevision: rev status: &status];
                    if (attachments) {
                        status = [self processAttachments: attachments
                                              forRevision: rev
                                       withParentSequence: localParentSequence];
                        [CBLDatabase stubOutAttachments: attachments inRevision: rev];
                    }
                    if (CBLStatusIsError(status))
                        return status;
                }
            }
        }

        if (localParentSequence == sequence)
            return kCBLStatusOK;      // No-op: No new revisions were inserted.

        // Mark the latest local rev as no longer current:
        if (localParentSequence > 0) {
            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                  @(localParentSequence)])
                return self.lastDbError;
        }

        // Figure out what the new winning rev ID is:
        winningRev = [self winnerWithDocID: docNumericID
                                 oldWinner: oldWinningRevID oldDeleted: oldWinnerWasDeletion
                                    newRev: rev];

        return kCBLStatusCreated;
    }];

    if (!CBLStatusIsError(status)) {
        [self notifyChange: [[CBLDatabaseChange alloc] initWithAddedRevision: rev
                                                             winningRevision: winningRev
                                                               maybeConflict: maybeConflict
                                                                      source: source]];
    }
    return status;
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


- (CBLStatus) validateRevision: (CBL_Revision*)newRev previousRevision: (CBL_Revision*)oldRev {
    NSDictionary* validations = [self.shared valuesOfType: @"validation" inDatabaseNamed: _name];
    if (validations.count == 0)
        return kCBLStatusOK;
    CBLSavedRevision* publicRev = [[CBLSavedRevision alloc] initWithDatabase: self revision: newRev];
    CBLValidationContext* context = [[CBLValidationContext alloc] initWithDatabase: self
                                                                        revision: oldRev
                                                                     newRevision: newRev];
    CBLStatus status = kCBLStatusOK;
    for (NSString* validationName in validations) {
        CBLValidationBlock validation = [self validationNamed: validationName];
        @try {
            if (!validation(publicRev, context)) {
                status = context.errorType;
                break;
            }
        } @catch (NSException* x) {
            MYReportException(x, @"validation block '%@'", validationName);
            status = kCBLStatusCallbackError;
            break;
        }
    }
    if (CBLStatusIsError(status))
        LogTo(CBLValidation, @"Failed update of %@: %d %@:\n  Old doc = %@\n  New doc = %@",
             oldRev, context.errorType, context.errorMessage, oldRev.properties, newRev.properties);
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


- (CBL_Revision*) current_Revision {
    if (_currentRevision)
        _currentRevision = [_db revisionByLoadingBody: _currentRevision options: 0 status: NULL];
    return _currentRevision;
}


- (CBLSavedRevision*) currentRevision {
    CBL_Revision* cur = self.current_Revision;
    return cur ? [[CBLSavedRevision alloc] initWithDatabase: _db revision: cur] : nil;
}

@synthesize errorType=_errorType, errorMessage=_errorMessage;

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

- (BOOL) allowChangesOnlyTo: (NSArray*)keys {
    for (NSString* key in self.changedKeys) {
        if (![keys containsObject: key]) {
            self.errorMessage = $sprintf(@"The '%@' property may not be changed", key);
            return NO;
        }
    }
    return YES;
}

- (BOOL) disallowChangesTo: (NSArray*)keys {
    for (NSString* key in self.changedKeys) {
        if ([keys containsObject: key]) {
            self.errorMessage = $sprintf(@"The '%@' property may not be changed", key);
            return NO;
        }
    }
    return YES;
}

- (BOOL) enumerateChanges: (CBLChangeEnumeratorBlock)enumerator {
    NSDictionary* cur = self.current_Revision.properties;
    NSDictionary* nuu = _newRevision.properties;
    for (NSString* key in self.changedKeys) {
        if (!enumerator(key, cur[key], nuu[key])) {
            if ($equal(_errorMessage, @"invalid document"))
                self.errorMessage = $sprintf(@"Illegal change to '%@' property", key);
            return NO;
        }
    }
    return YES;
}

@end
