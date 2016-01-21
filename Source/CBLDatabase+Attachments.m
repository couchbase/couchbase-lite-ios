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
#import "CBL_BlobStoreWriter.h"
#import "CBL_Attachment.h"
#import "CBL_Body.h"
#import "CBLMultipartWriter.h"
#import "CBLMisc.h"
#import "CBLInternal.h"
#import "CBLGZip.h"

#import "CollectionUtils.h"


// Length that constitutes a 'big' attachment
#define kBigAttachmentLength (2*1024)


@implementation CBLDatabase (Attachments)


+ (NSString*) blobKeyToDigest: (CBLBlobKey)key {
    return [@"sha1-" stringByAppendingString: [CBLBase64 encode: &key length: sizeof(key)]];
}

- (NSString*) attachmentStorePath {
    return [_dir stringByAppendingPathComponent: @"attachments"];
}


#pragma mark - ATTACHMENT WRITERS:


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


// Given a decoded attachment with a "follows" property, find the associated CBL_BlobStoreWriter
// and install it into the blob-store.
- (CBLStatus) installAttachment: (CBL_Attachment*)attachment {
    NSString* digest = attachment.digest;
    if (!digest) {
        Warn(@"Missing 'digest' property in attachment");
        return kCBLStatusBadAttachment;
    }
    id writer = _pendingAttachmentsByDigest[digest];

    if ([writer isKindOfClass: [CBL_BlobStoreWriter class]]) {
        // Found a blob writer, so install the blob:
        if (![writer install])
            return kCBLStatusAttachmentError;
        attachment.blobKey = [writer blobKey];
        attachment.possiblyEncodedLength = [writer bytesWritten];
        // Remove the writer but leave the blob-key behind for future use:
        [self rememberPendingKey: attachment.blobKey forDigest: digest];
        return kCBLStatusOK;
        
    } else if ([writer isKindOfClass: [NSData class]]) {
        // This attachment was already added, but the key was left behind in the dictionary:
        attachment.blobKey = *(CBLBlobKey*)[writer bytes];
        return kCBLStatusOK;

    } else if ([_attachments hasBlobForKey: attachment.blobKey]) {
        // It already exists in the blob-store, so it's OK
        return kCBLStatusOK;
        
    } else {
        Warn(@"CBLDatabase: No pending attachment for digest %@", digest);
        return kCBLStatusBadAttachment;
    }
}


#pragma mark - LOOKING UP ATTACHMENTS:


- (NSDictionary*) attachmentsForDocID: (NSString*)docID
                                revID: (NSString*)revID
                               status: (CBLStatus*)outStatus
{
    CBL_MutableRevision* mrev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                     revID: revID
                                                                   deleted: NO];
    *outStatus = [self loadRevisionBody: mrev];
    if (CBLStatusIsError(*outStatus))
        return nil;
    return mrev.attachments;
}


/** Returns a CBL_Attachment for an attachment in a stored revision. */
- (CBL_Attachment*) attachmentForRevision: (CBL_Revision*)rev
                                    named: (NSString*)filename
                                   status: (CBLStatus*)outStatus
{
    Assert(filename);
    NSDictionary* attachments = rev.attachments;
    if (!attachments) {
        attachments = [self attachmentsForDocID: rev.docID revID: rev.revID status: outStatus];
        if (!attachments) {
            *outStatus = kCBLStatusNotFound;
            return nil;
        }
    }
    return [self attachmentForDict: attachments[filename] named: filename status: outStatus];
}


- (CBL_Attachment*) attachmentForDict: (NSDictionary*)info
                                named: (NSString*)filename
                               status: (CBLStatus*)outStatus
{
    if (!info) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    CBL_Attachment* attachment = [[CBL_Attachment alloc] initWithName: filename
                                                                 info: info
                                                               status: outStatus];
    attachment.database = self;
    return attachment;
}


- (NSString*) pathForPendingAttachmentWithDict: (NSDictionary*)attachInfo {
    NSString* digest = $castIf(NSString, attachInfo[@"digest"]);
    if (!digest)
        return nil;
    CBL_BlobStoreWriter* pending = _pendingAttachmentsByDigest[digest];
    if ([pending isKindOfClass: [CBL_BlobStoreWriter class]])
        return pending.filePath;
    return nil;
}


// might be made public API someday...
- (BOOL) hasAttachmentWithDigest: (NSString*)digest {
    CBLBlobKey key;
    return [CBL_Attachment digest: digest toBlobKey: &key]
        && [_attachments hasBlobForKey: key];
}

// might be made public API someday...
- (uint64_t) lengthOfAttachmentWithDigest: (NSString*)digest {
    CBLBlobKey key;
    if (![CBL_Attachment digest: digest toBlobKey: &key])
        return 0;
    return [_attachments lengthOfBlobForKey: key];
}

// might be made public API someday...
- (NSData*) contentOfAttachmentWithDigest: (NSString*)digest {
    CBLBlobKey key;
    if (![CBL_Attachment digest: digest toBlobKey: &key])
        return nil;
    return [_attachments blobForKey: key];
}

// might be made public API someday...
- (NSInputStream*) contentStreamOfAttachmentWithDigest: (NSString*)digest {
    CBLBlobKey key;
    if (![CBL_Attachment digest: digest toBlobKey: &key])
        return nil;
    return [_attachments blobInputStreamForKey: key length: NULL];
}


#pragma mark - UPDATING _attachments DICTS:


static UInt64 smallestLength(NSDictionary* attachment) {
    UInt64 length = [attachment[@"length"] unsignedLongLongValue];
    NSNumber* encodedLength = attachment[@"encoded_length"];
    if (encodedLength)
        length = encodedLength.unsignedLongLongValue;
    return length;
}


- (BOOL) expandAttachmentsIn: (CBL_MutableRevision*)rev
                   minRevPos: (int)minRevPos
                allowFollows: (BOOL)allowFollows
                      decode: (BOOL)decodeAttachments
                      status: (CBLStatus*)outStatus
{
    *outStatus = kCBLStatusOK;
    [rev mutateAttachments: ^NSDictionary *(NSString *name, NSDictionary *attachment) {
        int revPos = [attachment[@"revpos"] intValue];
        if (revPos < minRevPos && revPos != 0) {
            // Stub:
            return @{@"stub": @YES, @"revpos": @(revPos)};
        } else {
            NSMutableDictionary* expanded = [attachment mutableCopy];
            [expanded removeObjectForKey: @"stub"];
            if (decodeAttachments) {
                [expanded removeObjectForKey: @"encoding"];
                [expanded removeObjectForKey: @"encoded_length"];
            }

            if (allowFollows && smallestLength(expanded) >= kBigAttachmentLength) {
                // Data will follow (multipart):
                expanded[@"follows"] = @YES;
                [expanded removeObjectForKey: @"data"];
            } else {
                // Put data inline:
                [expanded removeObjectForKey: @"follows"];
                CBLStatus status;
                CBL_Attachment* attachObj = [self attachmentForDict: attachment named: name
                                                             status: &status];
                if (!attachObj) {
                    Warn(@"Can't get attachment '%@' of %@ (status %d)", name, rev, status);
                    *outStatus = status;
                    return attachment;
                }
                NSData* data = decodeAttachments ? attachObj.content : attachObj.encodedContent;
                if (!data) {
                    Warn(@"Can't get binary data of attachment '%@' of %@", name, rev);
                    *outStatus = kCBLStatusNotFound;
                    return attachment;
                }
                expanded[@"data"] = [CBLBase64 encode: data];
            }
            return expanded;
        }
    }];
    return (*outStatus == kCBLStatusOK);
}


/** Given a revision, updates its _attachments dictionary for storage in the database. */
- (BOOL) processAttachmentsForRevision: (CBL_MutableRevision*)rev
                              ancestry: (NSArray*)ancestry
                                status: (CBLStatus*)outStatus
{
    *outStatus = kCBLStatusOK;
    NSDictionary* revAttachments = rev.attachments;
    if (revAttachments == nil)
        return YES;  // no-op: no attachments

    // Deletions can't have attachments:
    if (rev.deleted || revAttachments.count == 0) {
        NSMutableDictionary* body = [rev.properties mutableCopy];
        [body removeObjectForKey: @"_attachments"];
        rev.properties = body;
        return YES;
    }

    NSString *prevRevID = ancestry.firstObject;
    unsigned generation = rev.generation;
    Assert(generation > 0);
    __block NSDictionary* parentAttachments = nil;

    [rev mutateAttachments: ^NSDictionary *(NSString *name, NSDictionary *attachInfo) {
        CBL_Attachment* attachment = [[CBL_Attachment alloc] initWithName: name
                                                                     info: attachInfo
                                                                   status: outStatus];
        if (attachment == nil) {
            return nil;
        } else if (attachment.encodedContent) {
            // If there's inline attachment data, decode and store it:
            CBLBlobKey blobKey;
            if (![_attachments storeBlob: attachment.encodedContent creatingKey: &blobKey]) {
                *outStatus = kCBLStatusAttachmentError;
                return nil;
            }
            attachment.blobKey = blobKey;
        } else if ([attachInfo[@"follows"] isEqual: $true] || _pendingAttachmentsByDigest[attachment.digest] != nil) {
            // "follows" means the uploader provided the attachment in a separate MIME part.
            // This means it's already been registered in _pendingAttachmentsByDigest;
            // I just need to look it up by its "digest" property and install it into the store:
            *outStatus = [self installAttachment: attachment];
            if (CBLStatusIsError(*outStatus))
                return nil;
        } else if ([attachInfo[@"stub"] isEqual: $true] && attachment->revpos < generation) {
            // "stub" on an incoming revision means the attachment is the same as in the parent.
            // (Either that or the replicator just decided to defer downloading the attachment;
            // that's why the 'if' above tests the revpos.)
            if (!parentAttachments && prevRevID) {
                CBLStatus status;
                parentAttachments = [self attachmentsForDocID: rev.docID revID: prevRevID
                                                       status: &status];
                if (!parentAttachments) {
                    if (status == kCBLStatusOK || status == kCBLStatusNotFound) {
                        if (attachment.hasBlobKey && [_attachments hasBlobForKey: attachment.blobKey]) {
                            // Parent revision's body isn't known (we are probably pulling a rev along
                            // with its entire history) but it's OK, we have the attachment already
                            *outStatus = kCBLStatusOK;
                            return attachInfo;
                        }
                        // If parent rev isn't available, look farther back in ancestry:
                        NSDictionary* ancestorAttachment = [self findAttachment: name
                                                                         revpos: attachment->revpos
                                                                          docID: rev.docID
                                                                       ancestry: ancestry];
                        if (ancestorAttachment) {
                            *outStatus = kCBLStatusOK;
                            return ancestorAttachment;
                        } else {
                            Warn(@"Don't have original attachment for stub '%@' in %@ (missing rev)",
                                 name, rev);
                            status = kCBLStatusBadAttachment;
                        }
                    }
                    *outStatus = status;
                    return nil;
                }
            }
            NSDictionary* parentAttachment = parentAttachments[name];
            if (!parentAttachment) {
                Warn(@"Don't have original attachment for stub '%@' in %@ (missing attachment)",
                     name, rev);
                *outStatus = kCBLStatusBadAttachment;
                return nil;
            }
            return parentAttachment;
        }
        
        // Set or validate the revpos:
        if (attachment->revpos == 0) {
            attachment->revpos = generation;
        } else if (attachment->revpos > generation) {
            Warn(@"Attachment '%@' in %@ has invalid revpos=%d", name, rev, attachment->revpos);
            *outStatus = kCBLStatusBadAttachment;
            return nil;
        }
        Assert(attachment.isValid);
        return attachment.asStubDictionary;
    }];

    return !CBLStatusIsError(*outStatus);
}


// Looks for an attachment with the given revpos in the document's ancestry.
- (NSDictionary*) findAttachment: (NSString*)name
                          revpos: (unsigned)revpos
                           docID: (NSString*)docID
                        ancestry: (NSArray*)ancestry
{
    for (NSInteger i = ancestry.count - 1; i >= 0; i--) {
        NSString* revID = ancestry[i];
        if ([CBL_Revision generationFromRevID: revID] >= revpos) {
            CBLStatus status;
            NSDictionary* attachments = [self attachmentsForDocID: docID revID: revID
                                                           status: &status];
            NSDictionary* attachment = attachments[name];
            if (attachment)
                return attachment;
        }
    }
    return nil;
}


#pragma mark - MISC.:


/** Replaces or removes a single attachment in a document, by saving a new revision whose only
    change is the value of the attachment. */
- (CBL_Revision*) updateAttachment: (NSString*)filename
                              body: (CBL_BlobStoreWriter*)body
                              type: (NSString*)contentType
                          encoding: (CBLAttachmentEncoding)encoding
                           ofDocID: (NSString*)docID
                             revID: (NSString*)oldRevID
                            source: (NSURL*)source
                            status: (CBLStatus*)outStatus
                             error: (NSError**)outError
{
    *outStatus = kCBLStatusBadAttachment;
    if (filename.length == 0 || (body && !contentType) || (oldRevID && !docID) || (body && !docID)) {
        CBLStatusToOutNSError(*outStatus, outError);
        return nil;
    }

    CBL_MutableRevision* oldRev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                       revID: oldRevID
                                                                     deleted: NO];
    if (oldRevID) {
        // Load existing revision if this is a replacement:
        *outStatus = [self loadRevisionBody: oldRev];
        if (CBLStatusIsError(*outStatus)) {
            if (*outStatus == kCBLStatusNotFound
                && [self getDocumentWithID: docID revisionID: nil withBody: NO
                                    status: outStatus] != nil) {
                *outStatus = kCBLStatusConflict;   // if some other revision exists, it's a conflict
            }
            CBLStatusToOutNSError(*outStatus, outError);
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
        NSString* digest = [CBLDatabase blobKeyToDigest: key];
        [self rememberAttachmentWriter: body forDigest: digest];
        NSString* encodingName = (encoding == kCBLAttachmentEncodingGZIP) ? @"gzip" : nil;
        attachments[filename] = $dict({@"digest", digest},
                                      {@"length", @(body.bytesWritten)},
                                      {@"follows", $true},
                                      {@"content_type", contentType},
                                      {@"encoding", encodingName});
    } else {
        if (oldRevID && !attachments[filename]) {
            *outStatus = kCBLStatusAttachmentNotFound;
            CBLStatusToOutNSError(*outStatus, outError);
            return nil;
        }
        [attachments removeObjectForKey: filename];
    }

    NSMutableDictionary* properties = [oldRev.properties mutableCopy];
    properties[@"_attachments"] = attachments;

    // Store a new revision with the updated _attachments:
    CBL_Revision* newRev = [self putDocID: docID
                               properties: properties
                           prevRevisionID: oldRevID allowConflict: NO
                                   source: source
                                   status: outStatus error: outError];
    if (!body && *outStatus == kCBLStatusCreated)
        *outStatus = kCBLStatusOK;

    return newRev;
}


- (BOOL) garbageCollectAttachments: (NSError**)outError {
    LogTo(CBLDatabase, @"Scanning database revisions for attachments...");
    NSSet* keys = [_storage findAllAttachmentKeys: outError];
    if (!keys)
        return NO;
    LogTo(CBLDatabase, @"    ...found %lu attachments", (unsigned long)keys.count);
    NSInteger deleted = [_attachments deleteBlobsExceptMatching: ^BOOL(CBLBlobKey blobKey) {
        NSData* keyData = [[NSData alloc] initWithBytes: &blobKey length: sizeof(blobKey)];
        return [keys containsObject: keyData];
    } error: outError];
    LogTo(CBLDatabase, @"    ... deleted %ld obsolete attachment files.", (long)deleted);
    return deleted >= 0;
}


@end
