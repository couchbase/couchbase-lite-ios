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
    return [dbPath stringByAppendingPathComponent: @"attachments"];

}


- (NSString*) attachmentStorePath {
    return [[self class] attachmentStorePath: _dir];
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
        attachment->blobKey = [writer blobKey];
        attachment.possiblyEncodedLength = [writer length];
        // Remove the writer but leave the blob-key behind for future use:
        [self rememberPendingKey: attachment->blobKey forDigest: digest];
        return kCBLStatusOK;
        
    } else if ([writer isKindOfClass: [NSData class]]) {
        // This attachment was already added, but the key was left behind in the dictionary:
        attachment->blobKey = *(CBLBlobKey*)[writer bytes];
        return kCBLStatusOK;
        
    } else {
        Warn(@"CBLDatabase: No pending attachment for digest %@", digest);
        return kCBLStatusBadAttachment;
    }
}


/** Returns a CBL_Attachment for an attachment in a stored revision. */
- (CBL_Attachment*) attachmentForRevision: (CBL_Revision*)rev
                                    named: (NSString*)filename
                                   status: (CBLStatus*)outStatus
{
    Assert(rev);
    Assert(filename);
    NSDictionary* properties = rev.properties;
    if (!properties) {
        CBL_MutableRevision* mrev = [rev mutableCopy];
        *outStatus = [self loadRevisionBody: mrev options: 0];
        if (CBLStatusIsError(*outStatus))
            return nil;
        rev = mrev;
        properties = mrev.properties;
    }

    NSDictionary* info = rev.attachments[filename];
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


- (NSData*) dataForAttachmentDict: (NSDictionary*)attachmentDict
{
    NSURL* url = [self fileForAttachmentDict: attachmentDict];
    if (!url)
        return nil;
    return [NSData dataWithContentsOfURL: url options: NSDataReadingMappedIfSafe error: NULL];
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


/** Given a revision, updates its _attachments dictionary for storage in the database, returning an
    updated copy of the revision (or nil on error.) */
- (CBL_Revision*) processAttachmentsForRevision: (CBL_Revision*)rev
                                     generation: (unsigned)generation
                                         status: (CBLStatus*)outStatus
{
    *outStatus = kCBLStatusOK;
    NSDictionary* revAttachments = rev.attachments;
    if (revAttachments == nil)
        return rev;  // no-op: no attachments

    // Deletions can't have attachments:
    CBL_MutableRevision* nuRev = [rev mutableCopy];
    if (nuRev.deleted || revAttachments.count == 0) {
        NSMutableDictionary* body = [nuRev.properties mutableCopy];
        [body removeObjectForKey: @"_attachments"];
        nuRev.properties = body;
        return nuRev;
    }

    BOOL ok;
    ok = [nuRev mutateAttachments: ^NSDictionary *(NSString *name, NSDictionary *attachInfo) {
        CBL_Attachment* attachment = [[CBL_Attachment alloc] initWithName: name
                                                                     info: attachInfo
                                                                   status: outStatus];
        if (attachment == nil) {
            return nil;
        } else if (attachment.data) {
            // If there's inline attachment data, decode and store it:
            if (![_attachments storeBlob: attachment.data creatingKey: &attachment->blobKey]) {
                *outStatus = kCBLStatusAttachmentError;
                return nil;
            }
        } else if ([attachInfo[@"follows"] isEqual: $true]) {
            // "follows" means the uploader provided the attachment in a separate MIME part.
            // This means it's already been registered in _pendingAttachmentsByDigest;
            // I just need to look it up by its "digest" property and install it into the store:
            *outStatus = [self installAttachment: attachment];
            if (CBLStatusIsError(*outStatus))
                return nil;
        }
        // Set or validate the revpos:
        if (attachment->revpos == 0) {
            attachment->revpos = generation;
        } else if (attachment->revpos >= generation) {
            *outStatus = kCBLStatusBadAttachment;
            return nil;
        }
        return attachment.asStubDictionary;
    }];
    return ok ? nuRev : nil;
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
