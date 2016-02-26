//
//  BlobStore_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/23/14.
//
//

#import "CBLTestCase.h"
#import "CBL_BlobStore+Internal.h"
#import "CBL_BlobStoreWriter.h"
#import "CBLSymmetricKey.h"


@interface BlobStore_Tests : XCTestCase
@end


@implementation BlobStore_Tests
{
    BOOL encrypt;
    NSString* storePath;
    CBL_BlobStore* store;
}


- (void)invokeTest {
    // Run each test method twice, once plain and once encrypted.
    encrypt = NO;
    [super invokeTest];
    encrypt = YES;
    [super invokeTest];
}

- (void)setUp {
    [super setUp];
    storePath = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CBL_BlobStoreTest"];
    [[NSFileManager defaultManager] removeItemAtPath: storePath error: NULL];
    if (encrypt)
        Log(@"---- Now enabling attachment encryption ----");
    NSError* error;
    store = [[CBL_BlobStore alloc] initWithPath: storePath
                                  encryptionKey: (encrypt ? [[CBLSymmetricKey alloc] init] : nil)
                                          error: &error];
    Assert(store, @"Couldn't create CBL_BlobStore: %@", error.my_compactDescription);

    NSString* encMarkerPath = [storePath stringByAppendingPathComponent: kEncryptionMarkerFilename];
    BOOL markerExists = [[NSFileManager defaultManager] fileExistsAtPath: encMarkerPath
                                                             isDirectory: NULL];
    AssertEq(markerExists, encrypt);
}

- (void)tearDown {
    store = nil;
    [[NSFileManager defaultManager] removeItemAtPath: storePath error: NULL];
    [super tearDown];
}


// Asserts that the raw blob file is cleartext IFF the store is unencrypted.
- (void) verifyRawBlob: (CBLBlobKey)attKey
         withCleartext: (NSData*)cleartext
{
    NSString* path = [store rawPathForKey: attKey];
    NSData* raw = [NSData dataWithContentsOfFile: path];
    Assert(raw != nil);
    if (store.encryptionKey == nil) {
        AssertEqual(raw, cleartext);
    } else {
        AssertEq(memmem(raw.bytes, raw.length, cleartext.bytes, cleartext.length), NULL);
    }
}


- (void) test01_Basic {
    NSData* item = [@"this is an item" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlobKey key, key2;
    Assert([store storeBlob: item creatingKey: &key]);
    Assert([store storeBlob: item creatingKey: &key2]);
    Assert(memcmp(&key, &key2, sizeof(key)) == 0);

    NSData* readItem = [store blobForKey: key];
    AssertEqual(readItem, item);
    [self verifyRawBlob: key withCleartext: item];

    NSString* path = [store blobPathForKey: key];
    AssertEq((path == nil), encrypt);  // path is returned IFF not encrypted
}


- (void) test02_Reopen {
    NSData* item = [@"this is an item" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlobKey key;
    Assert([store storeBlob: item creatingKey: &key]);

    NSError* error;
    CBL_BlobStore* store2 = [[CBL_BlobStore alloc] initWithPath: store.path
                                                  encryptionKey: store.encryptionKey
                                                          error: &error];
    Assert(store2, @"Couldn't re-open store: %@", error.my_compactDescription);

    NSData* readItem = [store2 blobForKey: key];
    AssertEqual(readItem, item);

    readItem = [store blobForKey: key];
    AssertEqual(readItem, item);
    [self verifyRawBlob: key withCleartext: item];
}


- (void) test03_BlobStoreWriter {
    CBL_BlobStoreWriter* writer = [[CBL_BlobStoreWriter alloc] initWithStore: store];
    Assert(writer);

    [writer appendData: [@"part 1, " dataUsingEncoding: NSUTF8StringEncoding]];
    [writer appendData: [@"part 2, " dataUsingEncoding: NSUTF8StringEncoding]];
    [writer appendData: [@"part 3" dataUsingEncoding: NSUTF8StringEncoding]];
    [writer finish];
    Assert([writer install]);

    NSData* expectedData = [@"part 1, part 2, part 3" dataUsingEncoding: NSUTF8StringEncoding];
    NSData* readItem = [store blobForKey: writer.blobKey];
    AssertEqual(readItem, expectedData);
    [self verifyRawBlob: writer.blobKey withCleartext: expectedData];
}


- (void) test04_Rekey {
    NSData* item = [@"this is an item" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlobKey blobKey;
    Assert([store storeBlob: item creatingKey: &blobKey]);

    CBLSymmetricKey* newEncryptionKey = [CBLSymmetricKey new];
    NSError* error;

    Log(@"---- %@ key", (encrypt ? @"Changing" : @"Adding"));
    Assert([store changeEncryptionKey: newEncryptionKey error: &error],
           @"%@ key failed: %@", (encrypt ? @"Changing" : @"Adding"), error);
    AssertEqual(store.encryptionKey, newEncryptionKey);
    AssertEqual([store blobForKey: blobKey], item);

    [self test02_Reopen];

    if (encrypt) {
        Log(@"---- Removing key");
        Assert([store changeEncryptionKey: nil error: &error], @"Removing key failed: %@", error.my_compactDescription);
        AssertEqual(store.encryptionKey, nil);
        AssertEqual([store blobForKey: blobKey], item);
        [self test02_Reopen];
    }
}


- (void) test05_FixMissingEncryption {
    // Tests the recovery from the 1.1 bug where the attachment store isn't encrypted:
    if (encrypt)
        return;

    // Set up the 1.1-style store: no encryption
    NSData* item = [@"this is an item" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlobKey blobKey;
    Assert([store storeBlob: item creatingKey: &blobKey]);

    // Open a new instance on the store directory, but with a key -- this triggers the fix:
    CBLSymmetricKey* encryptionKey = [CBLSymmetricKey new];
    NSError* error;
    store = [[CBL_BlobStore alloc] initWithPath: store.path
                                                  encryptionKey: encryptionKey
                                                          error: &error];
    Assert(store, @"Couldn't re-open store: %@", error.my_compactDescription);
    AssertEqual(store.encryptionKey, encryptionKey);

    // Verify that the store got the "_encrypted" marker file:
    NSString* encMarkerPath = [storePath stringByAppendingPathComponent: kEncryptionMarkerFilename];
    BOOL markerExists = [[NSFileManager defaultManager] fileExistsAtPath: encMarkerPath
                                                             isDirectory: NULL];
    Assert(markerExists);

    // Verify that the attachment is readable:
    NSData* readItem = [store blobForKey: blobKey];
    AssertEqual(readItem, item);

    // ...and encrypted on disk:
    [self verifyRawBlob: blobKey withCleartext: item];
}


@end
