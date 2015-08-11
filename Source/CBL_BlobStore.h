//
//  CBL_BlobStore.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/10/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifdef GNUSTEP
#import <openssl/md5.h>
#import <openssl/sha.h>
#else
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>
#endif

@class CBLSymmetricKey;


/** Key identifying a data blob. This happens to be a SHA-1 digest. */
typedef struct CBLBlobKey {
    uint8_t bytes[SHA_DIGEST_LENGTH];
} CBLBlobKey;


/** A persistent content-addressable store for arbitrary-size data blobs.
    Each blob is stored as a file named by its SHA-1 digest. */
@interface CBL_BlobStore : NSObject

- (instancetype) initWithPath: (NSString*)dir error: (NSError**)outError;

@property (nonatomic) CBLSymmetricKey* encryptionKey;

- (BOOL) hasBlobForKey: (CBLBlobKey)key;
- (NSData*) blobForKey: (CBLBlobKey)key;
- (uint64_t) lengthOfBlobForKey: (CBLBlobKey)key;
- (NSInputStream*) blobInputStreamForKey: (CBLBlobKey)key
                                  length: (UInt64*)outLength;

/** Path to file storing the blob. Returns nil if the blob is encrypted. */
- (NSString*) blobPathForKey: (CBLBlobKey)key;

- (BOOL) storeBlob: (NSData*)blob
       creatingKey: (CBLBlobKey*)outKey;

- (BOOL) deleteBlobForKey: (CBLBlobKey)key;

@property (readonly) NSString* path;
@property (readonly) NSUInteger count;
@property (readonly) NSArray* allKeys;
@property (readonly) UInt64 totalDataSize;

- (NSInteger) deleteBlobsExceptMatching: (BOOL(^)(CBLBlobKey))predicate
                                  error: (NSError**)outError;

+ (CBLBlobKey) keyForBlob: (NSData*)blob;
+ (NSData*) keyDataForBlob: (NSData*)blob;

@end



typedef struct {
    uint8_t bytes[MD5_DIGEST_LENGTH];
} CBLMD5Key;


/** Lets you stream a large attachment to a CBL_BlobStore asynchronously, e.g. from a network download. */
@interface CBL_BlobStoreWriter : NSObject

- (instancetype) initWithStore: (CBL_BlobStore*)store;

@property (copy) NSString* name;

/** Appends data to the blob. Call this when new data is available. */
- (void) appendData: (NSData*)data;

- (void) closeFile;     /**< Closes the temporary file; it can be reopened later. */
- (BOOL) openFile;      /**< Reopens the temporary file for further appends. */
- (void) reset;         /**< Clears the temporary file to 0 bytes (must be open.) */

/** Call this after all the data has been added. */
- (void) finish;

/** Call this to cancel before finishing the data. */
- (void) cancel;

/** Installs a finished blob into the store. */
- (BOOL) install;

/** The number of bytes in the blob. */
@property (readonly) UInt64 length;

/** The contents of the blob. */
@property (readonly) NSData* blobData;

/** After finishing, this is the key for looking up the blob through the CBL_BlobStore. */
@property (readonly) CBLBlobKey blobKey;

/** After finishing, this is the MD5 digest of the blob, in base64 with an "md5-" prefix.
    (This is useful for compatibility with CouchDB, which stores MD5 digests of attachments.) */
@property (readonly) NSString* MD5DigestString;
@property (readonly) NSString* SHA1DigestString;

- (BOOL) verifyDigest: (NSString*)digestString;

/** The location of the temporary file containing the attachment contents.
    Will be nil after -install is called. */
@property (readonly) NSString* filePath;

/** A stream for reading the completed blob. */
- (NSInputStream*) blobInputStream;

@end
