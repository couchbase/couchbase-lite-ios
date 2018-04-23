//
//  CBL_BlobStore.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/10/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifdef GNUSTEP
#import <openssl/sha.h>
#else
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>
#endif

@class CBLSymmetricKey, MYAction;


/** Key identifying a data blob. This happens to be a SHA-1 digest. */
typedef struct CBLBlobKey {
    uint8_t bytes[SHA_DIGEST_LENGTH];
} CBLBlobKey;


/** A persistent content-addressable store for arbitrary-size data blobs.
    Each blob is stored as a file named by its SHA-1 digest. */
@interface CBL_BlobStore : NSObject

- (instancetype) initWithPath: (NSString*)dir
                encryptionKey: (CBLSymmetricKey*)encryptionKey
                        error: (NSError**)outError;

/** Changes the encryption key. This will rewrite every blob to a new directory
    and then replace the current directory with it. */
- (BOOL) changeEncryptionKey: (CBLSymmetricKey*)newKey
                       error: (NSError**)outError;

- (MYAction*) actionToChangeEncryptionKey: (CBLSymmetricKey*)newKey;

- (BOOL) hasBlobForKey: (CBLBlobKey)key;
- (NSData*) blobForKey: (CBLBlobKey)key;
- (uint64_t) lengthOfBlobForKey: (CBLBlobKey)key;
- (uint64_t) blobStreamLengthForKey: (CBLBlobKey)key;
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
