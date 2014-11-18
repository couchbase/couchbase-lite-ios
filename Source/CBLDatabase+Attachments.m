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

extern "C" {
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
#import "GTMNSData+zlib.h"
}

#import <CBForest/CBForest.hh>
using namespace forestdb;


// Length that constitutes a 'big' attachment
#define kBigAttachmentLength (16*1024)


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
    if (!digest)
        return kCBLStatusBadAttachment;
    id writer = _pendingAttachmentsByDigest[digest];

    if ([writer isKindOfClass: [CBL_BlobStoreWriter class]]) {
        // Found a blob writer, so install the blob:
        if (![writer install])
            return kCBLStatusAttachmentError;
        attachment.blobKey = [writer blobKey];
        attachment.possiblyEncodedLength = [writer length];
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
    *outStatus = [self loadRevisionBody: mrev options: 0];
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
        if (!attachments)
            return nil;
    }
    NSDictionary* info = attachments[filename];
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


- (NSData*) dataForAttachmentDict: (NSDictionary*)attachmentDict {
    NSURL* url = [self fileForAttachmentDict: attachmentDict];
    if (!url)
        return nil;
    return [NSData dataWithContentsOfURL: url options: NSDataReadingMappedIfSafe error: NULL];
}


- (NSURL*) fileForAttachmentDict: (NSDictionary*)attachmentDict {
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


#pragma mark - UPDATING _attachments DICTS:


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


- (void) expandAttachmentsIn: (CBL_MutableRevision*)rev options: (CBLContentOptions)options {
    BOOL decodeAttachments = !(options & kCBLLeaveAttachmentsEncoded);
    [rev mutateAttachments: ^NSDictionary *(NSString *name, NSDictionary *attachment) {
        NSString* encoding = attachment[@"encoding"];
        BOOL decodeIt = decodeAttachments && (encoding != nil);
        if (decodeIt || attachment[@"stub"] || attachment[@"follows"]) {
            NSMutableDictionary* expanded = [attachment mutableCopy];
            [expanded removeObjectForKey: @"stub"];
            [expanded removeObjectForKey: @"follows"];

            NSString* base64Data = attachment[@"data"];
            if (!base64Data || decodeIt) {
                NSData* data;
                if (base64Data)
                    data = [CBLBase64 decode: base64Data];
                else
                    data = [self dataForAttachmentDict: attachment];
                if (!data) {
                    Warn(@"Can't get binary data of attachment '%@' of %@", name, rev);
                    return attachment;
                }
                if (decodeIt) {
                    data = [NSData gtm_dataByInflatingData: data];
                    if (!data) {
                        Warn(@"Can't unzip attachment '%@' of %@", name, rev);
                        return attachment;
                    }
                    [expanded removeObjectForKey: @"encoding"];
                    [expanded removeObjectForKey: @"encoded_length"];
                }
                expanded[@"data"] = [CBLBase64 encode: data];
            }
            attachment = expanded;
        }
        return attachment;
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


/** Given a revision, updates its _attachments dictionary for storage in the database. */
- (BOOL) processAttachmentsForRevision: (CBL_MutableRevision*)rev
                             prevRevID: (NSString*)prevRevID
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

    unsigned generation = [CBL_Revision generationFromRevID: prevRevID] + 1;
    __block NSDictionary* parentAttachments = nil;

    return [rev mutateAttachments: ^NSDictionary *(NSString *name, NSDictionary *attachInfo) {
        CBL_Attachment* attachment = [[CBL_Attachment alloc] initWithName: name
                                                                     info: attachInfo
                                                                   status: outStatus];
        if (attachment == nil) {
            return nil;
        } else if (attachment.data) {
            // If there's inline attachment data, decode and store it:
            CBLBlobKey blobKey;
            if (![_attachments storeBlob: attachment.data creatingKey: &blobKey]) {
                *outStatus = kCBLStatusAttachmentError;
                return nil;
            }
            attachment.blobKey = blobKey;
        } else if ([attachInfo[@"follows"] isEqual: $true]) {
            // "follows" means the uploader provided the attachment in a separate MIME part.
            // This means it's already been registered in _pendingAttachmentsByDigest;
            // I just need to look it up by its "digest" property and install it into the store:
            *outStatus = [self installAttachment: attachment];
            if (CBLStatusIsError(*outStatus))
                return nil;
        } else if ([attachInfo[@"stub"] isEqual: $true]) {
            // "stub" on an incoming revision means the attachment is the same as in the parent.
            if (!parentAttachments && prevRevID) {
                parentAttachments = [self attachmentsForDocID: rev.docID revID: prevRevID
                                                       status: outStatus];
                if (!parentAttachments) {
                    if (*outStatus == kCBLStatusOK || *outStatus == kCBLStatusNotFound)
                        *outStatus = kCBLStatusBadAttachment;
                    return nil;
                }
            }
            NSDictionary* parentAttachment = parentAttachments[name];
            if (!parentAttachment) {
                *outStatus = kCBLStatusBadAttachment;
                return nil;
            }
            return parentAttachment;
        }
        
        // Set or validate the revpos:
        if (attachment->revpos == 0) {
            attachment->revpos = generation;
        } else if (attachment->revpos >= generation) {
            *outStatus = kCBLStatusBadAttachment;
            return nil;
        }
        Assert(attachment.isValid);
        return attachment.asStubDictionary;
    }];
}


#pragma mark - MISC.:


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
        NSString* digest = [CBLDatabase blobKeyToDigest: key];
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


- (BOOL) garbageCollectAttachments: (NSError**)outError {
    NSString* path = [_dir stringByAppendingPathComponent: @"attachmentIndex.forest"];
    if (!CBLRemoveFileIfExists(path, outError))
        return NO;

    CBLStatus status = [self _try:^CBLStatus{
        Database::config config = Database::defaultConfig();
        config.buffercache_size = 128*1024;
        config.wal_threshold = 128;
        config.wal_flush_before_commit = true;
        config.seqtree_opt = false;
        Database attachmentIndex(path.fileSystemRepresentation, FDB_OPEN_FLAG_CREATE, config);
        {
            Transaction attachmentTransaction(&attachmentIndex);

            DocEnumerator::Options options = DocEnumerator::Options::kDefault;
            options.contentOptions = Database::kMetaOnly;

            LogTo(CBLDatabase, @"Scanning database revisions for attachments...");
            for (DocEnumerator e(*_forest, slice::null, slice::null, options); e; ++e) {
                VersionedDocument doc(*_forest, *e);
                if (!doc.hasAttachments() || (doc.isDeleted() && !doc.isConflicted()))
                    continue;
                doc.read();
                // Since db is assumed to have just been compacted, we know that non-current revisions
                // won't have any bodies. So only scan the current revs.
                auto revNodes = doc.currentRevisions();
                for (auto revNode = revNodes.begin(); revNode != revNodes.end(); ++revNode) {
                    if ((*revNode)->isActive() && (*revNode)->hasAttachments()) {
                        alloc_slice body = (*revNode)->readBody();
                        if (body.size > 0) {
                            NSDictionary* rev = [CBLJSON JSONObjectWithData: body.uncopiedNSData()
                                                                    options: 0 error: NULL];
                            NSDictionary* attachments = rev.cbl_attachments;
                            for (NSString* key in attachments) {
                                NSDictionary* att = attachments[key];
                                NSString* digest = att[@"digest"];
                                CBLBlobKey blobKey;
                                if (digestToBlobKey(digest, &blobKey)) {
                                    attachmentTransaction.set(forestdb::slice(&blobKey, sizeof(blobKey)),
                                                              forestdb::slice("x", 1));
                                }
                            }
                        }
                    }
                }
            }
            LogTo(CBLDatabase, @"    ...found %llu attachments", attachmentIndex.getInfo().doc_count);

            Database* attachmentIndexP = &attachmentIndex; // workaround to allow block below to call it
            NSInteger deleted = [_attachments deleteBlobsExceptMatching: ^BOOL(CBLBlobKey blobKey) {
                return attachmentIndexP->get(forestdb::slice(&blobKey, sizeof(blobKey))).exists();
            }];

            LogTo(CBLDatabase, @"    ... deleted %ld obsolete attachment files.", (long)deleted);
        }
        attachmentIndex.deleteDatabase();
        return kCBLStatusOK;
    }];
    return !CBLStatusIsError(status);
}


@end
