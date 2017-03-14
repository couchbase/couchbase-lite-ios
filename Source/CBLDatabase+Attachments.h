//
//  CBLDatabase+Attachments.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase+Internal.h"
#import "CBL_BlobStore.h"
@class CBL_Revision, CBL_Attachment, CBL_BlobStoreWriter;


/** Types of encoding/compression of stored attachments. */
typedef enum {
    kCBLAttachmentEncodingNone,
    kCBLAttachmentEncodingGZIP
} CBLAttachmentEncoding;


@interface CBLDatabase (Attachments)

@property (readonly) NSString* attachmentStorePath;

+ (NSString*) blobKeyToDigest: (CBLBlobKey)key;

/** Register attachment bodies in `attachments` (NSData or file NSURLs) corresponding to the
    attachments in `rev`. The _attachments dict will be mutated if necessary to add "digest"
    and "follows" properties. */
- (BOOL) registerAttachmentBodies: (NSDictionary*)attachments
                      forRevision: (CBL_MutableRevision*)rev
                            error: (NSError**)outError;

/** Scans the rev's _attachments dictionary, adding inline attachment data to the blob-store
    and turning all the attachments into stubs. */
- (BOOL) processAttachmentsForRevision: (CBL_MutableRevision*)rev
                              ancestry: (NSArray<CBL_RevID*>*)ancestry // 1st item is parent revID, etc.
                  allowStubAttachments: (BOOL)allowStubAttachments
                                status: (CBLStatus*)outStatus;

/** Modifies a CBL_Revision's _attachments dictionary by adding the "data" property to all
    attachments (and removing "stub" and "follows".) GZip-encoded attachments will be unzipped
    unless options contains the flag kCBLLeaveAttachmentsEncoded.
    @param rev  The revision to operate on. Its _attachments property may be altered.
    @param minRevPos  Attachments with a "revpos" less than this will remain stubs.
    @param allowFollows  If YES, non-small attachments will get a "follows" key instead of data.
    @param decodeAttachments  If YES, attachments with "encoding" properties will be decoded.
    @param outStatus  On failure, will be set to the error status.
    @return  YES on success, NO on failure. */
- (BOOL) expandAttachmentsIn: (CBL_MutableRevision*)rev
                   minRevPos: (int)minRevPos
                allowFollows: (BOOL)allowFollows
                      decode: (BOOL)decodeAttachments
                      status: (CBLStatus*)outStatus;

- (NSDictionary*) attachmentsForDocID: (NSString*)docID
                                revID: (CBL_RevID*)revID
                               status: (CBLStatus*)outStatus;

/** Uses the "digest" field of the attachment dict to look up the attachment in the store.
    Input dict must come from an already-saved revision. */
- (CBL_Attachment*) attachmentForDict: (NSDictionary*)info
                                named: (NSString*)filename
                               status: (CBLStatus*)outStatus;

- (NSString*) pathForPendingAttachmentWithDict: (NSDictionary*)attachInfo;

/** Deletes obsolete attachments from the database and blob store. */
- (BOOL) garbageCollectAttachments: (NSError**)outError;

- (void) rememberAttachmentWriter: (CBL_BlobStoreWriter*)writer;
- (void) rememberAttachmentWriter: (CBL_BlobStoreWriter*)writer forDigest:(NSString*)digest;
- (void) rememberAttachmentWritersForDigests: (NSDictionary*)writersByDigests;
#if DEBUG
- (id) attachmentWriterForAttachment: (NSDictionary*)attachment;
#endif

@end
