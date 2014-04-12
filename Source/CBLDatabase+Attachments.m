//
//  CBLDatabase+Attachments.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/19/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
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

#import "CBLDatabase+Attachments.h"
#import "CBLDatabase+Insertion.h"
#import "CBLBase64.h"
#import "CBL_BlobStore.h"
#import "CBL_Attachment.h"
#import "CBL_Body.h"
#import "CBLMultipartWriter.h"
#import "CBLMisc.h"
#import "CBLInternal.h"

#import "CollectionUtils.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"
#import "GTMNSData+zlib.h"


// Length that constitutes a 'big' attachment
#define kBigAttachmentLength (16*1024)


static NSString* blobKeyToDigest(CBLBlobKey key) {
    return [@"sha1-" stringByAppendingString: [CBLBase64 encode: &key length: sizeof(key)]];
}

static bool digestToBlobKey(NSString* digest, CBLBlobKey* key) {
    if (![digest hasPrefix: @"sha1-"])
        return false;
    NSData* keyData = [CBLBase64 decode: [digest substringFromIndex: 5]];
    if (!keyData || keyData.length != sizeof(CBLBlobKey))
        return nil;
    *key = *(CBLBlobKey*)keyData.bytes;
    return true;
}


@implementation CBLDatabase (Attachments)


+ (NSString*) attachmentStorePath: (NSString*)dbPath {
    return [[dbPath stringByDeletingPathExtension] stringByAppendingString: @" attachments"];

}


- (NSString*) attachmentStorePath {
    return [[self class] attachmentStorePath: _path];
}


- (CBL_BlobStoreWriter*) attachmentWriter {
    return [[CBL_BlobStoreWriter alloc] initWithStore: _attachments];
}


- (void) rememberAttachmentWriter: (CBL_BlobStoreWriter*)writer {
    if (!_pendingAttachmentsByDigest)
        _pendingAttachmentsByDigest = [[NSMutableDictionary alloc] init];
    _pendingAttachmentsByDigest[writer.MD5DigestString] = writer;
}


- (void) rememberAttachmentWritersForDigests: (NSDictionary*)blobsByDigests {
    if (!_pendingAttachmentsByDigest)
        _pendingAttachmentsByDigest = [[NSMutableDictionary alloc] init];
    [_pendingAttachmentsByDigest addEntriesFromDictionary: blobsByDigests];
}


- (void) rememberPendingKey: (CBLBlobKey)key forDigest: (NSString*)digest {
    if (!_pendingAttachmentsByDigest)
        _pendingAttachmentsByDigest = [[NSMutableDictionary alloc] init];
    NSData* keyData = [NSData dataWithBytes: &key length: sizeof(CBLBlobKey)];
    _pendingAttachmentsByDigest[digest] = keyData;
}


- (void) rememberAttachmentWriter: (CBL_BlobStoreWriter*)writer forDigest:(NSString*)digest {
    if (!_pendingAttachmentsByDigest)
        _pendingAttachmentsByDigest = [[NSMutableDictionary alloc] init];
    _pendingAttachmentsByDigest[digest] = writer;
}


// This is ONLY FOR TESTS (see CBLMultipartDownloader.m)
#if DEBUG
- (id) attachmentWriterForAttachment: (NSDictionary*)attachment {
    NSString* digest = $castIf(NSString, attachment[@"digest"]);
    if (!digest)
        return nil;
    return _pendingAttachmentsByDigest[digest];
}
#endif


- (CBLStatus) installAttachment: (CBL_Attachment*)attachment
                       forInfo: (NSDictionary*)attachInfo {
    NSString* digest = $castIf(NSString, attachInfo[@"digest"]);
    if (!digest)
        return kCBLStatusBadAttachment;
    id writer = _pendingAttachmentsByDigest[digest];

    if ([writer isKindOfClass: [CBL_BlobStoreWriter class]]) {
        // Found a blob writer, so install the blob:
        if (![writer install])
            return kCBLStatusAttachmentError;
        attachment->blobKey = [writer blobKey];
        attachment->length = [writer length];
        // Remove the writer but leave the blob-key behind for future use:
        [self rememberPendingKey: attachment->blobKey forDigest: digest];
        return kCBLStatusOK;
        
    } else if ([writer isKindOfClass: [NSData class]]) {
        // This attachment was already added, but the key was left behind in the dictionary:
        attachment->blobKey = *(CBLBlobKey*)[writer bytes];
        NSNumber* lengthObj = $castIf(NSNumber, attachInfo[@"length"]);
        if (!lengthObj)
            return kCBLStatusBadAttachment;
        attachment->length = lengthObj.unsignedLongLongValue;
        return kCBLStatusOK;
        
    } else {
        Warn(@"CBLDatabase: No pending attachment for digest %@", digest);
        return kCBLStatusBadAttachment;
    }
}


- (BOOL) storeBlob: (NSData*)blob creatingKey: (CBLBlobKey*)outKey {
    return [_attachments storeBlob: blob creatingKey: outKey];
}


- (CBLStatus) insertAttachment: (CBL_Attachment*)attachment
                  forSequence: (SequenceNumber)sequence
{
    Assert(sequence > 0);
    Assert(attachment.isValid);
    NSData* keyData = [NSData dataWithBytes: &attachment->blobKey length: sizeof(CBLBlobKey)];
    id encodedLengthObj = attachment->encoding ? @(attachment->encodedLength) : nil;
    if (![_fmdb executeUpdate: @"INSERT INTO attachments "
                                  "(sequence, filename, key, type, encoding, length, encoded_length, revpos) "
                                  "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                                 @(sequence), attachment.name, keyData,
                                 attachment.contentType, @(attachment->encoding),
                                 @(attachment->length), encodedLengthObj,
                                 @(attachment->revpos)]) {
        return self.lastDbError;
    }
    return kCBLStatusCreated;
}


- (CBLStatus) copyAttachmentNamed: (NSString*)name
                    fromSequence: (SequenceNumber)fromSequence
                      toSequence: (SequenceNumber)toSequence
{
    Assert(name);
    Assert(toSequence > 0);
    Assert(toSequence > fromSequence);
    if (fromSequence <= 0)
        return kCBLStatusNotFound;
    if (![_fmdb executeUpdate: @"INSERT INTO attachments "
                    "(sequence, filename, key, type, encoding, encoded_Length, length, revpos) "
                    "SELECT ?, ?, key, type, encoding, encoded_Length, length, revpos "
                        "FROM attachments WHERE sequence=? AND filename=?",
                    @(toSequence), name,
                    @(fromSequence), name]) {
        return self.lastDbError;
    }
    if (_fmdb.changes == 0) {
        // Oops. This means a glitch in our attachment-management or pull code,
        // or else a bug in the upstream server.
        Warn(@"Can't find inherited attachment '%@' from seq#%lld to copy to #%lld",
             name, fromSequence, toSequence);
        return kCBLStatusNotFound;         // Fail if there is no such attachment on fromSequence
    }
    return kCBLStatusOK;
}


- (NSData*) decodeAttachment: (NSData*)attachment encoding: (CBLAttachmentEncoding)encoding {
    switch (encoding) {
        case kCBLAttachmentEncodingNone:
            break;
        case kCBLAttachmentEncodingGZIP:
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
                                  encoding: (CBLAttachmentEncoding*)outEncoding
                                    status: (CBLStatus*)outStatus
{
    Assert(sequence > 0);
    Assert(filename);
    NSString* filePath = nil;
    CBL_FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT key, type, encoding FROM attachments WHERE sequence=? AND filename=?",
                      @(sequence), filename];
    if (!r) {
        *outStatus = self.lastDbError;
        return nil;
    }
    @try {
        if (![r next]) {
            *outStatus = kCBLStatusNotFound;
            return nil;
        }
        NSData* keyData = [r dataNoCopyForColumnIndex: 0];
        if (keyData.length != sizeof(CBLBlobKey)) {
            Warn(@"%@: Attachment %lld.'%@' has bogus key size %u",
                 self, sequence, filename, (unsigned)keyData.length);
            *outStatus = kCBLStatusCorruptError;
            return nil;
        }
        filePath = [_attachments pathForKey: *(CBLBlobKey*)keyData.bytes];
        *outStatus = kCBLStatusOK;
        if (outType)
            *outType = [r stringForColumnIndex: 1];
        if (outEncoding)
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
                            encoding: (CBLAttachmentEncoding*)outEncoding
                              status: (CBLStatus*)outStatus
{
    CBLAttachmentEncoding encoding;
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
        *outStatus = kCBLStatusCorruptError;
        return nil;
    }
    if (outEncoding)
        *outEncoding = encoding;
    else
        contents = [self decodeAttachment: contents encoding: encoding];
    return contents;
}


- (BOOL) sequenceHasAttachments: (SequenceNumber)sequence {
    return [_fmdb boolForQuery: @"SELECT 1 FROM attachments WHERE sequence=? LIMIT 1", @(sequence)];
}


/** Constructs an "_attachments" dictionary for a revision, to be inserted in its JSON body. */
- (NSDictionary*) getAttachmentDictForSequence: (SequenceNumber)sequence
                                       options: (CBLContentOptions)options
{
    Assert(sequence > 0);
    CBL_FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT filename, key, type, encoding, length, encoded_length, revpos "
                       "FROM attachments WHERE sequence=?",
                      @(sequence)];
    if (!r)
        return nil;
    if (![r next]) {
        [r close];
        return nil;
    }
    BOOL decodeAttachments = !(options & kCBLLeaveAttachmentsEncoded);
    NSMutableDictionary* attachments = $mdict();
    do {
        NSData* keyData = [r dataNoCopyForColumnIndex: 1];
        NSString* digestStr = blobKeyToDigest(*(CBLBlobKey*)keyData.bytes);
        CBLAttachmentEncoding encoding = [r intForColumnIndex: 3];
        UInt64 length = [r longLongIntForColumnIndex: 4];
        UInt64 encodedLength = [r longLongIntForColumnIndex: 5];
        
        // Get the attachment contents if asked to:
        NSData* data = nil;
        BOOL dataSuppressed = NO;
        if (options & kCBLIncludeAttachments) {
            UInt64 effectiveLength = (encoding && !decodeAttachments) ? encodedLength : length;
            if ((options & kCBLBigAttachmentsFollow) && effectiveLength >= kBigAttachmentLength) {
                dataSuppressed = YES;
            } else {
                data = [_attachments blobForKey: *(CBLBlobKey*)keyData.bytes];
                if (!data)
                    Warn(@"CBLDatabase: Failed to get attachment for key %@", keyData);
            }
        }
        
        NSString* encodingStr = nil;
        id encodedLengthObj = nil;
        if (encoding != kCBLAttachmentEncodingNone) {
            // Decode the attachment if it's included in the dict:
            if (data && decodeAttachments) {
                data = [self decodeAttachment: data encoding: encoding];
            } else {
                encodingStr = @"gzip";  // the only encoding I know
                encodedLengthObj = @(encodedLength);
            }
        }

        attachments[[r stringForColumnIndex: 0]] = $dict({@"stub", ((data || dataSuppressed) ? nil : $true)},
                                      {@"data", (data ? [CBLBase64 encode: data] : nil)},
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
    NSString* digest = $castIf(NSString, attachmentDict[@"digest"]);
    if (!digest)
        return nil;
    NSString* path = nil;
    id pending = _pendingAttachmentsByDigest[digest];
    if (pending) {
        if ([pending isKindOfClass: [CBL_BlobStoreWriter class]]) {
            path = [pending filePath];
        } else {
            CBLBlobKey key = *(CBLBlobKey*)[pending bytes];
            path = [_attachments pathForKey: key];
        }
    } else {
        // If it's an installed attachment, ask the blob-store for it:
        CBLBlobKey key;
        if (digestToBlobKey(digest, &key))
            path = [_attachments pathForKey: key];
    }

    return path ? [NSURL fileURLWithPath: path] : nil;
}


+ (void) stubOutAttachments: (NSDictionary*)attachments
                 inRevision: (CBL_MutableRevision*)rev
{
    [rev mutateAttachments: ^NSDictionary *(NSString *name, NSDictionary *attachment) {
        if (attachment[@"follows"] || attachment[@"data"]) {
            NSMutableDictionary* editedAttachment = [attachment mutableCopy];
            [editedAttachment removeObjectForKey: @"follows"];
            [editedAttachment removeObjectForKey: @"data"];
            editedAttachment[@"stub"] = $true;
            if (!editedAttachment[@"revpos"])
                editedAttachment[@"revpos"] = @(rev.generation);

            CBL_Attachment* attachmentObject = attachments[name];
            if (attachmentObject) {
                editedAttachment[@"length"] = @(attachmentObject->length);
                editedAttachment[@"digest"] = blobKeyToDigest(attachmentObject->blobKey);
            }
            attachment = editedAttachment;
        }
        return attachment;
    }];
}


// Replaces attachment data whose revpos is < minRevPos with stubs.
// If attachmentsFollow==YES, replaces data with "follows" key.
+ (void) stubOutAttachmentsIn: (CBL_MutableRevision*)rev
                 beforeRevPos: (int)minRevPos
            attachmentsFollow: (BOOL)attachmentsFollow
{
    if (minRevPos <= 1 && !attachmentsFollow)
        return;
    [rev mutateAttachments: ^NSDictionary *(NSString *name, NSDictionary *attachment) {
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
- (BOOL) inlineFollowingAttachmentsIn: (CBL_MutableRevision*)rev error: (NSError**)outError {
    __block NSError *error = nil;
    [rev mutateAttachments:
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
            editedAttachment[@"data"] = [CBLBase64 encode: fileData];
            return editedAttachment;
        }
     ];
    if (outError)
        *outError = error;
    return (error == nil);
}


/** Given a revision, read its _attachments dictionary (if any), convert each non-stub
    attachment to a CBL_Attachment object, and return a dictionary names->CBL_Attachments. */
- (NSDictionary*) attachmentsFromRevision: (CBL_Revision*)rev
                                   status: (CBLStatus*)outStatus
{
    // If there are no attachments in the new rev, there's nothing to do:
    NSDictionary* revAttachments = rev.attachments;
    if (revAttachments.count == 0 || rev.deleted) {
        *outStatus = kCBLStatusOK;
        return @{};
    }
    
    CBLStatus status = kCBLStatusOK;
    NSMutableDictionary* attachments = $mdict();
    for (NSString* name in revAttachments) {
        // Create a CBL_Attachment object:
        NSDictionary* attachInfo = revAttachments[name];
        NSString* contentType = $castIf(NSString, attachInfo[@"content_type"]);
        CBL_Attachment* attachment = [[CBL_Attachment alloc] initWithName: name
                                                           contentType: contentType];

        NSString* newContentsBase64 = $castIf(NSString, attachInfo[@"data"]);
        if (newContentsBase64) {
            // If there's inline attachment data, decode and store it:
            @autoreleasepool {
                NSData* newContents = [CBLBase64 decode: newContentsBase64];
                if (!newContents) {
                    status = kCBLStatusBadEncoding;
                    break;
                }
                attachment->length = newContents.length;
                if (![self storeBlob: newContents creatingKey: &attachment->blobKey]) {
                    status = kCBLStatusAttachmentError;
                    break;
                }
            }
        } else if ([attachInfo[@"follows"] isEqual: $true]) {
            // "follows" means the uploader provided the attachment in a separate MIME part.
            // This means it's already been registered in _pendingAttachmentsByDigest;
            // I just need to look it up by its "digest" property and install it into the store:
            status = [self installAttachment: attachment forInfo: attachInfo];
            if (CBLStatusIsError(status))
                break;
        } else {
            // This item is just a stub; validate and skip it
            if (![attachInfo[@"stub"] isEqual: $true]) {
                *outStatus = kCBLStatusBadAttachment;
                return nil;
            }
            id revPosObj = attachInfo[@"revpos"];
            if (revPosObj) {
                int revPos = [$castIf(NSNumber, revPosObj) intValue];
                if (revPos <= 0) {
                    *outStatus = kCBLStatusBadAttachment;
                    return nil;
                }
            }
            continue;
        }
        
        // Handle encoded attachment:
        NSString* encodingStr = attachInfo[@"encoding"];
        if (encodingStr) {
            if ($equal(encodingStr, @"gzip"))
                attachment->encoding = kCBLAttachmentEncodingGZIP;
            else {
                status = kCBLStatusBadEncoding;
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


- (CBLStatus) processAttachments: (NSDictionary*)attachments
                    forRevision: (CBL_Revision*)rev
             withParentSequence: (SequenceNumber)parentSequence
{
    Assert(rev);
    
    // If there are no attachments in the new rev, there's nothing to do:
    NSDictionary* revAttachments = rev.attachments;
    if (revAttachments.count == 0 || rev.deleted)
        return kCBLStatusOK;
    
    SequenceNumber newSequence = rev.sequence;
    Assert(newSequence > 0);
    Assert(newSequence > parentSequence);
    unsigned generation = rev.generation;
    Assert(generation > 0, @"Missing generation in rev %@", rev);

    for (NSString* name in revAttachments) {
        CBLStatus status;
        CBL_Attachment* attachment = attachments[name];
        if (attachment) {
            // Determine the revpos, i.e. generation # this was added in. Usually this is
            // implicit, but a rev being pulled in replication will have it set already.
            if (attachment->revpos == 0)
                attachment->revpos = generation;
            else if (attachment->revpos > generation) {
                Warn(@"Attachment %@ . '%@' has weird revpos %u; setting to %u",
                     rev, name, attachment->revpos, generation);
                attachment->revpos = generation;
            }

            // Finally insert the attachment:
            status = [self insertAttachment: attachment forSequence: newSequence];
        } else {
            // It's just a stub, so copy the previous revision's attachment entry:
            //? Should I enforce that the type and digest (if any) match?
            status = [self copyAttachmentNamed: name
                                  fromSequence: parentSequence
                                    toSequence: newSequence];
        }
        if (CBLStatusIsError(status))
            return status;
    }
    return kCBLStatusOK;
}


- (CBLMultipartWriter*) multipartWriterForRevision: (CBL_Revision*)rev
                                      contentType: (NSString*)contentType
{
    CBLMultipartWriter* writer = [[CBLMultipartWriter alloc] initWithContentType: contentType 
                                                                      boundary: nil];
    [writer setNextPartsHeaders: @{@"Content-Type": @"application/json"}];
    [writer addData: rev.asJSON];
    NSDictionary* attachments = rev.attachments;
    for (NSString* attachmentName in attachments) {
        NSDictionary* attachment = attachments[attachmentName];
        if (attachment[@"follows"]) {
            NSString* disposition = $sprintf(@"attachment; filename=%@", CBLQuoteString(attachmentName));
            [writer setNextPartsHeaders: $dict({@"Content-Disposition", disposition})];
            [writer addFileURL: [self fileForAttachmentDict: attachment]];
        }
    }
    return writer;
}


/** Replaces or removes a single attachment in a document, by saving a new revision whose only
    change is the value of the attachment. */
- (CBL_Revision*) updateAttachment: (NSString*)filename
                            body: (CBL_BlobStoreWriter*)body
                            type: (NSString*)contentType
                        encoding: (CBLAttachmentEncoding)encoding
                         ofDocID: (NSString*)docID
                           revID: (NSString*)oldRevID
                          status: (CBLStatus*)outStatus
{
    *outStatus = kCBLStatusBadAttachment;
    if (filename.length == 0 || (body && !contentType) || (oldRevID && !docID) || (body && !docID))
        return nil;

    CBL_MutableRevision* oldRev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                       revID: oldRevID
                                                                     deleted: NO];
    if (oldRevID) {
        // Load existing revision if this is a replacement:
        *outStatus = [self loadRevisionBody: oldRev options: 0];
        if (CBLStatusIsError(*outStatus)) {
            if (*outStatus == kCBLStatusNotFound && [self existsDocumentWithID: docID revisionID: nil])
                *outStatus = kCBLStatusConflict;   // if some other revision exists, it's a conflict
            return nil;
        }
    } else {
        // If this creates a new doc, it needs a body:
        oldRev.body = [CBL_Body bodyWithProperties: @{}];
    }

    // Update the _attachments dictionary:
    NSMutableDictionary* attachments = [oldRev.attachments mutableCopy];
    if (!attachments)
        attachments = $mdict();
    if (body) {
        CBLBlobKey key = body.blobKey;
        NSString* digest = blobKeyToDigest(key);
        [self rememberAttachmentWriter: body forDigest: digest];
        NSString* encodingName = (encoding == kCBLAttachmentEncodingGZIP) ? @"gzip" : nil;
        attachments[filename] = $dict({@"digest", digest},
                                      {@"length", @(body.length)},
                                      {@"follows", $true},
                                      {@"content_type", contentType},
                                      {@"encoding", encodingName});
    } else {
        if (oldRevID && !attachments[filename]) {
            *outStatus = kCBLStatusAttachmentNotFound;
            return nil;
        }
        [attachments removeObjectForKey: filename];
    }
    NSMutableDictionary* properties = [oldRev.properties mutableCopy];
    properties[@"_attachments"] = attachments;
    oldRev.properties = properties;

    // Store a new revision with the updated _attachments:
    CBL_Revision* newRev = [self putRevision: oldRev prevRevisionID: oldRevID
                             allowConflict: NO status: outStatus];
    if (!body && *outStatus == kCBLStatusCreated)
        *outStatus = kCBLStatusOK;
    return newRev;
}


- (CBLStatus) garbageCollectAttachments {
    // First delete attachment rows for already-cleared revisions:
    // OPT: Could start after last sequence# we GC'd up to
    [_fmdb executeUpdate:  @"DELETE FROM attachments WHERE sequence IN "
                            "(SELECT sequence from revs WHERE current=0 AND json IS null)"];
    
    // Now collect all remaining attachment IDs and tell the store to delete all but these:
    // OPT: Unindexed scan of attachments table!
    CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT DISTINCT key FROM attachments"];
    if (!r)
        return self.lastDbError;
    NSMutableSet* allKeys = [NSMutableSet set];
    while ([r next]) {
        [allKeys addObject: [r dataForColumnIndex: 0]];
    }
    [r close];
    NSInteger numDeleted = [_attachments deleteBlobsExceptWithKeys: allKeys];
    if (numDeleted < 0)
        return kCBLStatusAttachmentError;
    Log(@"Deleted %d attachments", (int)numDeleted);
    return kCBLStatusOK;
}


@end
