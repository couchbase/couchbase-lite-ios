//
//  CBLAttachment.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/21/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDocument, CBLRevision, CBLSavedRevision;

#if __has_feature(nullability) // Xcode 6.3+
#pragma clang assume_nonnull begin
#else
#define nullable
#define __nullable
#endif


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
@property (readonly, nullable) NSString* contentType;

/** The length in bytes of the contents. */
@property (readonly) UInt64 length;

/** The CouchbaseLite metadata about the attachment, that lives in the document. */
@property (readonly) NSDictionary* metadata;

/** The data of the attachment. */
@property (readonly, nullable) NSData* content;

/** Returns a stream from which you can read the data of the attachment.
    Remember to close it when you're done. */
- (NSInputStream*) openContentStream;

/** The (file:) URL of the file containing the contents.
    This property is somewhat deprecated and is made available only for use with platform APIs that
    require file paths/URLs, e.g. some media playback APIs. Whenever possible, use the `content`
    property or the `openContentStream` method instead.
    The file must be treated as read-only! DO NOT MODIFY OR DELETE IT.
    If the database is encrypted, attachment files are also encrypted and not directly readable,
    so this property will return nil. */
@property (readonly, nullable) NSURL* contentURL;

@end


#if __has_feature(nullability)
#pragma clang assume_nonnull end
#endif
