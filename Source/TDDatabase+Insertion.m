//
//  TDDatabase+Insertion.m
//  TouchDB
//
//  Created by Jens Alfke on 12/27/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDDatabase+Insertion.h"
#import "TDDatabase+Attachments.h"
#import <TouchDB/TDRevision.h>
#import "TDCanonicalJSON.h"
#import "TDAttachment.h"
#import "TDInternal.h"
#import "TDMisc.h"
#import "Test.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"

#ifdef GNUSTEP
#import <openssl/sha.h>
#else
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>
#endif


NSString* const TDDatabaseChangeNotification = @"TDDatabaseChange";


@interface TDValidationContext : NSObject <TDValidationContext>
{
    @private
    TDDatabase* _db;
    TDRevision* _currentRevision;
    TDStatus _errorType;
    NSString* _errorMessage;
}
- (id) initWithDatabase: (TDDatabase*)db revision: (TDRevision*)currentRevision;
@property (readonly) TDRevision* currentRevision;
@property TDStatus errorType;
@property (copy) NSString* errorMessage;
@end



@implementation TDDatabase (Insertion)


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
    return TDCreateUUID();
}


/** Given an existing revision ID, generates an ID for the next revision.
    Returns nil if prevID is invalid. */
- (NSString*) generateIDForRevision: (TDRevision*)rev
                           withJSON: (NSData*)json
                        attachments: (NSDictionary*)attachments
                             prevID: (NSString*) prevID
{
    // Revision IDs have a generation count, a hyphen, and a hex digest.
    unsigned generation = 0;
    if (prevID) {
        generation = [TDRevision generationFromRevID: prevID];
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
        TDAttachment* attachment = [attachments objectForKey: attName];
        MD5_Update(&ctx, &attachment->blobKey, sizeof(attachment->blobKey));
    }
    
    MD5_Update(&ctx, json.bytes, json.length);
        
    MD5_Final(digestBytes, &ctx);
    NSString* digest = TDHexFromBytes(digestBytes, sizeof(digestBytes));
    return [NSString stringWithFormat: @"%u-%@", generation+1, digest];
}


/** Adds a new document ID to the 'docs' table. */
- (SInt64) insertDocumentID: (NSString*)docID {
    Assert([TDDatabase isValidDocumentID: docID]);  // this should be caught before I get here
    if (![_fmdb executeUpdate: @"INSERT INTO docs (docid) VALUES (?)", docID])
        return -1;
    return _fmdb.lastInsertRowId;
}


/** Extracts the history of revision IDs (in reverse chronological order) from the _revisions key */
+ (NSArray*) parseCouchDBRevisionHistory: (NSDictionary*)docProperties {
    NSDictionary* revisions = $castIf(NSDictionary,
                                      [docProperties objectForKey: @"_revisions"]);
    if (!revisions)
        return nil;
    // Extract the history, expanding the numeric prefixes:
    NSArray* revIDs = $castIf(NSArray, [revisions objectForKey: @"ids"]);
    __block int start = [$castIf(NSNumber, [revisions objectForKey: @"start"]) intValue];
    if (start)
        revIDs = [revIDs my_map: ^(id revID) {return $sprintf(@"%d-%@", start--, revID);}];
    return revIDs;
}


#pragma mark - INSERTION:


/** Returns the JSON to be stored into the 'json' column for a given TDRevision.
    This has all the special keys like "_id" stripped out. */
- (NSData*) encodeDocumentJSON: (TDRevision*)rev {
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
            [properties setObject: [origProps objectForKey: key] forKey: key];
        } else if (![sSpecialKeysToRemove member: key]) {
            Log(@"TDDatabase: Invalid top-level key '%@' in document to be inserted", key);
            [properties release];
            return nil;
        }
    }
    
    // Create canonical JSON -- this is important, because the JSON data returned here will be used
    // to create the new revision ID, and we need to guarantee that equivalent revision bodies
    // result in equal revision IDs.
    NSData* json = [TDCanonicalJSON canonicalData: properties];
    [properties release];
    return json;
}


/** Posts a local NSNotification of a new revision of a document. */
- (void) notifyChange: (TDRevision*)rev source: (NSURL*)source
{
    NSDictionary* userInfo = $dict({@"rev", rev},
                                   {@"seq", $object(rev.sequence)},
                                   {@"source", source});
    [[NSNotificationCenter defaultCenter] postNotificationName: TDDatabaseChangeNotification
                                                        object: self
                                                      userInfo: userInfo];
}


// Raw row insertion. Returns new sequence, or 0 on error
- (SequenceNumber) insertRevision: (TDRevision*)rev
                     docNumericID: (SInt64)docNumericID
                   parentSequence: (SequenceNumber)parentSequence
                          current: (BOOL)current
                             JSON: (NSData*)json
{
    if (![_fmdb executeUpdate: @"INSERT INTO revs (doc_id, revid, parent, current, deleted, json) "
                                "VALUES (?, ?, ?, ?, ?, ?)",
                               $object(docNumericID),
                               rev.revID,
                               (parentSequence ? $object(parentSequence) : nil ),
                               $object(current),
                               $object(rev.deleted),
                               json])
        return 0;
    return rev.sequence = _fmdb.lastInsertRowId;
}


/** Public method to add a new revision of a document. */
- (TDRevision*) putRevision: (TDRevision*)rev
             prevRevisionID: (NSString*)prevRevID   // rev ID being replaced, or nil if an insert
                     status: (TDStatus*)outStatus
{
    return [self putRevision: rev prevRevisionID: prevRevID allowConflict: NO status: outStatus];
}


/** Public method to add a new revision of a document. */
- (TDRevision*) putRevision: (TDRevision*)rev
             prevRevisionID: (NSString*)prevRevID   // rev ID being replaced, or nil if an insert
              allowConflict: (BOOL)allowConflict
                     status: (TDStatus*)outStatus
{
    LogTo(TDDatabase, @"PUT rev=%@, prevRevID=%@, allowConflict=%d", rev, prevRevID, allowConflict);
    Assert(outStatus);
    NSString* docID = rev.docID;
    BOOL deleted = rev.deleted;
    if (!rev || (prevRevID && !docID) || (deleted && !docID)
             || (docID && ![TDDatabase isValidDocumentID: docID])) {
        *outStatus = kTDStatusBadID;
        return nil;
    }
    
    *outStatus = kTDStatusDBError;  // default error is Internal Server Error, if we return nil below
    [self beginTransaction];
    FMResultSet* r = nil;
    TDStatus status;
    @try {
        //// PART I: In which are performed lookups and validations prior to the insert...
        
        SInt64 docNumericID = docID ? [self getDocNumericID: docID] : 0;
        SequenceNumber parentSequence = 0;
        if (prevRevID) {
            // Replacing: make sure given prevRevID is current & find its sequence number:
            if (docNumericID <= 0) {
                *outStatus = kTDStatusNotFound;
                return nil;
            }
            NSString* sql = $sprintf(@"SELECT sequence FROM revs "
                                      "WHERE doc_id=? AND revid=? %@ LIMIT 1",
                                     (allowConflict ? @"" : @"AND current=1"));
            parentSequence = [_fmdb longLongForQuery: sql, $object(docNumericID), prevRevID];
            if (parentSequence == 0) {
                // Not found: kTDStatusNotFound or a kTDStatusConflict, depending on whether there is any current revision
                if (!allowConflict && [self existsDocumentWithID: docID revisionID: nil])
                    *outStatus = kTDStatusConflict;
                else
                    *outStatus = kTDStatusNotFound;
                return nil;
            }
            
            if (_validations.count > 0) {
                // Fetch the previous revision and validate the new one against it:
                TDRevision* prevRev = [[TDRevision alloc] initWithDocID: docID revID: prevRevID
                                                                deleted: NO];
                status = [self validateRevision: rev previousRevision: prevRev];
                [prevRev release];
                if (TDStatusIsError(status)) {
                    *outStatus = status;
                    return nil;
                }
            }
            
            // Make replaced rev non-current:
            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                                       $object(parentSequence)])
                return nil;
            
        } else {
            // Inserting first revision.
            if (deleted && docID) {
                // Didn't specify a revision to delete: kTDStatusNotFound or a kTDStatusConflict, depending
                *outStatus = [self existsDocumentWithID: docID revisionID: nil] ? kTDStatusConflict : kTDStatusNotFound;
                return nil;
            }
            
            // Validate:
            status = [self validateRevision: rev previousRevision: nil];
            if (TDStatusIsError(status)) {
                *outStatus = status;
                return nil;
            }
            
            if (docID) {
                // Inserting first revision, with docID given (PUT):
                if (docNumericID <= 0) {
                    // Doc ID doesn't exist at all; create it:
                    docNumericID = [self insertDocumentID: docID];
                    if (docNumericID <= 0)
                        return nil;
                } else {
                    // Doc ID exists; check whether current winning revision is deleted:
                    r = [_fmdb executeQuery: @"SELECT sequence, deleted FROM revs "
                                              "WHERE doc_id=? and current=1 ORDER BY revid DESC LIMIT 1",
                                             $object(docNumericID)];
                    if (!r)
                        return nil;
                    if ([r next]) {
                        if ([r boolForColumnIndex: 1]) {
                            // Make the deleted revision no longer current:
                            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                                                       $object([r longLongIntForColumnIndex: 0])])
                                return nil;
                        } else if (!allowConflict) {
                            // The current winning revision is not deleted, so this is a conflict
                            *outStatus = kTDStatusConflict;
                            return nil;
                        }
                    }
                    [r close];
                    r = nil;
                }
            } else {
                // Inserting first revision, with no docID given (POST): generate a unique docID:
                docID = [[self class] generateDocumentID];
                docNumericID = [self insertDocumentID: docID];
                if (docNumericID <= 0)
                    return nil;
            }
        }
        
        //// PART II: In which insertion occurs...
        
        // Get the attachments:
        NSDictionary* attachments = [self attachmentsFromRevision: rev status: &status];
        if (!attachments) {
            *outStatus = status;
            return nil;
        }
        
        // Bump the revID and update the JSON:
        NSData* json = nil;
        if (rev.properties) {
            json = [self encodeDocumentJSON: rev];
            if (!json) {
                *outStatus = kTDStatusBadJSON;
                return nil;
            }
            if (json.length == 2 && memcmp(json.bytes, "{}", 2)==0)
                json = nil;
        }
        NSString* newRevID = [self generateIDForRevision: rev
                                                withJSON: json
                                             attachments: attachments
                                                  prevID: prevRevID];
        if (!newRevID) {
            *outStatus = kTDStatusBadID;  // invalid previous revID (no numeric prefix)
            return nil;
        }
        rev = [[rev copyWithDocID: docID revID: newRevID] autorelease];
        
        // Now insert the rev itself:
        SequenceNumber sequence = [self insertRevision: rev
                                          docNumericID: docNumericID
                                        parentSequence: parentSequence
                                               current: YES
                                                  JSON: json];
        if (!sequence) {
            // The insert failed. If it was due to a constraint violation, that means an identical
            // revision already exists; so just return it.
            if (_fmdb.lastErrorCode == SQLITE_CONSTRAINT) {
                *outStatus = kTDStatusOK;
                rev.body = nil;
                return rev;
            } else {
                return nil;
            }
        }
        
        // Store any attachments:
        status = [self processAttachments: attachments
                              forRevision: rev
                       withParentSequence: parentSequence];
        if (TDStatusIsError(status)) {
            *outStatus = status;
            return nil;
        }
        
        // Success!
        *outStatus = deleted ? kTDStatusOK : kTDStatusCreated;
        
    } @finally {
        // Remember, we could have gotten here via a 'return' inside the @try block above.
        [r close];
        [self endTransaction: (*outStatus < 300)];
    }
    
    if (TDStatusIsError(*outStatus)) 
        return nil;
    
    //// EPILOGUE: A change notification is sent...
    rev.body = nil;     // body is not up to date (no current _rev, likely no _id) so avoid confusion
    [self notifyChange: rev source: nil];
    return rev;
}


/** Public method to add an existing revision of a document (probably being pulled). */
- (TDStatus) forceInsert: (TDRevision*)rev
         revisionHistory: (NSArray*)history  // in *reverse* order, starting with rev's revID
                  source: (NSURL*)source
{
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    if (![TDDatabase isValidDocumentID: docID] || !revID)
        return kTDStatusBadID;
    
    NSUInteger historyCount = history.count;
    if (historyCount == 0) {
        history = $array(revID);
        historyCount = 1;
    } else if (!$equal([history objectAtIndex: 0], revID))
        return kTDStatusBadID;
    
    BOOL success = NO;
    [self beginTransaction];
    @try {
        // First look up the document's row-id and all locally-known revisions of it:
        TDRevisionList* localRevs = nil;
        SInt64 docNumericID = [self getDocNumericID: docID];
        if (docNumericID > 0) {
            localRevs = [self getAllRevisionsOfDocumentID: docID
                                                numericID: docNumericID
                                              onlyCurrent: NO];
            if (!localRevs)
                return kTDStatusDBError;
        } else {
            docNumericID = [self insertDocumentID: docID];
            if (docNumericID <= 0)
                return kTDStatusDBError;
        }

        // Validate against the latest common ancestor:
        if (_validations.count > 0) {
            TDRevision* oldRev = nil;
            for (NSUInteger i = 1; i<historyCount; ++i) {
                oldRev = [localRevs revWithDocID: docID revID: [history objectAtIndex: i]];
                if (oldRev)
                    break;
            }
            TDStatus status = [self validateRevision: rev previousRevision: oldRev];
            if (TDStatusIsError(status))
                return status;
        }
        
        // Walk through the remote history in chronological order, matching each revision ID to
        // a local revision. When the list diverges, start creating blank local revisions to fill
        // in the local history:
        SequenceNumber sequence = 0;
        SequenceNumber localParentSequence = 0;
        for (NSInteger i = historyCount - 1; i>=0; --i) {
            NSString* revID = [history objectAtIndex: i];
            TDRevision* localRev = [localRevs revWithDocID: docID revID: revID];
            if (localRev) {
                // This revision is known locally. Remember its sequence as the parent of the next one:
                sequence = localRev.sequence;
                Assert(sequence > 0);
                localParentSequence = sequence;
                
            } else {
                // This revision isn't known, so add it:
                TDRevision* newRev;
                NSData* json = nil;
                BOOL current = NO;
                if (i==0) {
                    // Hey, this is the leaf revision we're inserting:
                    newRev = rev;
                    if (!rev.deleted) {
                        json = [self encodeDocumentJSON: rev];
                        if (!json)
                            return kTDStatusBadJSON;
                    }
                    current = YES;
                } else {
                    // It's an intermediate parent, so insert a stub:
                    newRev = [[[TDRevision alloc] initWithDocID: docID revID: revID deleted: NO]
                                    autorelease];
                }

                // Insert it:
                sequence = [self insertRevision: newRev
                                   docNumericID: docNumericID
                                 parentSequence: sequence
                                        current: current 
                                           JSON: json];
                if (sequence <= 0)
                    return kTDStatusDBError;
                newRev.sequence = sequence;
                
                if (i==0) {
                    // Write any changed attachments for the new revision. As the parent sequence use
                    // the latest local revision (this is to copy attachments from):
                    TDStatus status;
                    NSDictionary* attachments = [self attachmentsFromRevision: rev status: &status];
                    if (attachments)
                        status = [self processAttachments: attachments
                                              forRevision: rev
                                       withParentSequence: localParentSequence];
                    if (TDStatusIsError(status)) 
                        return status;
                }
            }
        }

        // Mark the latest local rev as no longer current:
        if (localParentSequence > 0 && localParentSequence != sequence) {
            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                  $object(localParentSequence)])
                return kTDStatusDBError;
        }

        success = YES;
    } @finally {
        [self endTransaction: success];
    }
    
    // Notify and return:
    [self notifyChange: rev source: source];
    return kTDStatusCreated;
}


#pragma mark - VALIDATION:


- (void) defineValidation: (NSString*)validationName asBlock: (TDValidationBlock)validationBlock {
    if (validationBlock) {
        if (!_validations)
            _validations = [[NSMutableDictionary alloc] init];
        [_validations setValue: [[validationBlock copy] autorelease] forKey: validationName];
    } else {
        [_validations removeObjectForKey: validationName];
    }
}

- (TDValidationBlock) validationNamed: (NSString*)validationName {
    return [_validations objectForKey: validationName];
}


- (TDStatus) validateRevision: (TDRevision*)newRev previousRevision: (TDRevision*)oldRev {
    if (_validations.count == 0)
        return kTDStatusOK;
    TDValidationContext* context = [[TDValidationContext alloc] initWithDatabase: self
                                                                        revision: oldRev];
    TDStatus status = kTDStatusOK;
    for (TDValidationBlock validationName in _validations) {
        TDValidationBlock validation = [self validationNamed: validationName];
        if (!validation(newRev, context)) {
            status = context.errorType;
            break;
        }
    }
    [context release];
    return status;
}


@end






@implementation TDValidationContext

- (id) initWithDatabase: (TDDatabase*)db revision: (TDRevision*)currentRevision {
    self = [super init];
    if (self) {
        _db = db;
        _currentRevision = currentRevision;
        _errorType = kTDStatusForbidden;
        _errorMessage = [@"invalid document" retain];
    }
    return self;
}

- (void)dealloc {
    [_errorMessage release];
    [super dealloc];
}

- (TDRevision*) currentRevision {
    if (_currentRevision)
        [_db loadRevisionBody: _currentRevision options: 0];
    return _currentRevision;
}

@synthesize errorType=_errorType, errorMessage=_errorMessage;

@end
