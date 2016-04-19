//
//  CBLDatabase+REST.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/7/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase+Attachments.h"


@interface CBLDatabase (REST)


- (id) getDesignDocFunction: (NSString*)fnName
                        key: (NSString*)key
                   language: (NSString**)outLanguage;

- (CBLFilterBlock) compileFilterNamed: (NSString*)filterName
                               status: (CBLStatus*)outStatus;


/** Returns a CBL_Attachment for an attachment in a stored revision. */
- (CBL_Attachment*) attachmentForRevision: (CBL_Revision*)rev
                                    named: (NSString*)filename
                                   status: (CBLStatus*)outStatus;

/** Updates or deletes an attachment, creating a new document revision in the process.
    Used by the PUT / DELETE methods called on attachment URLs. */
- (CBL_Revision*) updateAttachment: (NSString*)filename
                              body: (CBL_BlobStoreWriter*)body
                              type: (NSString*)contentType
                          encoding: (CBLAttachmentEncoding)encoding
                           ofDocID: (NSString*)docID
                             revID: (CBL_RevID*)oldRevID
                            source: (NSURL*)source
                            status: (CBLStatus*)outStatus
                             error: (NSError**)outError;

@end
