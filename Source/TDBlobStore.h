//
//  TDBlobStore.h
//  TouchDB
//
//  Created by Jens Alfke on 12/10/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>


/** Key identifying a data blob. This happens to be a SHA-1 digest. */
typedef struct {
    uint8_t bytes[20];
} TDBlobKey;


/** A persistent content-addressable store for arbitrary-size data blobs.
    Each blob is stored as a file named by its SHA-1 digest. */
@interface TDBlobStore : NSObject
{
    NSString* _path;
}

- (id) initWithPath: (NSString*)dir error: (NSError**)outError;

- (NSData*) blobForKey: (TDBlobKey)key;

- (BOOL) storeBlob: (NSData*)blob
           creatingKey: (TDBlobKey*)outKey;

@property (readonly) NSUInteger count;
@property (readonly) NSArray* allKeys;
@property (readonly) UInt64 totalDataSize;

- (NSUInteger) deleteBlobsExceptWithKeys: (NSSet*)keysToKeep;

+ (TDBlobKey) keyForBlob: (NSData*)blob;
+ (NSData*) keyDataForBlob: (NSData*)blob;

@end
