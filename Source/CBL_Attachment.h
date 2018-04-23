//
//  CBL_Attachment.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/3/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase+Attachments.h"
#import "CBL_BlobStore.h"


/** A simple container for attachment metadata. */
@interface CBL_Attachment : NSObject
{
    @public
    // Yes, these are public. They're simple scalar values so it's not really worth
    // creating accessor methods for them all.
    UInt64 length;
    UInt64 encodedLength;
    CBLAttachmentEncoding encoding;
    unsigned revpos;
}

+ (bool) digest: (NSString*)digest toBlobKey: (CBLBlobKey*)outKey;

- (instancetype) initWithName: (NSString*)name contentType: (NSString*)contentType;

- (instancetype) initWithName: (NSString*)name
                         info: (NSDictionary*)attachInfo
                       status: (CBLStatus*)outStatus;

@property (weak) CBLDatabase* database;

@property (readonly, nonatomic) NSString* name;
@property (readonly, nonatomic) NSString* contentType;
@property                       CBLBlobKey blobKey;
@property (readonly, nonatomic) NSString* digest;
@property (readonly, nonatomic) NSString* encodingName;

@property (readonly, nonatomic) BOOL hasContent;
@property (readonly, nonatomic) NSData* encodedContent;  // only if inline or stored in db blob-store
@property (readonly, nonatomic) NSData* content;
@property (readonly, nonatomic) NSURL* contentURL; // only if already stored in db blob-store

@property (readonly) BOOL hasBlobKey;
@property (readonly) BOOL isValid;

@property (readonly) NSDictionary* asStubDictionary;

/** Equal to the encodedLength if there is an encoding, else length. */
@property (readwrite) uint64_t possiblyEncodedLength;

/** Length of the blob file; zero if encrypted. */
@property (readonly, nonatomic) uint64_t blobStreamLength;

- (NSInputStream*) getContentStreamDecoded: (BOOL)decoded
                                 andLength: (uint64_t*)outLength;

@end
