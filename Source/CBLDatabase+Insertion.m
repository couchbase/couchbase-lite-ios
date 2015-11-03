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
#import "CBLInternal.h"
#import "CBLDocument.h"
#import "CBL_Revision.h"
#import "CBL_Attachment.h"
#import "CBLDatabaseChange.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "Test.h"
#import "ExceptionUtils.h"


#ifdef GNUSTEP
#import <openssl/sha.h>
#else
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>
#endif


@interface CBLValidationContext : NSObject <CBLValidationContext>
- (instancetype) initWithDatabase: (CBLDatabase*)db
                         revision: (CBL_Revision*)currentRevision
                      newRevision: (CBL_Revision*)newRevision
                           source: (NSURL*)source;
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
- (NSString*) _generateRevIDForJSON: (NSData*)json
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


#if DEBUG // for tests only
- (CBL_Revision*) putRevision: (CBL_MutableRevision*)putRev
               prevRevisionID: (NSString*)inPrevRevID
                allowConflict: (BOOL)allowConflict
                       status: (CBLStatus*)outStatus
                        error: (NSError**)outError
{
    return [self putDocID: putRev.docID properties: [putRev.properties mutableCopy]
           prevRevisionID: inPrevRevID allowConflict: allowConflict
                   source: nil
                   status: outStatus error: outError];
}
#endif


- (CBL_Revision*) putDocID: (NSString*)inDocID
                properties: (NSMutableDictionary*)properties
            prevRevisionID: (NSString*)inPrevRevID
             allowConflict: (BOOL)allowConflict
                    source: (NSURL*)source
                    status: (CBLStatus*)outStatus
                     error: (NSError**)outError
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
        CBLStatusToOutNSError(*outStatus, outError);
        return nil;
    }

    if (properties.cbl_attachments) {
        // Add any new attachment data to the blob-store, and turn all of them into stubs:
        //FIX: Optimize this to avoid creating a revision object
        NSString* tmpRevID = $sprintf(@"%d-00", [CBL_Revision generationFromRevID: prevRevID] + 1);
        CBL_MutableRevision* tmpRev = [[CBL_MutableRevision alloc] initWithDocID: (docID ?: @"x")
                                                                           revID: tmpRevID
                                                                         deleted: deleting];
        tmpRev.properties = properties;
        if (![self processAttachmentsForRevision: tmpRev
                                        ancestry: (prevRevID ? @[prevRevID] : nil)
                                          status: outStatus]) {
            CBLStatusToOutNSError(*outStatus, outError);
            return nil;
        }
        properties = [tmpRev.properties mutableCopy];
    }

    CBL_StorageValidationBlock validationBlock = nil;
    if ([self.shared hasValuesOfType: @"validation" inDatabaseNamed: _name]) {
        validationBlock = ^(CBL_Revision* rev, CBL_Revision* prev, NSString* parentRevID, NSError** outError) {
            return [self validateRevision: rev
                         previousRevision: prev
                              parentRevID: parentRevID
                                   source: nil
                                    error: outError];
        };
    }

    CBL_Revision* putRev = [_storage addDocID: inDocID
                                    prevRevID: inPrevRevID
                                   properties: properties
                                     deleting: deleting
                                allowConflict: allowConflict
                              validationBlock: validationBlock
                                       status: outStatus
                                        error: outError];
    if (putRev) {
        LogTo(CBLDatabase, @"--> created %@", putRev);
    }
    return putRev;
}


/** Add an existing revision of a document (probably being pulled) plus its ancestors. */
- (CBLStatus) forceInsert: (CBL_Revision*)inRev
          revisionHistory: (NSArray*)history  // in *reverse* order, starting with rev's revID
                   source: (NSURL*)source
                    error: (NSError**)outError
{
    CBL_MutableRevision* rev = inRev.mutableCopy;
    rev.sequence = 0;
    NSString* revID = rev.revID;
    if (![CBLDatabase isValidDocumentID: rev.docID] || !revID) {
        CBLStatusToOutNSError(kCBLStatusBadID, outError);
        return kCBLStatusBadID;
    }
    
    if (history.count == 0)
        history = @[revID];
    else if (!$equal(history[0], revID)) {
        // If inRev's revID doesn't appear in history, add it at the start:
        NSMutableArray* nuHistory = [history mutableCopy];
        [nuHistory insertObject: revID atIndex: 0];
        history = nuHistory;
    }

    CBLStatus status;
    if (inRev.attachments) {
        CBL_MutableRevision* updatedRev = [inRev mutableCopy];
        NSArray* ancestry = [history subarrayWithRange: NSMakeRange(1, history.count-1)];
        if (![self processAttachmentsForRevision: updatedRev
                                        ancestry: ancestry
                                          status: &status]) {
            CBLStatusToOutNSError(status, outError);
            return status;
        }
        inRev = updatedRev;
    }

    CBL_StorageValidationBlock validationBlock = nil;
    if ([self.shared hasValuesOfType: @"validation" inDatabaseNamed: _name]) {
        validationBlock = ^(CBL_Revision* newRev, CBL_Revision* prev, NSString* parentRevID,
                            NSError** outError) {
            return [self validateRevision: newRev
                         previousRevision: prev
                              parentRevID: parentRevID
                                   source: source
                                    error: outError];
        };
    }

    return [_storage forceInsert: inRev
                 revisionHistory: history
                 validationBlock: validationBlock
                          source: source
                           error: outError];
}


- (BOOL) forceInsertRevisionWithJSON: (NSData*)json
                     revisionHistory: (NSArray*)history
                              source: (NSURL*)source
                               error: (NSError**)outError
{
    CBL_Body* body = [CBL_Body bodyWithJSON: json];
    if (body) {
        CBL_Revision* rev = [[CBL_Revision alloc] initWithBody: body];
        if (rev) {
            CBLStatus status = [self forceInsert: rev revisionHistory: history source: source
                                           error: outError];
            return !CBLStatusIsError(status);
        }
    }
    return CBLStatusToOutNSError(kCBLStatusBadJSON, outError);
}


#pragma mark - VALIDATION:


- (CBLStatus) validateRevision: (CBL_Revision*)newRev
              previousRevision: (CBL_Revision*)oldRev
                   parentRevID: (NSString*)parentRevID
                        source: (NSURL*)source
                         error: (NSError**)outError
{
    if (outError)
        *outError = nil;
    
    NSDictionary* validations = [self.shared valuesOfType: @"validation" inDatabaseNamed: _name];
    if (validations.count == 0)
        return kCBLStatusOK;
    CBLSavedRevision* publicRev;
    publicRev = [[CBLSavedRevision alloc] initForValidationWithDatabase: self
                                                               revision: newRev
                                                       parentRevisionID: parentRevID];
    CBLValidationContext* context = [[CBLValidationContext alloc] initWithDatabase: self
                                                                          revision: oldRev
                                                                       newRevision: newRev
                                                                            source: source];
    CBLStatus status = kCBLStatusOK;
    for (NSString* validationName in validations) {
        CBLValidationBlock validation = [self validationNamed: validationName];
        @try {
            validation(publicRev, context);
        } @catch (NSException* x) {
            MYReportException(x, @"validation block '%@'", validationName);
            status = kCBLStatusCallbackError;
            CBLStatusToOutNSError(status, outError);
            break;
        }
        if (context.rejectionMessage != nil) {
            LogTo(CBLValidation, @"Failed update of %@: %@:\n  Old doc = %@\n  New doc = %@",
                  oldRev, context.rejectionMessage, oldRev.properties, newRev.properties);
            status = kCBLStatusForbidden;
            if (outError)
                *outError = CBLStatusToNSErrorWithInfo(status, context.rejectionMessage, nil, nil);
            break;
        }
    }
    
    return status;
}


@end






@implementation CBLValidationContext
{
@private
    CBLDatabase* _db;
    CBL_Revision* _currentRevision, *_newRevision;
    NSURL* _source;
    int _errorType;
    NSString* _errorMessage;
    NSArray* _changedKeys;
}

- (instancetype) initWithDatabase: (CBLDatabase*)db
                         revision: (CBL_Revision*)currentRevision
                      newRevision: (CBL_Revision*)newRevision
                           source: (NSURL*)source
{
    self = [super init];
    if (self) {
        _db = db;
        _currentRevision = currentRevision;
        _newRevision = newRevision;
        _source = source;
        _errorType = kCBLStatusForbidden;
        _errorMessage = @"invalid document";
    }
    return self;
}


@synthesize rejectionMessage=_rejectionMessage, source=_source;


- (CBL_Revision*) current_Revision {
    if (_currentRevision)
        _currentRevision = [_db revisionByLoadingBody: _currentRevision status: NULL];
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
