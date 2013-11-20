//
//  CBLAttachment.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/21/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDocument, CBLRevision, CBLSavedRevision;


/** A binary attachment to a document revision.
    Existing attachments can be gotten from -[CBLRevision attachmentNamed:].
    New attachments can be created by calling the -setAttachment:... methods of CBLNewRevision or
    CBLModel. */
@interface CBLAttachment : NSObject

/** The owning document revision. */
@property (readonly, retain) CBLRevision* revision;

/** The owning document. */
@property (readonly) CBLDocument* document;

/** The filename. */
@property (readonly, copy) NSString* name;

/** The MIME type of the contents. */
@property (readonly) NSString* contentType;

/** The length in bytes of the contents. */
@property (readonly) UInt64 length;

/** The CouchbaseLite metadata about the attachment, that lives in the document. */
@property (readonly) NSDictionary* metadata;

/** The data of the attachment. */
@property (readonly) NSData* content;

/** The URL of the file containing the contents. (This is always a 'file:' URL.)
    This file must be treated as read-only! DO NOT MODIFY OR DELETE IT. */
@property (readonly) NSURL* contentURL;

#ifdef CBL_DEPRECATED
- (instancetype) initWithContentType: (NSString*)contentType
                                body: (id)body __attribute__((deprecated("use CBLNewRevision or CBLModel's -addAttachmentNamed:")));
@property (readonly) NSData* body __attribute__((deprecated("use content")));
@property (readonly) NSURL* bodyURL __attribute__((deprecated("use contentURL")));
- (CBLSavedRevision*) updateBody: (NSData*)body
                     contentType: (NSString*)contentType
                           error: (NSError**)outError __attribute__((deprecated("create a new revision and update the attachment there")));
#endif
@end
