//
//  CBLBlobStore.h
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "c4.h"

@class CBLBlob, CBLBlobStream;

@interface CBLBlobStore : NSObject

// Create a blob store with the given path, flags, and encryption key
- (instancetype)initWithPath:(NSString *)path
                       flags:(const C4DatabaseFlags)flags
               encryptionKey:(const C4EncryptionKey *)encryptionKey
                       error:(NSError **)error;

// Performs the write of a CBLBlob to disk
- (BOOL)write:(CBLBlob *)blob error:(NSError **)error;

// Creates a stream to the contents of the stored CBLBlob
- (CBLBlobStream *)dataForBlobWithDigest:(NSString *)digest error:(NSError **)error;

@end
