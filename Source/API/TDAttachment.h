//
//  TouchAttachment.h
//  TouchDB
//
//  Created by Jens Alfke on 6/21/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDocument, TDRevision;


/** A binary attachment to a document revision.
    Existing attachments can be gotten from -[TDRevision attachmentNamed:].
    To add a new attachment, call -initWithContentType:body: and then put the attachment object as a value in the "_attachments" dictionary of the properties when you create a new revision. */
@interface TDAttachment : NSObject
{
    @private
    TDRevision* _rev;
    NSString* _name;
    NSDictionary* _metadata;
    id _body;
}

/** Creates a new attachment that doesn't belong to any revision.
    This object can then be added as a value in a new revision's _attachments dictionary; it will be converted to JSON when saved.
    @param contentType  The MIME type
    @param body  The attachment body; this can either be an NSData object, or an NSURL pointing to a (local) file. */
- (id) initWithContentType: (NSString*)contentType
                      body: (id)body;

/** The owning document revision. */
@property (readonly) TDRevision* revision;

/** The owning document. */
@property (readonly) TDDocument* document;

/** The filename. */
@property (readonly, copy) NSString* name;

/** The MIME type of the contents. */
@property (readonly) NSString* contentType;

/** The length in bytes of the contents. */
@property (readonly) UInt64 length;

/** The TouchDB metadata about the attachment, that lives in the document. */
@property (readonly) NSDictionary* metadata;

/** The body data. */
@property (readonly) NSData* body;

/** Updates the body, creating a new document revision in the process.
    If all you need to do to a document is update a single attachment this is an easy way to do it; but if you need to change multiple attachments, or change other body properties, do them in one step by calling -putProperties:error: on the revision or document. */
- (TDAttachment*) updateBody: (NSData*)body
                    contentType: (NSString*)contentType
                          error: (NSError**)outError;

@end
