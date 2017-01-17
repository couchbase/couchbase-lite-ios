//
//  CBLBlobStore.h
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "c4.h"

@class CBLBlob;

@interface CBLBlobStore : NSObject

- (instancetype)initWithPath:(NSString *)path
                       flags:(const C4DatabaseFlags)flags
               encryptionKey:(const C4EncryptionKey *)encryptionKey
                       error:(NSError **)error;

- (BOOL)write:(CBLBlob *)blob error:(NSError **)error;

- (NSData *)dataForBlobWithDigest:(NSString *)digest error:(NSError **)error;

@end
