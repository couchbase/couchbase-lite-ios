//
//  BlobStore_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/23/14.
//
//

#import "CBLTestCase.h"
#import "CBL_BlobStore.h"


@interface BlobStore_Tests : XCTestCase
@end


@implementation BlobStore_Tests
{
    NSString* storePath;
    CBL_BlobStore* store;
}


- (void)setUp {
    [super setUp];
    storePath = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CBL_BlobStoreTest"];
    [[NSFileManager defaultManager] removeItemAtPath: storePath error: NULL];
    NSError* error;
    store = [[CBL_BlobStore alloc] initWithPath: storePath error: &error];
    Assert(store, @"Couldn't create CBL_BlobStore: %@", error);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath: storePath error: NULL];
    [super tearDown];
}


- (void) test_CBL_BlobStoreBasic {
    NSData* item = [@"this is an item" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlobKey key, key2;
    Assert([store storeBlob: item creatingKey: &key]);
    Assert([store storeBlob: item creatingKey: &key2]);
    Assert(memcmp(&key, &key2, sizeof(key)) == 0);

    NSData* readItem = [store blobForKey: key];
    AssertEqual(readItem, item);
}


- (void) test_CBL_BlobStoreWriter {
    CBL_BlobStoreWriter* writer = [[CBL_BlobStoreWriter alloc] initWithStore: store];
    Assert(writer);

    [writer appendData: [@"part 1, " dataUsingEncoding: NSUTF8StringEncoding]];
    [writer appendData: [@"part 2, " dataUsingEncoding: NSUTF8StringEncoding]];
    [writer appendData: [@"part 3" dataUsingEncoding: NSUTF8StringEncoding]];
    [writer finish];
    Assert([writer install]);

    NSData* readItem = [store blobForKey: writer.blobKey];
    AssertEqual(readItem, [@"part 1, part 2, part 3" dataUsingEncoding: NSUTF8StringEncoding]);
}


@end
