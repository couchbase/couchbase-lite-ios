//
//  CBL_BlobStore_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/31/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBL_BlobStore.h"
#import "Test.h"


static CBL_BlobStore* createStore(void) {
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CBL_BlobStoreTest"];
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    NSError* error;
    CBL_BlobStore* store = [[CBL_BlobStore alloc] initWithPath: path error: &error];
    CAssert(store, @"Couldn't create CBL_BlobStore: %@", error);
    AfterThisTest(^{
        [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    });
    return store;
}


TestCase(CBL_BlobStoreBasic) {
    CBL_BlobStore* store = createStore();
    NSData* item = [@"this is an item" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlobKey key, key2;
    CAssert([store storeBlob: item creatingKey: &key]);
    CAssert([store storeBlob: item creatingKey: &key2]);
    CAssert(memcmp(&key, &key2, sizeof(key)) == 0);

    NSData* readItem = [store blobForKey: key];
    CAssertEqual(readItem, item);
}


TestCase(CBL_BlobStoreWriter) {
    CBL_BlobStore* store = createStore();
    CBL_BlobStoreWriter* writer = [[CBL_BlobStoreWriter alloc] initWithStore: store];
    CAssert(writer);
    
    [writer appendData: [@"part 1, " dataUsingEncoding: NSUTF8StringEncoding]];
    [writer appendData: [@"part 2, " dataUsingEncoding: NSUTF8StringEncoding]];
    [writer appendData: [@"part 3" dataUsingEncoding: NSUTF8StringEncoding]];
    [writer finish];
    CAssert([writer install]);
    
    NSData* readItem = [store blobForKey: writer.blobKey];
    CAssertEqual(readItem, [@"part 1, part 2, part 3" dataUsingEncoding: NSUTF8StringEncoding]);
}


TestCase(CBL_BlobStore) {
    RequireTestCase(CBL_BlobStoreBasic);
    RequireTestCase(CBL_BlobStoreWriter);
}
