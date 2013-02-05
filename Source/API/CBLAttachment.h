//
//  CBLAttachment.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/21/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDocument, CBLRevisionBase, CBLRevision;


/** A binary attachment to a document revision.
    Existing attachments can be gotten from -[CBLRevision attachmentNamed:].
    To add a new attachment, call -initWithContentType:body: and then put the attachment object as a value in the "_attachments" dictionary of the properties when you create a new revision. */
@interface CBLAttachment : NSObject

/** Creates a new attachment that doesn't belong to any revision.
    This object can then be added as a value in a new revision's _attachments dictionary; it will be converted to JSON when saved.
    @param contentType  The MIME type
    @param body  The attachment body; this can either be an NSData object, or an NSURL pointing to a (local) file. */
- (instancetype) initWithContentType: (NSString*)contentType
                                body: (id)body                          __attribute__((nonnull));

/** The owning document revision. */
@property (readonly, retain) CBLRevisionBase* revision;

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

/** The body data. */
@property (readonly) NSData* body;

/** The URL of the file containing the body.
    This is read-only! DO NOT MODIFY OR DELETE THIS FILE. */
@property (readonly) NSURL* bodyURL;

/** Updates the body, creating a new document revision in the process.
    If all you need to do to a document is update a single attachment this is an easy way to do it; but if you need to change multiple attachments, or change other body properties, do them in one step by calling -putProperties:error: on the revision or document.
    @param body  The new body, or nil to delete the attachment.
    @param contentType  The new content type, or nil to leave it the same.
    @param outError  On return, the error (if any). */
- (CBLRevision*) updateBody: (NSData*)body
                 contentType: (NSString*)contentType
                       error: (NSError**)outError;

@end
