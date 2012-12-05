//
//  TD_Database+Attachments.m
//  TouchDB
//
//  Created by Jens Alfke on 12/19/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
//  http://wiki.apache.org/couchdb/HTTP_Document_API#Attachments

/*
    Here's what an actual _attachments object from CouchDB 1.2 looks like.
    The "revpos" and "digest" attributes aren't documented in the wiki (yet).
 
    "_attachments":{
        "index.txt":{"content_type":"text/plain", "revpos":1,
                     "digest":"md5-muNoTiLXyJYP9QkvPukNng==", "length":9, "stub":true}}
*/

#import "TD_Database+Attachments.h"
#import "TD_Database+Insertion.h"
#import "TDBase64.h"
#import "TDBlobStore.h"
#import "TD_Attachment.h"
#import "TD_Body.h"
#import "TDMultipartWriter.h"
#import "TDMisc.h"
#import "TDInternal.h"

#import "CollectionUtils.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"
#import "GTMNSData+zlib.h"


// Length that constitutes a 'big' attachment
#define kBigAttachmentLength (16*1024)



@implementation TD_Database (Attachments)


- (TDBlobStoreWriter*) attachmentWriter {
    return [[TDBlobStoreWriter alloc] initWithStore: _attachments];
}


- (void) rememberAttachmentWritersForDigests: (NSDictionary*)blobsByDigests {
    if (!_pendingAttachmentsByDigest)
        _pendingAttachmentsByDigest = [[NSMutableDictionary alloc] init];
    [_pendingAttachmentsByDigest addEntriesFromDictionary: blobsByDigests];
}


- (void) rememberPendingKey: (TDBlobKey)key forDigest: (NSString*)digest {
    if (!_pendingAttachmentsByDigest)
        _pendingAttachmentsByDigest = [[NSMutableDictionary alloc] init];
    NSData* keyData = [NSData dataWithBytes: &key length: sizeof(TDBlobKey)];
    _pendingAttachmentsByDigest[digest] = keyData;
}


// This is ONLY FOR TESTS (see TDMultipartDownloader.m)
#if DEBUG
- (id) attachmentWriterForAttachment: (NSDictionary*)attachment {
    NSString* digest = $castIf(NSString, attachment[@"digest"]);
    if (!digest)
        return nil;
    return _pendingAttachmentsByDigest[digest];
}
#endif


- (TDStatus) installAttachment: (TD_Attachment*)attachment
                       forInfo: (NSDictionary*)attachInfo {
    NSString* digest = $castIf(NSString, attachInfo[@"digest"]);
    if (!digest)
        return kTDStatusBadAttachment;
    id writer = _pendingAttachmentsByDigest[digest];

    if ([writer isKindOfClass: [TDBlobStoreWriter class]]) {
        // Found a blob writer, so install the blob:
        if (![writer install])
            return kTDStatusAttachmentError;
        attachment->blobKey = [writer blobKey];
        attachment->length = [writer length];
        // Remove the writer but leave the blob-key behind for future use:
        [self rememberPendingKey: attachment->blobKey forDigest: digest];
        return kTDStatusOK;
        
    } else if ([writer isKindOfClass: [NSData class]]) {
        // This attachment was already added, but the key was left behind in the dictionary:
        attachment->blobKey = *(TDBlobKey*)[writer bytes];
        NSNumber* lengthObj = $castIf(NSNumber, attachInfo[@"length"]);
        if (!lengthObj)
            return kTDStatusBadAttachment;
        attachment->length = lengthObj.unsignedLongLongValue;
        return kTDStatusOK;
        
    } else {
        return kTDStatusBadAttachment;
    }
}


- (BOOL) storeBlob: (NSData*)blob creatingKey: (TDBlobKey*)outKey {
    return [_attachments storeBlob: blob creatingKey: outKey];
}


- (TDStatus) insertAttachment: (TD_Attachment*)attachment
                  forSequence: (SequenceNumber)sequence
{
    Assert(sequence > 0);
    Assert(attachment.isValid);
    NSData* keyData = [NSData dataWithBytes: &attachment->blobKey length: sizeof(TDBlobKey)];
    id encodedLengthObj = attachment->encoding ? @(attachment->encodedLength) : nil;
    if (![_fmdb executeUpdate: @"INSERT INTO attachments "
                                  "(sequence, filename, key, type, encoding, length, encoded_length, revpos) "
                                  "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                                 @(sequence), attachment.name, keyData,
                                 attachment.contentType, @(attachment->encoding),
                                 @(attachment->length), encodedLengthObj,
                                 @(attachment->revpos)]) {
        return kTDStatusDBError;
    }
    return kTDStatusCreated;
}


- (TDStatus) copyAttachmentNamed: (NSString*)name
                    fromSequence: (SequenceNumber)fromSequence
                      toSequence: (SequenceNumber)toSequence
{
    Assert(name);
    Assert(toSequence > 0);
    Assert(toSequence > fromSequence);
    if (fromSequence <= 0)
        return kTDStatusNotFound;
    if (![_fmdb executeUpdate: @"INSERT INTO attachments "
                    "(sequence, filename, key, type, encoding, encoded_Length, length, revpos) "
                    "SELECT ?, ?, key, type, encoding, encoded_Length, length, revpos "
                        "FROM attachments WHERE sequence=? AND filename=?",
                    @(toSequence), name,
                    @(fromSequence), name]) {
        return kTDStatusDBError;
    }
    if (_fmdb.changes == 0) {
        // Oops. This means a glitch in our attachment-management or pull code,
        // or else a bug in the upstream server.
        Warn(@"Can't find inherited attachment '%@' from seq#%lld to copy to #%lld",
             name, fromSequence, toSequence);
        return kTDStatusNotFound;         // Fail if there is no such attachment on fromSequence
    }
    return kTDStatusOK;
}


- (NSData*) decodeAttachment: (NSData*)attachment encoding: (TDAttachmentEncoding)encoding {
    switch (encoding) {
        case kTDAttachmentEncodingNone:
            break;
        case kTDAttachmentEncodingGZIP:
            attachment = [NSData gtm_dataByInflatingData: attachment];
    }
    if (!attachment)
        Warn(@"Unable to decode attachment!");
    return attachment;
}


/** Returns the location of an attachment's file in the blob store. */
- (NSString*) getAttachmentPathForSequence: (SequenceNumber)sequence
                                     named: (NSString*)filename
                                      type: (NSString**)outType
                                  encoding: (TDAttachmentEncoding*)outEncoding
                                    status: (TDStatus*)outStatus
{
    Assert(sequence > 0);
    Assert(filename);
    NSString* filePath = nil;
    FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT key, type, encoding FROM attachments WHERE sequence=? AND filename=?",
                      @(sequence), filename];
    if (!r) {
        *outStatus = kTDStatusDBError;
        return nil;
    }
    @try {
        if (![r next]) {
            *outStatus = kTDStatusNotFound;
            return nil;
        }
        NSData* keyData = [r dataNoCopyForColumnIndex: 0];
        if (keyData.length != sizeof(TDBlobKey)) {
            Warn(@"%@: Attachment %lld.'%@' has bogus key size %u",
                 self, sequence, filename, (unsigned)keyData.length);
            *outStatus = kTDStatusCorruptError;
            return nil;
        }
        filePath = [_attachments pathForKey: *(TDBlobKey*)keyData.bytes];
        *outStatus = kTDStatusOK;
        if (outType)
            *outType = [r stringForColumnIndex: 1];
        
        *outEncoding = [r intForColumnIndex: 2];
    } @finally {
        [r close];
    }
    return filePath;
}


/** Returns the content and MIME type of an attachment */
- (NSData*) getAttachmentForSequence: (SequenceNumber)sequence
                               named: (NSString*)filename
                                type: (NSString**)outType
                            encoding: (TDAttachmentEncoding*)outEncoding
                              status: (TDStatus*)outStatus
{
    TDAttachmentEncoding encoding;
    NSString* filePath = [self getAttachmentPathForSequence: sequence
                                                      named: filename
                                                       type: outType
                                                   encoding: &encoding
                                                     status: outStatus];
    if (!filePath)
        return nil;
    NSError* error;
    NSData* contents = [NSData dataWithContentsOfFile: filePath options: NSDataReadingMappedIfSafe
                                                error: &error];
    if (!contents) {
        Warn(@"%@: Failed to load attachment %lld.'%@' -- %@", self, sequence, filename, error);
        *outStatus = kTDStatusCorruptError;
        return nil;
    }
    if (outEncoding)
        *outEncoding = encoding;
    else
        contents = [self decodeAttachment: contents encoding: encoding];
    return contents;
}


/** Constructs an "_attachments" dictionary for a revision, to be inserted in its JSON body. */
- (NSDictionary*) getAttachmentDictForSequence: (SequenceNumber)sequence
                                       options: (TDContentOptions)options
{
    Assert(sequence > 0);
    FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT filename, key, type, encoding, length, encoded_length, revpos "
                       "FROM attachments WHERE sequence=?",
                      @(sequence)];
    if (!r)
        return nil;
    if (![r next]) {
        [r close];
        return nil;
    }
    BOOL decodeAttachments = !(options & kTDLeaveAttachmentsEncoded);
    NSMutableDictionary* attachments = $mdict();
    do {
        NSData* keyData = [r dataNoCopyForColumnIndex: 1];
        NSString* digestStr = [@"sha1-" stringByAppendingString: [TDBase64 encode: keyData]];
        TDAttachmentEncoding encoding = [r intForColumnIndex: 3];
        UInt64 length = [r longLongIntForColumnIndex: 4];
        UInt64 encodedLength = [r longLongIntForColumnIndex: 5];
        
        // Get the attachment contents if asked to:
        NSData* data = nil;
        BOOL dataSuppressed = NO;
        if (options & kTDIncludeAttachments) {
            UInt64 effectiveLength = (encoding && !decodeAttachments) ? encodedLength : length;
            if ((options & kTDBigAttachmentsFollow) && effectiveLength >= kBigAttachmentLength) {
                dataSuppressed = YES;
            } else {
                data = [_attachments blobForKey: *(TDBlobKey*)keyData.bytes];
                if (!data)
                    Warn(@"TD_Database: Failed to get attachment for key %@", keyData);
            }
        }
        
        NSString* encodingStr = nil;
        id encodedLengthObj = nil;
        if (encoding != kTDAttachmentEncodingNone) {
            // Decode the attachment if it's included in the dict:
            if (data && decodeAttachments) {
                data = [self decodeAttachment: data encoding: encoding];
            } else {
                encodingStr = @"gzip";  // the only encoding I know
                encodedLengthObj = @(encodedLength);
            }
        }

        attachments[[r stringForColumnIndex: 0]] = $dict({@"stub", ((data || dataSuppressed) ? nil : $true)},
                                      {@"data", (data ? [TDBase64 encode: data] : nil)},
                                      {@"follows", (dataSuppressed ? $true : nil)},
                                      {@"digest", digestStr},
                                      {@"content_type", [r stringForColumnIndex: 2]},
                                      {@"encoding", encodingStr},
                                      {@"length", @(length)},
                                      {@"encoded_length", encodedLengthObj},
                                      {@"revpos", @([r intForColumnIndex: 6])});
    } while ([r next]);
    [r close];
    return attachments;
}


- (NSURL*) fileForAttachmentDict: (NSDictionary*)attachmentDict
{
    NSString* digest = attachmentDict[@"digest"];
    if (![digest hasPrefix: @"sha1-"])
        return nil;
    NSData* keyData = [TDBase64 decode: [digest substringFromIndex: 5]];
    if (!keyData)
        return nil;
    return [NSURL fileURLWithPath: [_attachments pathForKey: *(TDBlobKey*)keyData.bytes]];
}


// Calls the block on every attachment dictionary. The block can return a different dictionary,
// which will be replaced in the rev's properties. If it returns nil, the operation aborts.
// Returns YES if any changes were made.
+ (BOOL) mutateAttachmentsIn: (TD_Revision*)rev
                   withBlock: (NSDictionary*(^)(NSString*, NSDictionary*))block
{
    NSDictionary* properties = rev.properties;
    NSMutableDictionary* editedProperties = nil;
    NSDictionary* attachments = (id)properties[@"_attachments"];
    NSMutableDictionary* editedAttachments = nil;
    for (NSString* name in attachments) {
        @autoreleasepool {
            NSDictionary* attachment = attachments[name];
            NSDictionary* editedAttachment = block(name, attachment);
            if (!editedAttachment) {
                return NO;  // block canceled
            }
            if (editedAttachment != attachment) {
                if (!editedProperties) {
                    // Make the document properties and _attachments dictionary mutable:
                    editedProperties = [properties mutableCopy];
                    editedAttachments = [attachments mutableCopy];
                    editedProperties[@"_attachments"] = editedAttachments;
                }
                editedAttachments[name] = editedAttachment;
            }
        }
    }
    if (editedProperties) {
        rev.properties = editedProperties;
        return YES;
    }
    return NO;
}


// Replaces attachment data whose revpos is < minRevPos with stubs.
// If attachmentsFollow==YES, replaces data with "follows" key.
+ (void) stubOutAttachmentsIn: (TD_Revision*)rev
                 beforeRevPos: (int)minRevPos
            attachmentsFollow: (BOOL)attachmentsFollow
{
    if (minRevPos <= 1 && !attachmentsFollow)
        return;
    [self mutateAttachmentsIn: rev
                    withBlock: ^NSDictionary *(NSString *name, NSDictionary *attachment) {
        int revPos = [attachment[@"revpos"] intValue];
        bool includeAttachment = (revPos == 0 || revPos >= minRevPos);
        bool stubItOut = !includeAttachment && !attachment[@"stub"];
        bool addFollows = includeAttachment && attachmentsFollow
                                            && !attachment[@"follows"];
        if (!stubItOut && !addFollows)
            return attachment;  // no change
        // Need to modify attachment entry:
        NSMutableDictionary* editedAttachment = [attachment mutableCopy];
        [editedAttachment removeObjectForKey: @"data"];
        if (stubItOut) {
            // ...then remove the 'data' and 'follows' key:
            [editedAttachment removeObjectForKey: @"follows"];
            editedAttachment[@"stub"] = $true;
            LogTo(SyncVerbose, @"Stubbed out attachment %@/'%@': revpos %d < %d",
                  rev, name, revPos, minRevPos);
        } else if (addFollows) {
            [editedAttachment removeObjectForKey: @"stub"];
            editedAttachment[@"follows"] = $true;
            LogTo(SyncVerbose, @"Added 'follows' for attachment %@/'%@': revpos %d >= %d",
                  rev, name, revPos, minRevPos);
        }
        return editedAttachment;
    }];
}


// Replaces the "follows" key with the real attachment data in all attachments to 'doc'.
- (BOOL) inlineFollowingAttachmentsIn: (TD_Revision*)rev error: (NSError**)outError {
    __block NSError *error = nil;
    [[self class] mutateAttachmentsIn: rev
                            withBlock:
        ^NSDictionary *(NSString *name, NSDictionary *attachment) {
            if (!attachment[@"follows"])
                return attachment;
            NSURL* fileURL = [self fileForAttachmentDict: attachment];
            NSData* fileData = [NSData dataWithContentsOfURL: fileURL
                                                     options: NSDataReadingMappedIfSafe
                                                       error: &error];
            if (!fileData)
                return nil;
            NSMutableDictionary* editedAttachment = [attachment mutableCopy];
            [editedAttachment removeObjectForKey: @"follows"];
            editedAttachment[@"data"] = [TDBase64 encode: fileData];
            return editedAttachment;
        }
     ];
    if (outError)
        *outError = error;
    return (error == nil);
}


- (NSDictionary*) attachmentsFromRevision: (TD_Revision*)rev
                                   status: (TDStatus*)outStatus
{
    // If there are no attachments in the new rev, there's nothing to do:
    NSDictionary* revAttachments = rev[@"_attachments"];
    if (revAttachments.count == 0 || rev.deleted) {
        *outStatus = kTDStatusOK;
        return @{};
    }
    
    TDStatus status = kTDStatusOK;
    NSMutableDictionary* attachments = $mdict();
    for (NSString* name in revAttachments) {
        // Create a TD_Attachment object:
        NSDictionary* attachInfo = revAttachments[name];
        NSString* contentType = $castIf(NSString, attachInfo[@"content_type"]);
        TD_Attachment* attachment = [[TD_Attachment alloc] initWithName: name
                                                           contentType: contentType];

        NSString* newContentsBase64 = $castIf(NSString, attachInfo[@"data"]);
        if (newContentsBase64) {
            // If there's inline attachment data, decode and store it:
            @autoreleasepool {
                NSData* newContents = [TDBase64 decode: newContentsBase64];
                if (!newContents) {
                    status = kTDStatusBadEncoding;
                    break;
                }
                attachment->length = newContents.length;
                if (![self storeBlob: newContents creatingKey: &attachment->blobKey]) {
                    status = kTDStatusAttachmentError;
                    break;
                }
            }
        } else if ([attachInfo[@"follows"] isEqual: $true]) {
            // "follows" means the uploader provided the attachment in a separate MIME part.
            // This means it's already been registered in _pendingAttachmentsByDigest;
            // I just need to look it up by its "digest" property and install it into the store:
            status = [self installAttachment: attachment forInfo: attachInfo];
            if (TDStatusIsError(status))
                break;
        } else {
            // This item is just a stub; skip it
            continue;
        }
        
        // Handle encoded attachment:
        NSString* encodingStr = attachInfo[@"encoding"];
        if (encodingStr) {
            if ($equal(encodingStr, @"gzip"))
                attachment->encoding = kTDAttachmentEncodingGZIP;
            else {
                status = kTDStatusBadEncoding;
                break;
            }
            
            attachment->encodedLength = attachment->length;
            attachment->length = $castIf(NSNumber, attachInfo[@"length"]).unsignedLongLongValue;
        }
        
        attachment->revpos = $castIf(NSNumber, attachInfo[@"revpos"]).unsignedIntValue;
        attachments[name] = attachment;
    }

    *outStatus = status;
    return status<300 ? attachments : nil;
}


- (TDStatus) processAttachments: (NSDictionary*)attachments
                    forRevision: (TD_Revision*)rev
             withParentSequence: (SequenceNumber)parentSequence
{
    Assert(rev);
    
    // If there are no attachments in the new rev, there's nothing to do:
    NSDictionary* revAttachments = rev[@"_attachments"];
    if (revAttachments.count == 0 || rev.deleted)
        return kTDStatusOK;
    
    SequenceNumber newSequence = rev.sequence;
    Assert(newSequence > 0);
    Assert(newSequence > parentSequence);
    unsigned generation = rev.generation;
    Assert(generation > 0, @"Missing generation in rev %@", rev);

    for (NSString* name in revAttachments) {
        TDStatus status;
        TD_Attachment* attachment = attachments[name];
        if (attachment) {
            // Determine the revpos, i.e. generation # this was added in. Usually this is
            // implicit, but a rev being pulled in replication will have it set already.
            if (attachment->revpos == 0)
                attachment->revpos = generation;
            else if (attachment->revpos > generation)
                return kTDStatusBadAttachment;

            // Finally insert the attachment:
            status = [self insertAttachment: attachment forSequence: newSequence];
        } else {
            // It's just a stub, so copy the previous revision's attachment entry:
            //? Should I enforce that the type and digest (if any) match?
            status = [self copyAttachmentNamed: name
                                  fromSequence: parentSequence
                                    toSequence: newSequence];
        }
        if (TDStatusIsError(status))
            return status;
    }
    return kTDStatusOK;
}


- (TDMultipartWriter*) multipartWriterForRevision: (TD_Revision*)rev
                                      contentType: (NSString*)contentType
{
    TDMultipartWriter* writer = [[TDMultipartWriter alloc] initWithContentType: contentType 
                                                                      boundary: nil];
    [writer setNextPartsHeaders: @{@"Content-Type": @"application/json"}];
    [writer addData: rev.asJSON];
    NSDictionary* attachments = rev[@"_attachments"];
    for (NSString* attachmentName in attachments) {
        NSDictionary* attachment = attachments[attachmentName];
        if (attachment[@"follows"]) {
            NSString* disposition = $sprintf(@"attachment; filename=%@", TDQuoteString(attachmentName));
            [writer setNextPartsHeaders: $dict({@"Content-Disposition", disposition})];
            [writer addFileURL: [self fileForAttachmentDict: attachment]];
        }
    }
    return writer;
}


- (TD_Revision*) updateAttachment: (NSString*)filename
                            body: (NSData*)body
                            type: (NSString*)contentType
                        encoding: (TDAttachmentEncoding)encoding
                         ofDocID: (NSString*)docID
                           revID: (NSString*)oldRevID
                          status: (TDStatus*)outStatus
{
    *outStatus = kTDStatusBadAttachment;
    if (filename.length == 0 || (body && !contentType) || (oldRevID && !docID) || (body && !docID))
        return nil;

    TD_Revision* oldRev = [[TD_Revision alloc] initWithDocID: docID
                                                      revID: oldRevID
                                                    deleted: NO];
    if (oldRevID) {
        // Load existing revision if this is a replacement:
        *outStatus = [self loadRevisionBody: oldRev options: 0];
        if (TDStatusIsError(*outStatus)) {
            if (*outStatus == kTDStatusNotFound && [self existsDocumentWithID: docID revisionID: nil])
                *outStatus = kTDStatusConflict;   // if some other revision exists, it's a conflict
            return nil;
        }
    } else {
        // If this creates a new doc, it needs a body:
        oldRev.body = [TD_Body bodyWithProperties: @{}];
    }

    // Update the _attachments dictionary:
    NSMutableDictionary* attachments = [oldRev[@"_attachments"] mutableCopy];
    if (!attachments)
        attachments = $mdict();
    if (body) {
        TDBlobKey key;
        if (![self storeBlob: body creatingKey: &key]) {
            *outStatus = kTDStatusAttachmentError;
            return nil;
        }
        NSString* digest = [@"sha1-" stringByAppendingString: [TDBase64 encode: &key
                                                                        length: sizeof(key)]];
        [self rememberPendingKey: key forDigest: digest];
        NSString* encodingName = (encoding == kTDAttachmentEncodingGZIP) ? @"gzip" : nil;
        attachments[filename] = $dict({@"digest", digest},
                                      {@"length", @(body.length)},
                                      {@"follows", $true},
                                      {@"content_type", contentType},
                                      {@"encoding", encodingName});
    } else {
        if (!attachments[filename]) {
            *outStatus = kTDStatusAttachmentNotFound;
            return nil;
        }
        [attachments removeObjectForKey: filename];
    }
    NSMutableDictionary* properties = [oldRev.properties mutableCopy];
    properties[@"_attachments"] = attachments;
    oldRev.properties = properties;

    // Store a new revision with the updated _attachments:
    TD_Revision* newRev = [self putRevision: oldRev prevRevisionID: oldRevID
                             allowConflict: NO status: outStatus];
    if (!body && *outStatus == kTDStatusCreated)
        *outStatus = kTDStatusOK;
    return newRev;
}


- (TDStatus) garbageCollectAttachments {
    // First delete attachment rows for already-cleared revisions:
    // OPT: Could start after last sequence# we GC'd up to
    [_fmdb executeUpdate:  @"DELETE FROM attachments WHERE sequence IN "
                            "(SELECT sequence from revs WHERE json IS null)"];
    
    // Now collect all remaining attachment IDs and tell the store to delete all but these:
    FMResultSet* r = [_fmdb executeQuery: @"SELECT DISTINCT key FROM attachments"];
    if (!r)
        return kTDStatusDBError;
    NSMutableSet* allKeys = [NSMutableSet set];
    while ([r next]) {
        [allKeys addObject: [r dataForColumnIndex: 0]];
    }
    [r close];
    NSInteger numDeleted = [_attachments deleteBlobsExceptWithKeys: allKeys];
    if (numDeleted < 0)
        return kTDStatusAttachmentError;
    Log(@"Deleted %d attachments", (int)numDeleted);
    return kTDStatusOK;
}


@end
