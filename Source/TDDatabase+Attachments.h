//
//  TDDatabase+Attachments.h
//  TouchDB
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
@class TDBlobStoreWriter;


/** Types of encoding/compression of stored attachments. */
typedef enum {
    kTDAttachmentEncodingNone,
    kTDAttachmentEncodingGZIP
} TDAttachmentEncoding;


@interface TDDatabase (Attachments)

/** Creates a TDBlobStoreWriter object that can be used to stream an attachment to the store. */
- (TDBlobStoreWriter*) attachmentWriter;

/** Given a newly-added revision, adds the necessary attachment rows to the database and stores inline attachments into the blob store. */
- (TDStatus) processAttachmentsForRevision: (TDRevision*)rev
                        withParentSequence: (SequenceNumber)parentSequence;

/** Constructs an "_attachments" dictionary for a revision, to be inserted in its JSON body. */
- (NSDictionary*) getAttachmentDictForSequence: (SequenceNumber)sequence
                                   withContent: (BOOL)withContent;

/** Returns the content and metadata of an attachment.
    If you pass NULL for the 'outEncoding' parameter, it signifies that you don't care about encodings and just want the 'real' data, so it'll be decoded for you. */
- (NSData*) getAttachmentForSequence: (SequenceNumber)sequence
                               named: (NSString*)filename
                                type: (NSString**)outType
                            encoding: (TDAttachmentEncoding*)outEncoding
                              status: (TDStatus*)outStatus;

/** Deletes obsolete attachments from the database and blob store. */
- (TDStatus) garbageCollectAttachments;

/** Updates or deletes an attachment, creating a new document revision in the process.
    Used by the PUT / DELETE methods called on attachment URLs. */
- (TDRevision*) updateAttachment: (NSString*)filename
                            body: (NSData*)body
                            type: (NSString*)contentType
                        encoding: (TDAttachmentEncoding)encoding
                         ofDocID: (NSString*)docID
                           revID: (NSString*)oldRevID
                          status: (TDStatus*)outStatus;
@end
