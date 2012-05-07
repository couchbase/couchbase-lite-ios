//
//  TDDatabase+Attachments.m
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

#import "TDDatabase+Attachments.h"
#import "TDDatabase+Insertion.h"
#import "TDBase64.h"
#import "TDBlobStore.h"
#import "TDAttachment.h"
#import "TDBody.h"
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



@implementation TDDatabase (Attachments)


- (TDBlobStoreWriter*) attachmentWriter {
    return [[[TDBlobStoreWriter alloc] initWithStore: _attachments] autorelease];
}


- (void) rememberAttachmentWritersForDigests: (NSDictionary*)blobsByDigests {
    if (!_pendingAttachmentsByDigest)
        _pendingAttachmentsByDigest = [[NSMutableDictionary alloc] init];
    [_pendingAttachmentsByDigest addEntriesFromDictionary: blobsByDigests];
}


// This is ONLY FOR TESTS (see TDMultipartDownloader.m)
#if DEBUG
- (id) attachmentWriterForAttachment: (NSDictionary*)attachment {
    NSString* digest = $castIf(NSString, [attachment objectForKey: @"digest"]);
    if (!digest)
        return nil;
    return [_pendingAttachmentsByDigest objectForKey: digest];
}
#endif


- (TDStatus) installAttachment: (TDAttachment*)attachment
                       forInfo: (NSDictionary*)attachInfo {
    NSString* digest = $castIf(NSString, [attachInfo objectForKey: @"digest"]);
    if (!digest)
        return kTDStatusBadAttachment;
    id writer = [_pendingAttachmentsByDigest objectForKey: digest];

    if ([writer isKindOfClass: [TDBlobStoreWriter class]]) {
        // Found a blob writer, so install the blob:
        if (![writer install])
            return kTDStatusAttachmentError;
        attachment->blobKey = [writer blobKey];
        attachment->length = [writer length];

        // Remove the writer but leave the blob-key behind for future use:
        NSData* keyData = [NSData dataWithBytes: &attachment->blobKey length: sizeof(TDBlobKey)];
        [_pendingAttachmentsByDigest setObject: keyData forKey: digest];
        return kTDStatusOK;
        
    } else if ([writer isKindOfClass: [NSData class]]) {
        // This attachment was already added, but the key was left behind in the dictionary:
        attachment->blobKey = *(TDBlobKey*)[writer bytes];
        NSNumber* lengthObj = $castIf(NSNumber, [attachInfo objectForKey: @"length"]);
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


- (TDStatus) insertAttachment: (TDAttachment*)attachment
                  forSequence: (SequenceNumber)sequence
{
    Assert(sequence > 0);
    Assert(attachment.isValid);
    NSData* keyData = [NSData dataWithBytes: &attachment->blobKey length: sizeof(TDBlobKey)];
    if (attachment->encodedLength > attachment->length)
        Warn(@"Encoded attachment bigger than original: %llu > %llu for key %@",
             attachment->encodedLength, attachment->length, keyData);
    id encodedLengthObj = attachment->encoding ? $object(attachment->encodedLength) : nil;
    if (![_fmdb executeUpdate: @"INSERT INTO attachments "
                                  "(sequence, filename, key, type, encoding, length, encoded_length, revpos) "
                                  "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                                 $object(sequence), attachment.name, keyData,
                                 attachment.contentType, $object(attachment->encoding),
                                 $object(attachment->length), encodedLengthObj,
                                 $object(attachment->revpos)]) {
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
                    $object(toSequence), name,
                    $object(fromSequence), name]) {
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


/** Returns the content and MIME type of an attachment */
- (NSData*) getAttachmentForSequence: (SequenceNumber)sequence
                               named: (NSString*)filename
                                type: (NSString**)outType
                            encoding: (TDAttachmentEncoding*)outEncoding
                              status: (TDStatus*)outStatus
{
    Assert(sequence > 0);
    Assert(filename);
    NSData* contents = nil;
    FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT key, type, encoding FROM attachments WHERE sequence=? AND filename=?",
                      $object(sequence), filename];
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
            Warn(@"%@: Attachment %lld.'%@' has bogus key size %d",
                 self, sequence, filename, keyData.length);
            *outStatus = kTDStatusCorruptError;
            return nil;
        }
        contents = [_attachments blobForKey: *(TDBlobKey*)keyData.bytes];
        if (!contents) {
            Warn(@"%@: Failed to load attachment %lld.'%@'", self, sequence, filename);
            *outStatus = kTDStatusCorruptError;
            return nil;
        }
        *outStatus = kTDStatusOK;
        if (outType)
            *outType = [r stringForColumnIndex: 1];
        
        TDAttachmentEncoding encoding = [r intForColumnIndex: 2];
        if (outEncoding)
            *outEncoding = encoding;
        else
            contents = [self decodeAttachment: contents encoding: encoding];
    } @finally {
        [r close];
    }
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
                      $object(sequence)];
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
                    Warn(@"TDDatabase: Failed to get attachment for key %@", keyData);
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
                encodedLengthObj = $object(encodedLength);
            }
        }

        [attachments setObject: $dict({@"stub", ((data || dataSuppressed) ? nil : $true)},
                                      {@"data", (data ? [TDBase64 encode: data] : nil)},
                                      {@"follows", (dataSuppressed ? $true : nil)},
                                      {@"digest", digestStr},
                                      {@"content_type", [r stringForColumnIndex: 2]},
                                      {@"encoding", encodingStr},
                                      {@"length", $object(length)},
                                      {@"encoded_length", encodedLengthObj},
                                      {@"revpos", $object([r intForColumnIndex: 6])})
                        forKey: [r stringForColumnIndex: 0]];
    } while ([r next]);
    [r close];
    return attachments;
}


- (NSInputStream*) inputStreamForAttachmentDict: (NSDictionary*)attachmentDict
                                         length: (UInt64*)outLength
{
    NSString* digest = [attachmentDict objectForKey: @"digest"];
    if (![digest hasPrefix: @"sha1-"])
        return nil;
    NSData* keyData = [TDBase64 decode: [digest substringFromIndex: 5]];
    if (!keyData)
        return nil;
    return [_attachments blobInputStreamForKey: *(TDBlobKey*)keyData.bytes length: outLength];
}


+ (void) stubOutAttachmentsIn: (TDRevision*)rev
                 beforeRevPos: (int)minRevPos
            attachmentsFollow: (BOOL)attachmentsFollow
{
    if (minRevPos <= 1 && !attachmentsFollow)
        return;
    NSDictionary* properties = rev.properties;
    NSMutableDictionary* editedProperties = nil;
    NSDictionary* attachments = (id)[properties objectForKey: @"_attachments"];
    NSMutableDictionary* editedAttachments = nil;
    for (NSString* name in attachments) {
        NSDictionary* attachment = [attachments objectForKey: name];
        int revPos = [[attachment objectForKey: @"revpos"] intValue];
        bool includeAttachment = (revPos == 0 || revPos >= minRevPos);
        bool stubItOut = !includeAttachment && ![attachment objectForKey: @"stub"];
        bool addFollows = includeAttachment && attachmentsFollow
                                            && ![attachment objectForKey: @"follows"];
        if (stubItOut || addFollows) {
            // Need to modify attachment entry:
            if (!editedProperties) {
                // Make the document properties and _attachments dictionary mutable:
                editedProperties = [[properties mutableCopy] autorelease];
                editedAttachments = [[attachments mutableCopy] autorelease];
                [editedProperties setObject: editedAttachments forKey: @"_attachments"];
            }
            NSMutableDictionary* editedAttachment = [[attachment mutableCopy] autorelease];
            [editedAttachment removeObjectForKey: @"data"];
            if (stubItOut) {
                // ...then remove the 'data' and 'follows' key:
                [editedAttachment removeObjectForKey: @"follows"];
                [editedAttachment setObject: $true forKey: @"stub"];
                LogTo(SyncVerbose, @"Stubbed out attachment %@/'%@': revpos %d < %d",
                      rev, name, revPos, minRevPos);
            } else if (addFollows) {
                [editedAttachment removeObjectForKey: @"stub"];
                [editedAttachment setObject: $true forKey: @"follows"];
                LogTo(SyncVerbose, @"Added 'follows' for attachment %@/'%@': revpos %d >= %d",
                      rev, name, revPos, minRevPos);
            }
            [editedAttachments setObject: editedAttachment forKey: name];
        }
    }
    if (editedProperties)
        rev.properties = editedProperties;
}


- (NSDictionary*) attachmentsFromRevision: (TDRevision*)rev
                                   status: (TDStatus*)outStatus
{
    // If there are no attachments in the new rev, there's nothing to do:
    NSDictionary* revAttachments = [rev.properties objectForKey: @"_attachments"];
    if (revAttachments.count == 0 || rev.deleted) {
        *outStatus = kTDStatusOK;
        return [NSDictionary dictionary];
    }
    
    TDStatus status = kTDStatusOK;
    NSMutableDictionary* attachments = $mdict();
    for (NSString* name in revAttachments) {
        // Create a TDAttachment object:
        NSDictionary* attachInfo = [revAttachments objectForKey: name];
        NSString* contentType = $castIf(NSString, [attachInfo objectForKey: @"content_type"]);
        TDAttachment* attachment = [[[TDAttachment alloc] initWithName: name
                                                           contentType: contentType] autorelease];

        NSString* newContentsBase64 = $castIf(NSString, [attachInfo objectForKey: @"data"]);
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
        } else if ([[attachInfo objectForKey: @"follows"] isEqual: $true]) {
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
        NSString* encodingStr = [attachInfo objectForKey: @"encoding"];
        if (encodingStr) {
            if ($equal(encodingStr, @"gzip"))
                attachment->encoding = kTDAttachmentEncodingGZIP;
            else {
                status = kTDStatusBadEncoding;
                break;
            }
            
            attachment->encodedLength = attachment->length;
            attachment->length = $castIf(NSNumber, [attachInfo objectForKey: @"length"]).unsignedLongLongValue;
        }
        
        attachment->revpos = $castIf(NSNumber, [attachInfo objectForKey: @"revpos"]).unsignedIntValue;
        [attachments setObject: attachment forKey: name];
    }

    *outStatus = status;
    return status<300 ? attachments : nil;
}


- (TDStatus) processAttachments: (NSDictionary*)attachments
                    forRevision: (TDRevision*)rev
             withParentSequence: (SequenceNumber)parentSequence
{
    Assert(rev);
    
    // If there are no attachments in the new rev, there's nothing to do:
    NSDictionary* revAttachments = [rev.properties objectForKey: @"_attachments"];
    if (revAttachments.count == 0 || rev.deleted)
        return kTDStatusOK;
    
    SequenceNumber newSequence = rev.sequence;
    Assert(newSequence > 0);
    Assert(newSequence > parentSequence);
    unsigned generation = rev.generation;
    Assert(generation > 0, @"Missing generation in rev %@", rev);

    for (NSString* name in revAttachments) {
        TDStatus status;
        TDAttachment* attachment = [attachments objectForKey: name];
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


- (TDMultipartWriter*) multipartWriterForRevision: (TDRevision*)rev
                                      contentType: (NSString*)contentType
{
    TDMultipartWriter* writer = [[TDMultipartWriter alloc] initWithContentType: contentType 
                                                                      boundary: nil];
    [writer setNextPartsHeaders: $dict({@"Content-Type", @"application/json"})];
    [writer addData: rev.asJSON];
    NSDictionary* attachments = [rev.properties objectForKey: @"_attachments"];
    for (NSString* attachmentName in attachments) {
        NSDictionary* attachment = [attachments objectForKey: attachmentName];
        if ([attachment objectForKey: @"follows"]) {
            UInt64 length;
            NSInputStream *stream = [self inputStreamForAttachmentDict: attachment length: &length];
            NSString* disposition = $sprintf(@"attachment; filename=%@", TDQuoteString(attachmentName));
            [writer setNextPartsHeaders: $dict({@"Content-Disposition", disposition})];
            [writer addStream: stream length: length];
        }
    }
    return [writer autorelease];
}


- (TDRevision*) updateAttachment: (NSString*)filename
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
    
    [self beginTransaction];
    @try {
        TDRevision* oldRev = [[TDRevision alloc] initWithDocID: docID revID: oldRevID deleted: NO];
        if (oldRevID) {
            // Load existing revision if this is a replacement:
            *outStatus = [self loadRevisionBody: oldRev options: 0];
            if (TDStatusIsError(*outStatus)) {
                if (*outStatus == kTDStatusNotFound && [self existsDocumentWithID: docID revisionID: nil])
                    *outStatus = kTDStatusConflict;   // if some other revision exists, it's a conflict
                return nil;
            }
            NSDictionary* attachments = [oldRev.properties objectForKey: @"_attachments"];
            if (!body && ![attachments objectForKey: filename]) {
                *outStatus = kTDStatusAttachmentNotFound;
                return nil;
            }
            // Remove the _attachments stubs so putRevision: doesn't copy the rows for me
            // OPT: Would be better if I could tell loadRevisionBody: not to add it
            if (attachments) {
                NSMutableDictionary* properties = [oldRev.properties mutableCopy];
                [properties removeObjectForKey: @"_attachments"];
                oldRev.body = [TDBody bodyWithProperties: properties];
                [properties release];
            }
        } else {
            // If this creates a new doc, it needs a body:
            oldRev.body = [TDBody bodyWithProperties: $dict()];
        }
        
        // Create a new revision:
        TDRevision* newRev = [self putRevision: oldRev prevRevisionID: oldRevID
                                 allowConflict: NO status: outStatus];
        if (!newRev)
            return nil;
        
        if (oldRevID) {
            // Copy all attachment rows _except_ for the one being updated:
            if (![_fmdb executeUpdate: @"INSERT INTO attachments "
                    "(sequence, filename, key, type, encoding, encoded_length, length, revpos) "
                    "SELECT ?, filename, key, type, encoding, encoded_length, length, revpos "
                    "FROM attachments WHERE sequence=? AND filename != ?",
                                        $object(newRev.sequence), $object(oldRev.sequence),
                                        filename]) {
                *outStatus = kTDStatusDBError;
                return nil;
            }
        }
        
        if (body) {
            // If not deleting, add a new attachment entry:
            TDAttachment* attachment = [[TDAttachment alloc] initWithName: filename
                                                              contentType: contentType];
            [attachment autorelease];
            attachment->length = body.length;
            attachment->encoding = encoding;
            attachment->revpos = newRev.generation;
            if (encoding) {
                attachment->encodedLength = attachment->length;
                attachment->length = [self decodeAttachment: body encoding: encoding].length;
                if (attachment->length == 0 && attachment->encodedLength > 0) {
                    *outStatus = kTDStatusBadEncoding;     // failed to decode
                    return nil;
                }
            }
            
            if (![self storeBlob: body creatingKey: &attachment->blobKey]) {
                *outStatus = kTDStatusAttachmentError;
                return nil;
            }
            
            *outStatus = [self insertAttachment: attachment forSequence: newRev.sequence];
            if (TDStatusIsError(*outStatus))
                return nil;
        }
        
        *outStatus = body ? kTDStatusCreated : kTDStatusOK;
        return newRev;
    } @finally {
        [self endTransaction: (*outStatus < 300)];
    }
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
    Log(@"Deleted %d attachments", numDeleted);
    return kTDStatusOK;
}


@end
