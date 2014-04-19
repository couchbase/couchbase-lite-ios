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
- (NSString*) generateRevIDForJSON: (NSData*)json
                           deleted: (BOOL)deleted
                         prevRevID: (NSString*) prevID
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
    
    uint8_t deletedByte = deleted != NO;
    MD5_Update(&ctx, &deletedByte, 1);
    
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
        sSpecialKeysToRemove = [[NSSet alloc] initWithObjects: @"_id", @"_rev",
            @"_deleted", @"_revisions", @"_revs_info", @"_conflicts", @"_deleted_conflicts",
            @"_local_seq", nil];
        sSpecialKeysToLeave = [[NSSet alloc] initWithObjects:
            @"_attachments", @"_removed", nil];
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


- (CBL_Revision*) putRevision: (CBL_Revision*)inPutRev
               prevRevisionID: (NSString*)inPrevRevID
                allowConflict: (BOOL)allowConflict
                       status: (CBLStatus*)outStatus
{
    // "oldRev" is sort of a misnomer. It's a hodge-podge. It contains the stuff that would go into
    // a regular PUT in the REST API: The doc ID, and the new body. The actual
    // rev ID of the new revision will be assigned down below before it's inserted.
    Assert(outStatus);
    __block CBL_Revision* putRev = inPutRev;
    __block NSString* prevRevID = inPrevRevID;
    NSString* docID = putRev.docID;
    BOOL deleting = putRev.deleted;
    LogTo(CBLDatabase, @"PUT _id=%@, _rev=%@, _deleted=%d, allowConflict=%d",
          docID, prevRevID, deleting, allowConflict);
    if (!putRev || (prevRevID && !docID) || (deleting && !docID)
                || (docID && ![CBLDatabase isValidDocumentID: docID])) {
        *outStatus = kCBLStatusBadID;
        return nil;
    }

    // Make up a UUID if no docID was given:
    if (!docID)
        docID = [[self class] generateDocumentID];

    __block CBForestVersions* doc = nil;
    __block NSString* newRevID = nil;
    __block NSData* json = nil;

    *outStatus = [self _inTransaction: ^CBLStatus {
        // Get the ForestDB document:
        NSError* error;
        doc = (CBForestVersions*) [_forest documentWithID: docID
                                                  options: kCBForestDBCreateDoc
                                                    error: &error];
        if (!doc)
            return kCBLStatusDBError;
        doc.maxDepth = (unsigned)self.maxRevTreeDepth;

        CBForestRevisionFlags prevRevFlags = [doc flagsOfRevision: prevRevID];
        if (prevRevID) {
            // Updating an existing revision; make sure it exists and is a leaf:
            CBForestRevisionFlags revFlags = [doc flagsOfRevision: prevRevID];
            if (!(revFlags & kCBForestRevisionKnown))
                return kCBLStatusNotFound;
            else if (!allowConflict && !(revFlags & kCBForestRevisionLeaf))
                return kCBLStatusConflict;
        } else {
            // No parent revision given:
            if (deleting) {
                // Didn't specify a revision to delete: NotFound or a Conflict, depending
                return doc.exists ? kCBLStatusConflict : kCBLStatusNotFound;
            }
            // If doc exists, current rev must be in a deleted state or there will be a conflict:
            if (prevRevFlags & kCBForestRevisionKnown) {
                if (prevRevFlags & kCBForestRevisionDeleted) {
                    // New rev will be child of the tombstone:
                    // (T0D0: Direct a horror movie called "Child Of The Tombstone"!)
                    prevRevID = doc.revID;
                } else if (!allowConflict) {
                    return kCBLStatusConflict;
                }
            }
        }

        // Run any validation blocks:
        if ([self.shared hasValuesOfType: @"validation" inDatabaseNamed: _name]) {
            CBL_Revision* fakeNewRev = [putRev mutableCopyWithDocID: docID revID: nil];
            CBL_Revision* prevRev = nil;
            if (prevRevID) {
                prevRev = [[CBL_Revision alloc] initWithDocID: docID revID: prevRevID
                                              deleted: (prevRevFlags & kCBForestRevisionDeleted) != 0];
            }
            CBLStatus status = [self validateRevision: fakeNewRev
                                     previousRevision: prevRev
                                          parentRevID: prevRevID];
            if (CBLStatusIsError(status))
                return status;
        }

        // Add any new attachment data to the blob-store, and turn all of them into stubs:
        putRev = [self processAttachmentsForRevision: putRev
                                           prevRevID: prevRevID
                                              status: outStatus];
        if (!putRev)
            return NO;

        // Encode the body as JSON:
        if (putRev.properties) {
            json = [self encodeDocumentJSON: putRev];
            if (!json)
                return kCBLStatusBadJSON;
        }

        // Compute the new revID:
        newRevID = [self generateRevIDForJSON: json deleted: deleting prevRevID: prevRevID];
        if (!newRevID)
            return kCBLStatusBadID;  // invalid previous revID (no numeric prefix)

        if ([doc flagsOfRevision: newRevID] != 0)
            return kCBLStatusOK;    // Revision already exists

        // Add the revision to the database:
        if (![doc addRevision: json
                     deletion: putRev.deleted
                       withID: newRevID
                     parentID: prevRevID
                allowConflict: allowConflict]) {
            return kCBLStatusDBError;
        } else if (![doc save: &error]) {
            return kCBLStatusDBError;
        } else {
            return deleting ? kCBLStatusOK : kCBLStatusCreated;
        }
    }];
    if (CBLStatusIsError(*outStatus))
        return nil;

    CBL_MutableRevision* newRev = [putRev mutableCopyWithDocID: docID revID: newRevID];
    newRev.sequence = doc.sequence;

    LogTo(CBLDatabase, @"--> created %@", newRev);
    LogTo(CBLDatabaseVerbose, @"    %@", [json my_UTF8ToString]);
    
    // Epilogue: A change notification is sent:
    [self notifyChange: newRev doc: doc source: nil];
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
    
    NSData* json = [self encodeDocumentJSON: inRev];
    if (!json)
        return kCBLStatusBadJSON;

    NSUInteger historyCount = history.count;
    if (historyCount == 0) {
        history = @[revID];
        historyCount = 1;
    } else if (!$equal(history[0], revID)) {
        return kCBLStatusBadID;
    }

    // First get the CBForest doc:
    __block CBForestVersions* doc;
    CBLStatus status = [self _inTransaction: ^CBLStatus {
        NSError* error;
        doc = (CBForestVersions*)[_forest documentWithID: docID
                                                 options: kCBForestDBCreateDoc
                                                   error: &error];
        if (!doc)
            return kCBLStatusDBError;
        doc.maxDepth = (unsigned)self.maxRevTreeDepth;

        // Add the revision & ancestry to the doc:
        NSInteger common = [doc addRevision: json
                                   deletion: inRev.deleted
                                    history: history];
        if (common < 0)
            return kCBLStatusDBError;   //FIX: Get a more detailed status
        else if (common == 0)
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
        return kCBLStatusCreated;
    }];

    if (!CBLStatusIsError(status))
        [self notifyChange: inRev doc: doc source: source];
    return status;
}


#pragma mark - PURGING / COMPACTING:


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
            CBLStatus status;
            CBForestVersions* doc = [self _forestDocWithID: docID status: &status];
            if (!doc && status != kCBLStatusOK)
                return status;

            NSArray* revsPurged;
            NSArray* revIDs = $castIf(NSArray, docsToRevs[docID]);
            if (!revIDs) {
                return kCBLStatusBadParam;
            } else if (revIDs.count == 0) {
                revsPurged = @[];
            } else if ([revIDs containsObject: @"*"]) {
                // Delete all revisions if magic "*" revision ID is given:
                [_forest deleteDocument: doc error: NULL];
                revsPurged = @[@"*"];
            } else {
                revsPurged = [doc purgeRevisions: revIDs];
                if (![doc save: NULL])
                    revsPurged = @[];
            }
            result[docID] = revsPurged;
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
