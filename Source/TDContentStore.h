//
//  TDContentStore.h
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
} TDContentKey;


/** A content-addressable store for large blobs.
    Each blob is stored as a file named by its SHA-1 digest. */
@interface TDContentStore : NSObject
{
    NSString* _path;
}

- (id) initWithPath: (NSString*)dir error: (NSError**)outError;

- (NSData*) contentsForKey: (TDContentKey)key;

- (BOOL) storeContents: (NSData*)contents
           creatingKey: (TDContentKey*)outKey;

@property (readonly) NSUInteger count;
@property (readonly) NSArray* allKeys;

- (NSUInteger) deleteContentsExceptWithKeys: (NSSet*)keysToKeep;

+ (TDContentKey) keyForContents: (NSData*)contents;
+ (NSData*) keyDataForContents: (NSData*)contents;

@end
