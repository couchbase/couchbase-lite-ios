//
//  CBLBlobStore.m
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLBlobStore.h"
#import "CBLInternal.h"
#import "CBLStringBytes.h"
#import "CBLCoreBridge.h"
#import "CBLBlobStream.h"
#include "c4BlobStore.h"

@implementation CBLBlobStore
{
    C4BlobStore* _blobStore;
}

- (instancetype)initWithPath:(NSString *)path flags:(const C4DatabaseFlags)flags encryptionKey:(const C4EncryptionKey *)encryptionKey error:(NSError *__autoreleasing *)error
{
    self = [super init];
    if(self) {
        CBLStringBytes bPath(path);
        C4Error err;
        _blobStore = c4blob_openStore(bPath, flags, encryptionKey, &err);
        if(!_blobStore) {
            convertError(err, error);
            return nil;
        }
    }
    
    return self;
}

- (BOOL)write:(CBLBlob *)blob error:(NSError *__autoreleasing *)error {
    return [blob install:_blobStore error:error];
}

- (CBLBlobStream *)dataForBlobWithDigest:(NSString *)digest error:(NSError *__autoreleasing *)error {
    CBLStringBytes bDigest(digest);
    C4BlobKey key;
    if(!c4blob_keyFromString(bDigest, &key)) {
        if(error != nil) {
            NSString *desc = [NSString stringWithFormat:@"Failed to create a key from %@", digest];
            *error = [NSError errorWithDomain:@"LiteCore" code:kC4ErrorCorruptData userInfo:
                      @{NSLocalizedDescriptionKey:desc}];
            return nil;
        }
    }
    
    C4Error err;
    C4ReadStream *readStream = c4blob_openReadStream(_blobStore, key, &err);
    if(!readStream) {
        convertError(err, error);
        return nil;
    }
    
    return [[CBLBlobStream alloc] initWithStore:_blobStore key:key error:error];
}

- (void)dealloc {
    c4blob_freeStore(_blobStore);
}

@end
