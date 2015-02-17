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

/** Modifies a CBL_Revision's _attachments dictionary by changing all attachments with revpos < minRevPos into stubs; and if 'attachmentsFollow' is true, the remaining attachments will be modified to _not_ be stubs but include a "follows" key instead of a body. */
+ (void) stubOutAttachmentsIn: (CBL_MutableRevision*)rev
                 beforeRevPos: (int)minRevPos
            attachmentsFollow: (BOOL)attachmentsFollow;

/** Modifies a CBL_Revision's _attachments dictionary by adding the "data" property to all
    attachments (and removing "stub" and "follows".) GZip-encoded attachments will be unzipped
    unless options contains the flag kCBLLeaveAttachmentsEncoded. */
- (BOOL) expandAttachmentsIn: (CBL_MutableRevision*)rev
                     options: (CBLContentOptions)options
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
                          status: (CBLStatus*)outStatus;

@end
