//
//  CBLDatabase+Attachments.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase+Internal.h"
#import "CBL_BlobStore.h"
@class CBL_Revision, CBLMultipartWriter, CBL_Attachment;


/** Types of encoding/compression of stored attachments. */
typedef enum {
    kCBLAttachmentEncodingNone,
    kCBLAttachmentEncodingGZIP
} CBLAttachmentEncoding;


@interface CBLDatabase (Attachments)

@property (readonly) NSString* attachmentStorePath;

+ (NSString*) blobKeyToDigest: (CBLBlobKey)key;

/** Creates a CBL_BlobStoreWriter object that can be used to stream an attachment to the store. */
- (CBL_BlobStoreWriter*) attachmentWriter;

/** Scans the rev's _attachments dictionary, adding inline attachment data to the blob-store
    and turning all the attachments into stubs. */
- (BOOL) processAttachmentsForRevision: (CBL_MutableRevision*)rev
                             prevRevID: (NSString*)prevRevID
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

/** Generates a MIME multipart writer for a revision, with separate body parts for each attachment whose "follows" property is set. */
- (CBLMultipartWriter*) multipartWriterForRevision: (CBL_Revision*)rev
                                      contentType: (NSString*)contentType;

/** Returns a CBL_Attachment for an attachment in a stored revision. */
- (CBL_Attachment*) attachmentForRevision: (CBL_Revision*)rev
                                    named: (NSString*)filename
                                   status: (CBLStatus*)outStatus;

/** Uses the "digest" field of the attachment dict to look up the attachment in the store.
    Input dict must come from an already-saved revision. */
- (CBL_Attachment*) attachmentForDict: (NSDictionary*)info
                                named: (NSString*)filename
                               status: (CBLStatus*)outStatus;

- (NSString*) pathForPendingAttachmentWithDict: (NSDictionary*)attachInfo;

/** Deletes obsolete attachments from the database and blob store. */
- (BOOL) garbageCollectAttachments: (NSError**)outError;

/** Updates or deletes an attachment, creating a new document revision in the process.
    Used by the PUT / DELETE methods called on attachment URLs. */
- (CBL_Revision*) updateAttachment: (NSString*)filename
                              body: (CBL_BlobStoreWriter*)body
                              type: (NSString*)contentType
                          encoding: (CBLAttachmentEncoding)encoding
                           ofDocID: (NSString*)docID
                             revID: (NSString*)oldRevID
                            status: (CBLStatus*)outStatus
                             error: (NSError**)outError;

@end
