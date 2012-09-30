//
//  TDBlobStore_Tests.m
//  TouchDB
//
//  Created by Jens Alfke on 1/31/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDBlobStore.h"
#import "Test.h"


static TDBlobStore* createStore(void) {
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"TDBlobStoreTest"];
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    NSError* error;
    TDBlobStore* store = [[TDBlobStore alloc] initWithPath: path error: &error];
    CAssert(store, @"Couldn't create TDBlobStore: %@", error);
    return store;
}

static void deleteStore(TDBlobStore* store) {
    [[NSFileManager defaultManager] removeItemAtPath: store.path error: NULL];
}


TestCase(TDBlobStoreBasic) {
    TDBlobStore* store = createStore();
    NSData* item = [@"this is an item" dataUsingEncoding: NSUTF8StringEncoding];
    TDBlobKey key, key2;
    CAssert([store storeBlob: item creatingKey: &key]);
    CAssert([store storeBlob: item creatingKey: &key2]);
    CAssert(memcmp(&key, &key2, sizeof(key)) == 0);

    NSData* readItem = [store blobForKey: key];
    CAssertEqual(readItem, item);
    deleteStore(store);
}


TestCase(TDBlobStoreWriter) {
    TDBlobStore* store = createStore();
    TDBlobStoreWriter* writer = [[TDBlobStoreWriter alloc] initWithStore: store];
    CAssert(writer);
    
    [writer appendData: [@"part 1, " dataUsingEncoding: NSUTF8StringEncoding]];
    [writer appendData: [@"part 2, " dataUsingEncoding: NSUTF8StringEncoding]];
    [writer appendData: [@"part 3" dataUsingEncoding: NSUTF8StringEncoding]];
    [writer finish];
    CAssert([writer install]);
    
    NSData* readItem = [store blobForKey: writer.blobKey];
    CAssertEqual(readItem, [@"part 1, part 2, part 3" dataUsingEncoding: NSUTF8StringEncoding]);
    
    deleteStore(store);
}


TestCase(TDBlobStore) {
    RequireTestCase(TDBlobStoreBasic);
    RequireTestCase(TDBlobStoreWriter);
}