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


/** Key identifying a data blob. This happens to be a SHA-1 digest. */
typedef struct CBLBlobKey {
    uint8_t bytes[SHA_DIGEST_LENGTH];
} CBLBlobKey;


/** A persistent content-addressable store for arbitrary-size data blobs.
    Each blob is stored as a file named by its SHA-1 digest. */
@interface CBL_BlobStore : NSObject

- (instancetype) initWithPath: (NSString*)dir error: (NSError**)outError;

#if TARGET_OS_IPHONE
/** Sets iOS file protection. Defaults to CompleteUntilFirstUserAuthentication. */
@property (nonatomic) NSDataWritingOptions fileProtection;
#endif

- (NSData*) blobForKey: (CBLBlobKey)key;
- (NSInputStream*) blobInputStreamForKey: (CBLBlobKey)key
                                  length: (UInt64*)outLength;

- (BOOL) storeBlob: (NSData*)blob
       creatingKey: (CBLBlobKey*)outKey;

@property (readonly) NSString* path;
@property (readonly) NSUInteger count;
@property (readonly) NSArray* allKeys;
@property (readonly) UInt64 totalDataSize;

- (NSInteger) deleteBlobsExceptWithKeys: (NSSet*)keysToKeep;

+ (CBLBlobKey) keyForBlob: (NSData*)blob;
+ (NSData*) keyDataForBlob: (NSData*)blob;

/** Returns the path of the file storing the attachment with the given key, or nil.
    DO NOT MODIFY THIS FILE! */
- (NSString*) pathForKey: (CBLBlobKey)key;

@end



typedef struct {
    uint8_t bytes[MD5_DIGEST_LENGTH];
} CBLMD5Key;


/** Lets you stream a large attachment to a CBL_BlobStore asynchronously, e.g. from a network download. */
@interface CBL_BlobStoreWriter : NSObject {
@private
    CBL_BlobStore* _store;
    NSString* _tempPath;
    NSFileHandle* _out;
    UInt64 _length;
    SHA_CTX _shaCtx;
    MD5_CTX _md5Ctx;
    CBLBlobKey _blobKey;
    CBLMD5Key _MD5Digest;
}

- (instancetype) initWithStore: (CBL_BlobStore*)store;

/** Appends data to the blob. Call this when new data is available. */
- (void) appendData: (NSData*)data;

/** Call this after all the data has been added. */
- (void) finish;

/** Call this to cancel before finishing the data. */
- (void) cancel;

/** Installs a finished blob into the store. */
- (BOOL) install;

/** The number of bytes in the blob. */
@property (readonly) UInt64 length;

/** After finishing, this is the key for looking up the blob through the CBL_BlobStore. */
@property (readonly) CBLBlobKey blobKey;

/** After finishing, this is the MD5 digest of the blob, in base64 with an "md5-" prefix.
    (This is useful for compatibility with CouchDB, which stores MD5 digests of attachments.) */
@property (readonly) NSString* MD5DigestString;
@property (readonly) NSString* SHA1DigestString;

/** The location of the temporary file containing the attachment contents.
    Will be nil after -install is called. */
@property (readonly) NSString* filePath;

@end
