//
//  ReplicationAPITests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/16/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//

#import "CouchbaseLite.h"
#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"
#import "Test.h"
#import <CommonCrypto/CommonCryptor.h>


#if DEBUG


// This db will get deleted and overwritten during every test.
#define kPushThenPullDBName @"cbl_replicator_pushpull"
#define kNDocuments 1000
#define kAttSize 1*1024
// This one too.
#define kEncodedDBName @"cbl_replicator_encoding"
// This one's never actually read or written to.
#define kCookieTestDBName @"cbl_replicator_cookies"


@interface CBL_ReplicationObserverHelper : NSObject
- (instancetype) initWithReplication: (CBLReplication*)repl;
@property NSUInteger expectedChangesCount;
@end


@implementation CBL_ReplicationObserverHelper
{
    CBLReplication* _repl;
}

@synthesize expectedChangesCount=_expectedChangesCount;

- (instancetype) initWithReplication: (CBLReplication*)repl {
    Assert(repl);
    self = [super init];
    if (self) {
        _repl = repl;
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(replChanged:)
                                                     name: kCBLReplicationChangeNotification
                                                   object: _repl];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

- (void) replChanged: (NSNotification*)n {
    AssertEq(n.object, _repl);
    Log(@"Replication status=%u; completedChangesCount=%u; changesCount=%u",
        _repl.status, _repl.completedChangesCount, _repl.changesCount);
    CAssert(_repl.completedChangesCount <= _repl.changesCount);
    if (_repl.status == kCBLReplicationStopped) {
        AssertEq(_repl.completedChangesCount, _repl.changesCount);
        if (_expectedChangesCount > 0)
            AssertEq(_repl.changesCount, _expectedChangesCount);
    }
}

@end



static CBLDatabase* createEmptyManagerAndDb(void) {
    CBLManager* mgr = [CBLManager createEmptyAtTemporaryPath: @"CBL_ReplicatorTests"];
    NSError* error;
    CBLDatabase* db = [mgr databaseNamed: @"db" error: &error];
    CAssert(db);
    return db;
}


static void runReplication(CBLReplication* repl, unsigned expectedChangesCount) {
    Log(@"Waiting for %@ to finish...", repl);
    CBL_ReplicationObserverHelper *observer = [[CBL_ReplicationObserverHelper alloc] initWithReplication: repl];
    observer.expectedChangesCount = expectedChangesCount;
    bool started = false, done = false;
    [repl start];
    CFAbsoluteTime lastTime = 0;
    while (!done) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]])
            break;
        if (repl.running)
            started = true;
        if (started && (repl.status == kCBLReplicationStopped ||
                        repl.status == kCBLReplicationIdle))
            done = true;

        // Replication runs on a background thread, so the main runloop should not be blocked.
        // Make sure it's spinning in a timely manner:
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (lastTime > 0 && now-lastTime > 0.25)
            Warn(@"Runloop was blocked for %g sec", now-lastTime);
        lastTime = now;
    }
    Log(@"...replicator finished. mode=%u, progress %u/%u, error=%@",
        repl.status, repl.completedChangesCount, repl.changesCount, repl.lastError);
    observer = nil;
}


TestCase(CreateReplicators) {
    NSURL* const fakeRemoteURL = [NSURL URLWithString: @"http://fake.fake/fakedb"];
    CBLDatabase* db = createEmptyManagerAndDb();

    // Create a replication:
    CAssertEqual(db.allReplications, @[]);
    CBLReplication* r1 = [db createPushReplication: fakeRemoteURL];
    CAssert(r1);

    // Check the replication's properties:
    CAssertEq(r1.localDatabase, db);
    CAssertEqual(r1.remoteURL, fakeRemoteURL);
    CAssert(!r1.pull);
    CAssert(!r1.continuous);
    CAssert(!r1.createTarget);
    CAssertNil(r1.filter);
    CAssertNil(r1.filterParams);
    CAssertNil(r1.documentIDs);
    CAssertNil(r1.headers);

    // Check that the replication hasn't started running:
    CAssert(!r1.running);
    CAssertEq(r1.status, kCBLReplicationStopped);
    CAssertEq(r1.completedChangesCount, 0u);
    CAssertEq(r1.changesCount, 0u);
    CAssertNil(r1.lastError);

    // Create another replication:
    CBLReplication* r2 = [db createPullReplication: fakeRemoteURL];
    CAssert(r2);
    CAssert(r2 != r1);

    // Check the replication's properties:
    CAssertEq(r2.localDatabase, db);
    CAssertEqual(r2.remoteURL, fakeRemoteURL);
    CAssert(r2.pull);

    CBLReplication* r3 = [db createPullReplication: fakeRemoteURL];
    CAssert(r3 != r2);
    r3.documentIDs = @[@"doc1", @"doc2"];
    CBLStatus status;
    CBL_Replicator* repl = [db.manager replicatorWithProperties: r3.properties
                                                         status: &status];
    AssertEqual(repl.docIDs, r3.documentIDs);
    [db.manager close];
}

TestCase(RunPushReplicationNoSendAttachmentForUpdatedRev) {
    
    //RequireTestCase(CreateReplicators);
    NSURL* remoteDbURL = RemoteTestDBURL(kPushThenPullDBName);
    if (!remoteDbURL) {
        Warn(@"Skipping test RunPushReplication (no remote test DB URL)");
        return;
    }
    
    Log(@"Creating %d documents...", kNDocuments);
    CBLDatabase* db = createEmptyManagerAndDb();
    
    CBLDocument* doc = [db createDocument];
    
    NSError* error;
    CBLSavedRevision *rev1 = [doc putProperties: @{@"dynamic":@1} error: &error];
    
    CAssert(!error);
    
    CAssert(![db sequenceHasAttachments: rev1.sequence]);
    
    unsigned char attachbytes[kAttSize];
    for(int i=0; i<kAttSize; i++) {
        attachbytes[i] = 1;
    }
    
    NSData* attach1 = [NSData dataWithBytes:attachbytes length:kAttSize];
    
    CBLUnsavedRevision *rev2 = [doc newRevision];
    [rev2 setAttachmentNamed: @"attach" withContentType: @"text/plain" content:attach1];
    
    [rev2 save:&error];
    
    CAssert(!error);
    
    CAssertEq(rev2.attachments.count, (NSUInteger)1);
    CAssertEqual(rev2.attachmentNames, [NSArray arrayWithObject: @"attach"]);
    
    Log(@"Pushing 1...");
    CBLReplication* repl = [db createPushReplication: remoteDbURL];
    repl.createTarget = NO;
    [repl start];
    
    runReplication(repl, 1);
    AssertNil(repl.lastError);
    
    
    // Add a third revision that doesn't update the attachment:
    Log(@"Updating doc to rev3");
    
    // copy the document
    NSMutableDictionary *contents = [doc.properties mutableCopy];
    
    // toggle value of check property
    contents[@"dynamic"] = @2;
    
    // save the updated document
    [doc putProperties: contents error: &error];
    
    CAssert(!error);
    
    Log(@"Pushing 2...");
    repl = [db createPushReplication: remoteDbURL];
    repl.createTarget = NO;
    [repl start];
    
    runReplication(repl, 1);
    AssertNil(repl.lastError);
    
    
    [db.manager close];
}



TestCase(RunPushReplication) {

    RequireTestCase(CreateReplicators);
    NSURL* remoteDbURL = RemoteTestDBURL(kPushThenPullDBName);
    if (!remoteDbURL) {
        Warn(@"Skipping test RunPushReplication (no remote test DB URL)");
        return;
    }
    DeleteRemoteDB(remoteDbURL);

    Log(@"Creating %d documents...", kNDocuments);
    CBLDatabase* db = createEmptyManagerAndDb();
    [db inTransaction:^BOOL{
        for (int i = 1; i <= kNDocuments; i++) {
            @autoreleasepool {
                CBLDocument* doc = db[ $sprintf(@"doc-%d", i) ];
                NSError* error;
                [doc putProperties: @{@"index": @(i), @"bar": $false} error: &error];
                AssertNil(error);
            }
        }
        return YES;
    }];

    Log(@"Pushing...");
    CBLReplication* repl = [db createPushReplication: remoteDbURL];
    repl.createTarget = YES;
    [repl start];
    CAssertEqual(db.allReplications, @[repl]);
    runReplication(repl, kNDocuments);
    AssertNil(repl.lastError);
    CAssertEqual(db.allReplications, @[]);
    [db.manager close];
}


TestCase(RunPullReplication) {
    RequireTestCase(RunPushReplication);
    NSURL* remoteDbURL = RemoteTestDBURL(kPushThenPullDBName);
    if (!remoteDbURL) {
        Warn(@"Skipping test RunPullReplication (no remote test DB URL)");
        return;
    }
    CBLDatabase* db = createEmptyManagerAndDb();

    Log(@"Pulling...");
    CBLReplication* repl = [db createPullReplication: remoteDbURL];

    runReplication(repl, kNDocuments);
    AssertNil(repl.lastError);

    Log(@"Verifying documents...");
    for (int i = 1; i <= kNDocuments; i++) {
        CBLDocument* doc = db[ $sprintf(@"doc-%d", i) ];
        AssertEqual(doc[@"index"], @(i));
        AssertEqual(doc[@"bar"], $false);
    }
    [db.manager close];
}


TestCase(RunReplicationWithError) {
    RequireTestCase(CreateReplicators);
    NSURL* const fakeRemoteURL = RemoteTestDBURL(@"no-such-db");
    CBLDatabase* db = createEmptyManagerAndDb();

    // Create a replication:
    CBLReplication* r1 = [db createPullReplication: fakeRemoteURL];
    runReplication(r1, 0);

    // It should have failed with a 404:
    CAssertEq(r1.status, kCBLReplicationStopped);
    CAssertEq(r1.completedChangesCount, 0u);
    CAssertEq(r1.changesCount, 0u);
    CAssertEqual(r1.lastError.domain, CBLHTTPErrorDomain);
    CAssertEq(r1.lastError.code, 404);

    [db.manager close];
}


TestCase(ReplicationChannelsProperty) {
    CBLDatabase* db = createEmptyManagerAndDb();
    NSURL* const fakeRemoteURL = RemoteTestDBURL(@"no-such-db");
    CBLReplication* r1 = [db createPullReplication: fakeRemoteURL];

    CAssertNil(r1.channels);
    r1.filter = @"foo/bar";
    CAssertNil(r1.channels);
    r1.filterParams = @{@"a": @"b"};
    CAssertNil(r1.channels);

    r1.channels = nil;
    CAssertEqual(r1.filter, @"foo/bar");
    CAssertEqual(r1.filterParams, @{@"a": @"b"});

    r1.channels = @[@"NBC", @"MTV"];
    CAssertEqual(r1.channels, (@[@"NBC", @"MTV"]));
    CAssertEqual(r1.filter, @"sync_gateway/bychannel");
    CAssertEqual(r1.filterParams, @{@"channels": @"NBC,MTV"});

    r1.channels = nil;
    CAssertEqual(r1.filter, nil);
    CAssertEqual(r1.filterParams, nil);

    [db.manager close];
}


static UInt8 sEncryptionKey[kCCKeySizeAES256];
static UInt8 sEncryptionIV[kCCBlockSizeAES128];


// Tests the CBLReplication.propertiesTransformationBlock API, by encrypting the document's
// "secret" property with AES-256 as it's pushed to the server. The encrypted data is stored in
// an attachment named "(encrypted)".
TestCase(ReplicationWithEncoding) {
    RequireTestCase(RunPushReplication);
    NSURL* remoteDbURL = RemoteTestDBURL(kEncodedDBName);
    if (!remoteDbURL) {
        Warn(@"Skipping test ReplicationWithEncoding (no remote test DB URL)");
        return;
    }
    DeleteRemoteDB(remoteDbURL);

    Log(@"Creating document...");
    CBLDatabase* db = createEmptyManagerAndDb();
    CBLDocument* doc = db[@"seekrit"];
    [doc putProperties: @{@"secret": @"Attack at dawn"} error: NULL];

    Log(@"Pushing...");
    CBLReplication* repl = [db createPushReplication: remoteDbURL];
    repl.createTarget = YES;

    SecRandomCopyBytes(kSecRandomDefault, sizeof(sEncryptionKey), sEncryptionKey);
    SecRandomCopyBytes(kSecRandomDefault, sizeof(sEncryptionIV), sEncryptionIV);

    repl.propertiesTransformationBlock = ^NSDictionary*(NSDictionary* props) {
        NSData* cleartext = [props[@"secret"] dataUsingEncoding: NSUTF8StringEncoding];
        Assert(cleartext);
        NSMutableData* ciphertext = [NSMutableData dataWithLength: cleartext.length + 128];
        size_t encryptedLength;
        CCCryptorStatus status = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                         sEncryptionKey, sizeof(sEncryptionKey), sEncryptionIV,
                                         cleartext.bytes, cleartext.length,
                                         ciphertext.mutableBytes, ciphertext.length, &encryptedLength);
        AssertEq(status, kCCSuccess);
        Assert(encryptedLength > 0);
        ciphertext.length = encryptedLength;
        Log(@"Ciphertext = %@", ciphertext);

        NSMutableDictionary* nuProps = [props mutableCopy];
        [nuProps removeObjectForKey: @"secret"];
        nuProps[@"_attachments"] = @{@"(encrypted)": @{@"data":[ciphertext base64Encoding]}};
        Log(@"Encoded document = %@", nuProps);
        return nuProps;
    };

    [repl start];
    runReplication(repl, 1);
    AssertNil(repl.lastError);
    [db.manager close];
}


// Tests the CBLReplication.propertiesTransformationBlock API, by decrypting the encrypted
// documents produced by ReplicationWithEncoding.
TestCase(ReplicationWithDecoding) {
    RequireTestCase(ReplicationWithEncoding);
    NSURL* remoteDbURL = RemoteTestDBURL(kEncodedDBName);
    if (!remoteDbURL) {
        Warn(@"Skipping test ReplicationWithDecoding (no remote test DB URL)");
        return;
    }
    CBLDatabase* db = createEmptyManagerAndDb();

    Log(@"Pulling...");
    CBLReplication* repl = [db createPullReplication: remoteDbURL];
    repl.propertiesTransformationBlock = ^NSDictionary*(NSDictionary* props) {
        Assert(props.cbl_id);
        Assert(props.cbl_rev);
        NSDictionary* encrypted = (props[@"_attachments"])[@"(encrypted)"];
        if (!encrypted)
            return props;

        NSData* ciphertext;
        NSString* ciphertextStr = $castIf(NSString, encrypted[@"data"]);
        if (ciphertextStr) {
            // Attachment was inline:
            ciphertext = [[NSData alloc] initWithBase64EncodedString: ciphertextStr options: 0];
        } else {
            // The replicator is kind enough to add a temporary "file" property that points to
            // the downloaded attachment:
            NSString* filePath = $castIf(NSString, encrypted[@"file"]);
            Assert(filePath);
            ciphertext = [NSData dataWithContentsOfFile: filePath];
        }
        Assert(ciphertext);
        NSMutableData* cleartext = [NSMutableData dataWithLength: ciphertext.length];

        size_t decryptedLength;
        CCCryptorStatus status = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                         sEncryptionKey, sizeof(sEncryptionKey), sEncryptionIV,
                                         ciphertext.bytes, ciphertext.length,
                                         cleartext.mutableBytes, cleartext.length, &decryptedLength);
        AssertEq(status, kCCSuccess);
        Assert(decryptedLength > 0);
        cleartext.length = decryptedLength;
        Log(@"Cleartext = %@", cleartext);
        NSString* cleartextStr = [[NSString alloc] initWithData: cleartext encoding: NSUTF8StringEncoding];

        NSMutableDictionary* nuProps = [props mutableCopy];
        nuProps[@"secret"] = cleartextStr;
        return nuProps;
    };
    runReplication(repl, 1);
    AssertNil(repl.lastError);

    // Finally, verify the decryption:
    CBLDocument* doc = db[@"seekrit"];
    NSString* plans = doc[@"secret"];
    AssertEqual(plans, @"Attack at dawn");
    [db.manager close];
}


static NSHTTPCookie* cookieForURL(NSURL* url, NSString* name) {
    NSArray* cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL: url];
    for (NSHTTPCookie* cookie in cookies) {
        if ([cookie.name isEqualToString: name])
            return cookie;
    }
    return nil;
}


TestCase(ReplicationCookie) {
    RequireTestCase(CreateReplicators);
    NSURL* remoteDbURL = RemoteTestDBURL(kCookieTestDBName);
    CBLDatabase* db = createEmptyManagerAndDb();

    CBLReplication* repl = [db createPullReplication: remoteDbURL];
    [repl setCookieNamed: @"UnitTestCookie"
               withValue: @"logmein"
                    path: remoteDbURL.path
          expirationDate: [NSDate dateWithTimeIntervalSinceNow: 10]
                  secure: NO];
    NSHTTPCookie* cookie = cookieForURL(remoteDbURL, @"UnitTestCookie");
    AssertEqual(cookie.value, @"logmein");

    [repl deleteCookieNamed: @"UnitTestCookie"];
    cookie = cookieForURL(remoteDbURL, @"UnitTestCookie");
    AssertNil(cookie.value);
}


TestCase(API_Replicator) {
    RequireTestCase(CreateReplicators);
    RequireTestCase(RunReplicationWithError);
    RequireTestCase(ReplicationChannelsProperty);
    RequireTestCase(RunPushReplication);
}


#endif // DEBUG
