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

extern "C" {
#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+Attachments.h"
#import "CBLDatabase.h"
#import "CouchbaseLitePrivate.h"
#import "CBLDocument.h"
#import "CBL_Revision.h"
#import "CBL_Attachment.h"
#import "CBLDatabaseChange.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "Test.h"
#import "ExceptionUtils.h"
}

#import <CBForest/CBForest.hh>
using namespace forestdb;

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
    __block MD5_CTX ctx;
    unsigned char digestBytes[MD5_DIGEST_LENGTH];
    MD5_Init(&ctx);

    __block BOOL tooLong = NO;
    CBLWithStringBytes(prevID, ^(const char *bytes, size_t length) {
        if (length > 0xFF)
            tooLong = YES;
        uint8_t lengthByte = length & 0xFF;
        MD5_Update(&ctx, &lengthByte, 1);       // prefix with length byte
        if (length > 0)
            MD5_Update(&ctx, bytes, length);
    });
    
    uint8_t deletedByte = deleted != NO;
    MD5_Update(&ctx, &deletedByte, 1);
    
    MD5_Update(&ctx, json.bytes, json.length);
    MD5_Final(digestBytes, &ctx);

    char hex[11 + 2*MD5_DIGEST_LENGTH + 1];
    char *dst = hex + sprintf(hex, "%u-", generation+1);
    dst = CBLAppendHex(dst, digestBytes, sizeof(digestBytes));
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


- (CBLDatabaseChange*) changeWithNewRevision: (CBL_Revision*)inRev
                                isWinningRev: (BOOL)isWinningRev
                                         doc: (VersionedDocument&)doc
                                      source: (NSURL*)source
{
    CBL_Revision* winningRev = inRev;
    if (!isWinningRev) {
        const Revision* winningRevision = doc.currentRevision();
        NSString* winningRevID = (NSString*)winningRevision->revID;
        if (!$equal(winningRevID, inRev.revID)) {
            winningRev = [[CBL_Revision alloc] initWithDocID: inRev.docID
                                                       revID: winningRevID
                                                     deleted: winningRevision->isDeleted()];
        }
    }
    return [[CBLDatabaseChange alloc] initWithAddedRevision: inRev
                                            winningRevision: winningRev
                                                 inConflict: doc.hasConflict()
                                                     source: source];
}


- (CBL_Revision*) putRevision: (CBL_MutableRevision*)putRev
               prevRevisionID: (NSString*)inPrevRevID
                allowConflict: (BOOL)allowConflict
                       status: (CBLStatus*)outStatus
{
    return [self putDocID: putRev.docID properties: [putRev.properties mutableCopy]
           prevRevisionID: inPrevRevID allowConflict: allowConflict status: outStatus];
}


- (CBL_Revision*) putDocID: (NSString*)inDocID
                properties: (NSMutableDictionary*)properties
            prevRevisionID: (NSString*)inPrevRevID
             allowConflict: (BOOL)allowConflict
                    status: (CBLStatus*)outStatus
{
    Assert(outStatus);
    __block NSString* docID = inDocID;
    __block NSString* prevRevID = inPrevRevID;
    BOOL deleting = !properties || properties.cbl_deleted;
    LogTo(CBLDatabase, @"PUT _id=%@, _rev=%@, _deleted=%d, allowConflict=%d",
          docID, prevRevID, deleting, allowConflict);
    if ((prevRevID && !docID) || (deleting && !docID)
            || (docID && ![CBLDatabase isValidDocumentID: docID])) {
        *outStatus = kCBLStatusBadID;
        return nil;
    }

    if (_forest->isReadOnly()) {
        *outStatus = kCBLStatusForbidden;
        return nil;
    }

    __block CBL_MutableRevision* putRev = nil;
    __block CBLDatabaseChange* change = nil;

    __block NSData* json = nil;
#ifdef ASYNC_ENCODE
    dispatch_semaphore_t jsonSemaphore = NULL;
#endif
    if (properties) {
        if (properties.cbl_attachments) {
            // Add any new attachment data to the blob-store, and turn all of them into stubs:
            //FIX: Optimize this to avoid creating a revision object
            CBL_MutableRevision* tmpRev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                               revID: prevRevID
                                                                             deleted: deleting];
            tmpRev.properties = properties;
            if (![self processAttachmentsForRevision: tmpRev
                                           prevRevID: prevRevID
                                              status: outStatus])
                return nil;
            properties = [tmpRev.properties mutableCopy];
        }

#ifdef ASYNC_ENCODE
        // Asynchronously convert the revision to JSON (this is expensive):
        static dispatch_queue_t sJSONQueue;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sJSONQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        });
        jsonSemaphore = dispatch_semaphore_create(0);
        dispatch_async(sJSONQueue, ^{
            json = [CBL_Revision asCanonicalJSON: properties];
            dispatch_semaphore_signal(jsonSemaphore);
        });
#else
        json = [CBL_Revision asCanonicalJSON: properties error: NULL];
        if (!json) {
            *outStatus = kCBLStatusBadJSON;
            return nil;
        }
#endif
    } else {
        json = [NSData dataWithBytes: "{}" length: 2];
    }

    *outStatus = [self _inTransaction: ^CBLStatus {
        Document rawDoc;
        if (docID) {
            // Read the doc from the database:
            rawDoc.setKey(nsstring_slice(docID));
            _forest->read(rawDoc);
        } else {
            // Create new doc ID, and don't bother to read it since it's a new doc:
            docID = [[self class] generateDocumentID];
            rawDoc.setKey(nsstring_slice(docID));
        }

        // Parse the document revision tree:
        VersionedDocument doc(_forest, rawDoc);
        const Revision* revNode;

        if (prevRevID) {
            // Updating an existing revision; make sure it exists and is a leaf:
            revNode = doc.get(prevRevID);
            if (!revNode)
                return kCBLStatusNotFound;
            else if (!allowConflict && !revNode->isLeaf())
                return kCBLStatusConflict;
        } else {
            // No parent revision given:
            if (deleting) {
                // Didn't specify a revision to delete: NotFound or a Conflict, depending
                return doc.exists() ? kCBLStatusConflict : kCBLStatusNotFound;
            }
            // If doc exists, current rev must be in a deleted state or there will be a conflict:
            revNode = doc.currentRevision();
            if (revNode) {
                if (revNode->isDeleted()) {
                    // New rev will be child of the tombstone:
                    // (T0D0: Write a horror novel called "Child Of The Tombstone"!)
                    prevRevID = (NSString*)revNode->revID;
                } else {
                    return kCBLStatusConflict;
                }
            }
        }

        BOOL hasValidations = [self.shared hasValuesOfType: @"validation" inDatabaseNamed: _name];

#ifdef ASYNC_ENCODE
        // Get the JSON that we already started encoding:
        if (properties) {
            dispatch_semaphore_wait(jsonSemaphore, DISPATCH_TIME_FOREVER);
            if (!json)
                return kCBLStatusBadJSON;
        }
#endif

        // Compute the new revID:
        NSString* newRevID = [self generateRevIDForJSON: json
                                                deleted: deleting
                                              prevRevID: prevRevID];
        if (!newRevID)
            return kCBLStatusBadID;  // invalid previous revID (no numeric prefix)

        putRev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                      revID: newRevID
                                                    deleted: deleting];
        if (properties) {
            properties[@"_id"] = docID;
            properties[@"_rev"] = newRevID;
            putRev.properties = properties;
        }

        // Run any validation blocks:
        if (hasValidations) {
            CBL_Revision* prevRev = nil;
            if (prevRevID) {
                prevRev = [[CBL_Revision alloc] initWithDocID: docID
                                                        revID: prevRevID
                                                      deleted: revNode->isDeleted()];
            }
            CBLStatus status = [self validateRevision: putRev
                                     previousRevision: prevRev
                                          parentRevID: prevRevID];
            if (CBLStatusIsError(status))
                return status;
        }

        // Add the revision to the database:
        int status;
        BOOL isWinner;
        {
            const Revision* fdbRev = doc.insert(revidBuffer(newRevID), json,
                                                deleting,
                                                (putRev.attachments != nil),
                                                revNode, allowConflict, status);
            if (fdbRev)
                putRev.sequence = fdbRev->sequence;
            else if (CBLStatusIsError((CBLStatus)status))
                return (CBLStatus)status;
            isWinner = (fdbRev == doc.currentRevision());
        } // prune call will invalidate fdbRev ptr, so let it go out of scope
        doc.prune((unsigned)self.maxRevTreeDepth);
        doc.save(*_forestTransaction);
#if DEBUG
        LogTo(CBLDatabase, @"Saved %s", doc.dump().c_str());
#endif

        change = [self changeWithNewRevision: putRev
                                isWinningRev: isWinner
                                         doc: doc
                                      source: nil];

        return (CBLStatus)status;
    }];
    if (CBLStatusIsError(*outStatus))
        return nil;

    LogTo(CBLDatabase, @"--> created %@", putRev);
    LogTo(CBLDatabaseVerbose, @"    %@", [json my_UTF8ToString]);
    
    // Epilogue: A change notification is sent:
    if (change)
        [self notifyChange: change];
    return putRev;
}


static void convertRevIDs(NSArray* revIDs,
                          std::vector<revidBuffer> &historyBuffers,
                          std::vector<revid> &historyVector)
{
    historyBuffers.resize(revIDs.count);
    for (NSString* revID in revIDs) {
        historyBuffers.push_back(revidBuffer(revID));
        historyVector.push_back(historyBuffers.back());
    }
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
    
    if (_forest->isReadOnly())
        return kCBLStatusForbidden;

    if (history.count == 0)
        history = @[revID];
    else if (!$equal(history[0], revID))
        return kCBLStatusBadID;

    CBLStatus status;
    if (inRev.attachments) {
        CBL_MutableRevision* updatedRev = [inRev mutableCopy];
        NSString* prevRevID = history.count >= 2 ? history[1] : nil;
        if (![self processAttachmentsForRevision: updatedRev
                                       prevRevID: prevRevID
                                          status: &status])
        return status;
        inRev = updatedRev;
    }

    NSData* json = inRev.asCanonicalJSON;
    if (!json)
        return kCBLStatusBadJSON;

    __block CBLDatabaseChange* change = nil;

    status = [self _inTransaction: ^CBLStatus {
        // First get the CBForest doc:
        VersionedDocument doc(_forest, docID);

        // Add the revision & ancestry to the doc:
        std::vector<revidBuffer> historyBuffers;
        std::vector<revid> historyVector;
        convertRevIDs(history, historyBuffers, historyVector);
        int common = doc.insertHistory(historyVector,
                                       forestdb::slice(json),
                                       inRev.deleted,
                                       (inRev.attachments != nil));
        if (common < 0)
            return kCBLStatusBadRequest; // generation numbers not in descending order
        else if (common == 0)
            return kCBLStatusOK;      // No-op: No new revisions were inserted.

        // Validate against the common ancestor:
        if (([self.shared hasValuesOfType: @"validation" inDatabaseNamed: _name])) {
            CBL_Revision* prev;
            if ((NSUInteger)common < history.count) {
                BOOL deleted = doc[historyVector[common]]->isDeleted();
                prev = [[CBL_Revision alloc] initWithDocID: docID
                                                     revID: history[common]
                                                   deleted: deleted];
            }
            NSString* parentRevID = (history.count > 1) ? history[1] : nil;
            CBLStatus status = [self validateRevision: rev
                                     previousRevision: prev
                                          parentRevID: parentRevID];
            if (CBLStatusIsError(status))
                return status;
        }

        // Save updated doc back to the database:
        doc.prune((unsigned)self.maxRevTreeDepth);
        doc.save(*_forestTransaction);
#if DEBUG
        LogTo(CBLDatabase, @"Saved %s", doc.dump().c_str());
#endif
        change = [self changeWithNewRevision: inRev
                                isWinningRev: NO // might be, but not known for sure
                                         doc: doc
                                      source: source];
        return kCBLStatusCreated;
    }];

    if (change)
        [self notifyChange: change];
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
    LogTo(CBLDatabase, @"Purging %lu docs...", (unsigned long)docsToRevs.count);
    return [self _inTransaction: ^CBLStatus {
        for (NSString* docID in docsToRevs) {
            VersionedDocument doc(_forest, docID);
            if (!doc.exists())
                return kCBLStatusNotFound;

            NSArray* revsPurged;
            NSArray* revIDs = $castIf(NSArray, docsToRevs[docID]);
            if (!revIDs) {
                return kCBLStatusBadParam;
            } else if (revIDs.count == 0) {
                revsPurged = @[];
            } else if ([revIDs containsObject: @"*"]) {
                // Delete all revisions if magic "*" revision ID is given:
                _forestTransaction->del(doc.docID());
                revsPurged = @[@"*"];
                LogTo(CBLDatabase, @"Purged doc '%@'", docID);
            } else {
                NSMutableArray* purged = $marray();
                for (NSString* revID in revIDs) {
                    if (doc.purge(revidBuffer(revID)) > 0)
                        [purged addObject: revID];
                }
                if (purged.count > 0) {
                    if (doc.allRevisions().size() > 0) {
                        doc.save(*_forestTransaction);
                        LogTo(CBLDatabase, @"Purged doc '%@' revs %@", docID, revIDs);
                    } else {
                        _forestTransaction->del(doc.docID());
                        LogTo(CBLDatabase, @"Purged doc '%@'", docID);
                    }
                }
                revsPurged = purged;
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
    CBLSavedRevision* publicRev;
    publicRev = [[CBLSavedRevision alloc] initForValidationWithDatabase: self
                                                               revision: newRev
                                                       parentRevisionID: parentRevID];
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
