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

- (NSData *)dataForBlobWithDigest:(NSString *)digest error:(NSError *__autoreleasing *)error {
    CBLStringBytes bDigest(digest);
    C4BlobKey key;
    if(!c4blob_keyFromString(bDigest, &key)) {
        if(error != nil) {
            *error = [NSError errorWithDomain:@"CouchbaseLite" code:kC4ErrorCorruptData userInfo:nil];
            return nil;
        }
    }
    
    C4Error err;
    C4SliceResult sliceResult = c4blob_getContents(_blobStore, key, &err);
    if(!sliceResult.buf) {
        convertError(err, error);
        return nil;
    }
    
    return [[NSData alloc] initWithBytesNoCopy:(void *)sliceResult.buf length:sliceResult.size deallocator:^(void * _Nonnull bytes, NSUInteger length) {
        c4slice_free((C4Slice){bytes, length});
    }];
}

- (void)dealloc {
    c4blob_freeStore(_blobStore);
}

@end
