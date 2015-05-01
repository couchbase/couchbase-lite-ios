//
//  Replication_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/22/14.
//
//

#import "CBLTestCase.h"
#import <CommonCrypto/CommonCryptor.h>
#import "CBLCookieStorage.h"
#import "CBLManager+Internal.h"


// These dbs will get deleted and overwritten during tests:
#define kPushThenPullDBName @"cbl_replicator_pushpull"
#define kNDocuments 1000
#define kAttSize 1*1024
#define kEncodedDBName @"cbl_replicator_encoding"
#define kScratchDBName @"cbl_replicator_scratch"

// This one's never actually read or written to.
#define kCookieTestDBName @"cbl_replicator_cookies"
// This one is read-only
#define kAttachTestDBName @"attach_test"


@interface CBLDatabase (Internal)
@property (nonatomic, readonly) NSString* path;
@property (readonly) NSString* attachmentStorePath;
@end


@interface Replication_Tests : CBLTestCaseWithDB
@end


@implementation Replication_Tests
{
    CBLReplication* _currentReplication;
    NSUInteger _expectedChangesCount;
    NSArray* _changedCookies;
}


- (void) runReplication: (CBLReplication*)repl expectedChangesCount: (unsigned)expectedChangesCount
{
    Log(@"Waiting for %@ to finish...", repl);
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(replChanged:)
                                                 name: kCBLReplicationChangeNotification
                                               object: repl];
    _currentReplication = repl;
    _expectedChangesCount = expectedChangesCount;

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

    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: kCBLReplicationChangeNotification
                                                  object: _currentReplication];
    _currentReplication = nil;
}


- (void) runReplication: (CBLReplication*)repl
   expectedChangesCount: (unsigned)expectedChangesCount
 expectedChangedCookies: (NSArray*) expectedChangedCookies {

    _changedCookies = nil;

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(cookiesChanged:)
                                                 name: CBLCookieStorageCookiesChangedNotification
                                               object: nil];

    [self runReplication: repl expectedChangesCount: expectedChangesCount];

    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: CBLCookieStorageCookiesChangedNotification
                                                  object: nil];

    Assert (expectedChangedCookies.count == _changedCookies.count);
    for (NSHTTPCookie* cookie in expectedChangedCookies)
        Assert([_changedCookies containsObject: cookie]);
}


- (void) replChanged: (NSNotification*)n {
    Assert(n.object == _currentReplication, @"Wrong replication given to notification");
    Log(@"Replication status=%u; completedChangesCount=%u; changesCount=%u",
        _currentReplication.status, _currentReplication.completedChangesCount, _currentReplication.changesCount);
    Assert(_currentReplication.completedChangesCount <= _currentReplication.changesCount, @"Invalid change counts");
    if (_currentReplication.status == kCBLReplicationStopped) {
        AssertEq(_currentReplication.completedChangesCount, _currentReplication.changesCount);
        if (_expectedChangesCount > 0) {
            AssertNil(_currentReplication.lastError);
            AssertEq(_currentReplication.changesCount, _expectedChangesCount);
        }
    }
}


- (void) cookiesChanged: (NSNotification*)n {
    CBLCookieStorage* storage = n.object;
    _changedCookies = storage.cookies;
}


- (void) test01_CreateReplicators {
    NSURL* const fakeRemoteURL = [NSURL URLWithString: @"http://fake.fake/fakedb"];

    // Create a replication:
    AssertEqual(db.allReplications, @[]);
    CBLReplication* r1 = [db createPushReplication: fakeRemoteURL];
    Assert(r1);

    // Check the replication's properties:
    AssertEq(r1.localDatabase, db);
    AssertEqual(r1.remoteURL, fakeRemoteURL);
    Assert(!r1.pull);
    Assert(!r1.continuous);
    Assert(!r1.createTarget);
    AssertNil(r1.filter);
    AssertNil(r1.filterParams);
    AssertNil(r1.documentIDs);
    AssertNil(r1.headers);

    // Check that the replication hasn't started running:
    Assert(!r1.running);
    AssertEq(r1.status, kCBLReplicationStopped);
    AssertEq(r1.completedChangesCount, 0u);
    AssertEq(r1.changesCount, 0u);
    AssertNil(r1.lastError);

    // Create another replication:
    CBLReplication* r2 = [db createPullReplication: fakeRemoteURL];
    Assert(r2);
    Assert(r2 != r1);

    // Check the replication's properties:
    AssertEq(r2.localDatabase, db);
    AssertEqual(r2.remoteURL, fakeRemoteURL);
    Assert(r2.pull);

    CBLReplication* r3 = [db createPullReplication: fakeRemoteURL];
    Assert(r3 != r2);
    r3.documentIDs = @[@"doc1", @"doc2"];
    AssertEqual(r3.properties, (@{@"continuous": @NO,
                                  @"create_target": @NO,
                                  @"doc_ids": @[@"doc1", @"doc2"],
                                  @"source": @{@"url": @"http://fake.fake/fakedb"},
                                  @"target": db.name}));
#if 0
    CBLStatus status;
    CBL_Replicator* repl = [db.manager replicatorWithProperties: r3.properties
                                                         status: &status];
    AssertEqual(repl.docIDs, r3.documentIDs);
#endif
}


- (void) test02_RunPushReplicationNoSendAttachmentForUpdatedRev {
    //RequireTestCase(CreateReplicators);
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    CBLDocument* doc = [db createDocument];
    
    NSError* error;
    __unused CBLSavedRevision *rev1 = [doc putProperties: @{@"dynamic":@1} error: &error];
    
    Assert(!error);

    unsigned char attachbytes[kAttSize];
    for(int i=0; i<kAttSize; i++) {
        attachbytes[i] = 1;
    }
    
    NSData* attach1 = [NSData dataWithBytes:attachbytes length:kAttSize];
    
    CBLUnsavedRevision *rev2 = [doc newRevision];
    [rev2 setAttachmentNamed: @"attach" withContentType: @"text/plain" content:attach1];
    
    [rev2 save:&error];
    
    Assert(!error);
    
    AssertEq(rev2.attachments.count, (NSUInteger)1);
    AssertEqual(rev2.attachmentNames, [NSArray arrayWithObject: @"attach"]);
    
    Log(@"Pushing 1...");
    CBLReplication* repl = [db createPushReplication: remoteDbURL];
    repl.createTarget = NO;
    [repl start];

    [self runReplication: repl expectedChangesCount: 1];
    AssertNil(repl.lastError);
    
    
    // Add a third revision that doesn't update the attachment:
    Log(@"Updating doc to rev3");
    
    // copy the document
    NSMutableDictionary *contents = [doc.properties mutableCopy];
    
    // toggle value of check property
    contents[@"dynamic"] = @2;
    
    // save the updated document
    [doc putProperties: contents error: &error];
    
    Assert(!error);
    
    Log(@"Pushing 2...");
    repl = [db createPushReplication: remoteDbURL];
    repl.createTarget = NO;
    [repl start];
    
    [self runReplication: repl expectedChangesCount: 1];
    AssertNil(repl.lastError);
}



- (void) test03_RunPushReplication {
    RequireTestCase(CreateReplicators);
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    Log(@"Creating %d documents...", kNDocuments);
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
    [repl start];

    NSSet* unpushed = repl.pendingDocumentIDs;
    AssertEq(unpushed.count, (unsigned)kNDocuments);
    Assert([repl isDocumentPending: [db documentWithID: @"doc-1"]]);
    Assert(![repl isDocumentPending: [db documentWithID: @"nosuchdoc"]]);

    AssertEqual(db.allReplications, @[repl]);
    [self runReplication: repl expectedChangesCount: kNDocuments];
    AssertNil(repl.lastError);
    AssertEqual(db.allReplications, @[]);

    AssertEq(repl.pendingDocumentIDs.count, 0u);
    Assert(![repl isDocumentPending: [db documentWithID: @"doc-1"]]);
}


- (void) test04_RunPullReplication {
    RequireTestCase(RunPushReplication);
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;

    Log(@"Pulling...");
    CBLReplication* repl = [db createPullReplication: remoteDbURL];

    [self runReplication: repl expectedChangesCount: kNDocuments];
    AssertNil(repl.lastError);

    Log(@"Verifying documents...");
    for (int i = 1; i <= kNDocuments; i++) {
        CBLDocument* doc = db[ $sprintf(@"doc-%d", i) ];
        AssertEqual(doc[@"index"], @(i));
        AssertEqual(doc[@"bar"], $false);
    }
}


- (void) test04_ReplicateAttachments {
    // First pull the read-only "attach_test" database:
    NSURL* pullURL = [self remoteTestDBURL: kAttachTestDBName];
    if (!pullURL)
        return;

    Log(@"Pulling from %@...", pullURL);
    CBLReplication* repl = [db createPullReplication: pullURL];
    [self runReplication: repl expectedChangesCount: 0];
    AssertNil(repl.lastError);

    Log(@"Verifying documents...");
    CBLDocument* doc = db[@"oneBigAttachment"];
    CBLAttachment* att = [doc.currentRevision attachmentNamed: @"IMG_0450.MOV"];
    Assert(att);
    AssertEq(att.length, 34120085ul);
    NSData* content = att.content;
    AssertEq(content.length, 34120085ul);

    doc = db[@"extrameta"];
    att = [doc.currentRevision attachmentNamed: @"extra.txt"];
    AssertEqual(att.content, [NSData dataWithBytes: "hello\n" length: 6]);

    // Now push it to the scratch database:
    NSURL* pushURL = [self remoteTestDBURL: kScratchDBName];
    [self eraseRemoteDB: pushURL];
    Log(@"Pushing to %@...", pushURL);
    repl = [db createPushReplication: pushURL];
    [self runReplication: repl expectedChangesCount: 0];
    AssertNil(repl.lastError);
}


- (void) test05_RunReplicationWithError {
    RequireTestCase(CreateReplicators);
    NSURL* const fakeRemoteURL = [self remoteTestDBURL: @"no-such-db"];
    if (!fakeRemoteURL)
        return;

    // Create a replication:
    CBLReplication* r1 = [db createPullReplication: fakeRemoteURL];
    [self runReplication: r1 expectedChangesCount: 0];

    // It should have failed with a 404:
    AssertEq(r1.status, kCBLReplicationStopped);
    AssertEq(r1.completedChangesCount, 0u);
    AssertEq(r1.changesCount, 0u);
    AssertEqual(r1.lastError.domain, CBLHTTPErrorDomain);
    AssertEq(r1.lastError.code, 404);
}


- (NSArray*) remoteTestDBAnchorCerts {
    NSData* certData = [NSData dataWithContentsOfFile: [self pathToTestFile: @"SelfSigned.cer"]];
    Assert(certData, @"Couldn't load cert file");
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert, @"Couldn't parse cert");
    return @[CFBridgingRelease(cert)];
}


- (void) test06_RunSSLReplication {
    RequireTestCase(RunPullReplication);
    NSURL* remoteDbURL = [self remoteSSLTestDBURL: @"public"];
    if (!remoteDbURL)
        return;

    Log(@"Pulling SSL...");
    CBLReplication* repl = [db createPullReplication: remoteDbURL];

    NSArray* serverCerts = [self remoteTestDBAnchorCerts];
    [CBLReplication setAnchorCerts: serverCerts onlyThese: NO];
    [self runReplication: repl expectedChangesCount: 2];
    [CBLReplication setAnchorCerts: nil onlyThese: NO];

    AssertNil(repl.lastError);
    if (repl.lastError)
        return;
    SecCertificateRef gotServerCert = repl.serverCertificate;
    Assert(gotServerCert);
    Assert(CFEqual(gotServerCert, (SecCertificateRef)serverCerts[0]));
}


- (void) test07_ReplicationChannelsProperty {
    NSURL* const fakeRemoteURL = [self remoteTestDBURL: @"no-such-db"];
    if (!fakeRemoteURL)
        return;
    CBLReplication* r1 = [db createPullReplication: fakeRemoteURL];

    AssertNil(r1.channels);
    r1.filter = @"foo/bar";
    AssertNil(r1.channels);
    r1.filterParams = @{@"a": @"b"};
    AssertNil(r1.channels);

    r1.channels = nil;
    AssertEqual(r1.filter, @"foo/bar");
    AssertEqual(r1.filterParams, @{@"a": @"b"});

    r1.channels = @[@"NBC", @"MTV"];
    AssertEqual(r1.channels, (@[@"NBC", @"MTV"]));
    AssertEqual(r1.filter, @"sync_gateway/bychannel");
    AssertEqual(r1.filterParams, @{@"channels": @"NBC,MTV"});

    r1.channels = nil;
    AssertEqual(r1.filter, nil);
    AssertEqual(r1.filterParams, nil);
}


static UInt8 sEncryptionKey[kCCKeySizeAES256];
static UInt8 sEncryptionIV[kCCBlockSizeAES128];


// Tests the CBLReplication.propertiesTransformationBlock API, by encrypting the document's
// "secret" property with AES-256 as it's pushed to the server. The encrypted data is stored in
// an attachment named "(encrypted)".
- (void) test08_ReplicationWithEncoding {
    RequireTestCase(RunPushReplication);
    NSURL* remoteDbURL = [self remoteTestDBURL: kEncodedDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    Log(@"Creating document...");
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
        nuProps[@"_attachments"] = @{@"(encrypted)": @{@"data":[ciphertext base64EncodedStringWithOptions: 0]}};
        Log(@"Encoded document = %@", nuProps);
        return nuProps;
    };

    [repl start];
    [self runReplication: repl expectedChangesCount: 1];
    AssertNil(repl.lastError);
}


// Tests the CBLReplication.propertiesTransformationBlock API, by decrypting the encrypted
// documents produced by ReplicationWithEncoding.
- (void) test09_ReplicationWithDecoding {
    RequireTestCase(ReplicationWithEncoding);
    NSURL* remoteDbURL = [self remoteTestDBURL: kEncodedDBName];
    if (!remoteDbURL)
        return;

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
    [self runReplication: repl expectedChangesCount: 1];
    AssertNil(repl.lastError);

    // Finally, verify the decryption:
    CBLDocument* doc = db[@"seekrit"];
    NSString* plans = doc[@"secret"];
    AssertEqual(plans, @"Attack at dawn");
}


- (void) test10_ReplicationCookie {
    RequireTestCase(CreateReplicators);

    NSURL* remoteDbURL = [self remoteTestDBURL: kCookieTestDBName];
    if (!remoteDbURL)
        return;

    NSHTTPCookie* cookie1 = [NSHTTPCookie cookieWithProperties:
                                @{ NSHTTPCookieName: @"UnitTestCookie1",
                                   NSHTTPCookieOriginURL: remoteDbURL,
                                   NSHTTPCookiePath: remoteDbURL.path,
                                   NSHTTPCookieValue: @"logmein",
                                   NSHTTPCookieExpires: [NSDate dateWithTimeIntervalSinceNow: 10]
                                   }];

    NSHTTPCookie* cookie2 = [NSHTTPCookie cookieWithProperties:
                             @{ NSHTTPCookieName: @"UnitTestCookie2",
                                NSHTTPCookieOriginURL: remoteDbURL,
                                NSHTTPCookiePath: remoteDbURL.path,
                                NSHTTPCookieValue: @"logmein",
                                NSHTTPCookieExpires: [NSDate dateWithTimeIntervalSinceNow: 10]
                                }];

    NSHTTPCookie* cookie3 = [NSHTTPCookie cookieWithProperties:
                             @{ NSHTTPCookieName: @"UnitTestCookie3",
                                NSHTTPCookieOriginURL: remoteDbURL,
                                NSHTTPCookiePath: remoteDbURL.path,
                                NSHTTPCookieValue: @"logmein",
                                NSHTTPCookieExpires: [NSDate dateWithTimeIntervalSinceNow: 10]
                                }];

    CBLReplication* repl = [db createPullReplication: remoteDbURL];

    [repl setCookieNamed: cookie1.name
               withValue: cookie1.value
                    path: cookie1.path
          expirationDate: cookie1.expiresDate
                  secure: cookie1.isSecure];

    [repl setCookieNamed: cookie2.name
               withValue: cookie2.value
                    path: cookie2.path
          expirationDate: cookie2.expiresDate
                  secure: cookie2.isSecure];

    [repl setCookieNamed: cookie3.name
               withValue: cookie3.value
                    path: cookie3.path
          expirationDate: cookie3.expiresDate
                  secure: cookie3.isSecure];

    [repl deleteCookieNamed: cookie2.name];

    [repl start];
    [self runReplication: repl expectedChangesCount: 0 expectedChangedCookies: @[cookie1, cookie3]];
    AssertNil(repl.lastError);

    // Recreate the replicator and delete a cookie:
    repl = [db createPullReplication: remoteDbURL];
    [repl deleteCookieNamed: cookie3.name];
    [repl start];
    [self runReplication: repl expectedChangesCount: 0 expectedChangedCookies: @[cookie1]];
    AssertNil(repl.lastError);
}

- (void) test11_ReplicationWithReplacedDatabase {
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL) {
        Warn(@"Skipping test RunPushReplication (no remote test DB URL)");
        return;
    }
    [self eraseRemoteDB: remoteDbURL];

    // Create pre-populated database:
    NSUInteger numPrePopulatedDocs = 100u;
    Log(@"Creating %lu pre-populated documents...", (unsigned long)numPrePopulatedDocs);

    NSError* error;
    CBLDatabase* prePopulateDB = [dbmgr createEmptyDatabaseNamed: @"prepopdb" error: &error];
    Assert(prePopulateDB, @"Couldn't create db: %@", error);
    NSString* oldDbPath = prePopulateDB.path;

    [prePopulateDB inTransaction:^BOOL{
        for (int i = 1; i <= (int)numPrePopulatedDocs; i++) {
            @autoreleasepool {
                CBLDocument* doc = prePopulateDB[ $sprintf(@"foo-doc-%d", i) ];
                NSError* error;
                [doc putProperties: @{@"index": @(i), @"foo": $true} error: &error];
                AssertNil(error);
            }
        }
        return YES;
    }];

    Log(@"Pushing pre-populated documents ...");
    CBLReplication* pusher = [prePopulateDB createPushReplication: remoteDbURL];
    pusher.createTarget = YES;
    [pusher start];
    [self runReplication: pusher expectedChangesCount: (unsigned)numPrePopulatedDocs];
    AssertEq(pusher.status, kCBLReplicationStopped);
    AssertEq(pusher.completedChangesCount, numPrePopulatedDocs);
    AssertEq(pusher.changesCount, numPrePopulatedDocs);

    Log(@"Pulling pre-populated documents ...");
    CBLReplication* puller = [prePopulateDB createPullReplication: remoteDbURL];
    puller.createTarget = YES;
    [puller start];
    [self runReplication: puller expectedChangesCount: (unsigned)numPrePopulatedDocs];
    AssertEq(puller.status, kCBLReplicationStopped);
    AssertEq(puller.completedChangesCount, numPrePopulatedDocs);
    AssertEq(puller.changesCount, numPrePopulatedDocs);

    // Add some documents to the remote database:
    CBLDatabase* anotherDB = [dbmgr createEmptyDatabaseNamed: @"anotherdb" error: &error];
    Assert(anotherDB, @"Couldn't create db: %@", error);

    NSUInteger numNonPrePopulatedDocs = 100u;
    Log(@"Creating %lu non-pre-populated documents...", (unsigned long)numNonPrePopulatedDocs);
    [anotherDB inTransaction:^BOOL{
        for (int i = 1; i <= (int)numNonPrePopulatedDocs; i++) {
            @autoreleasepool {
                CBLDocument* doc = anotherDB[ $sprintf(@"bar-doc-%d", i) ];
                NSError* error;
                [doc putProperties: @{@"index": @(i), @"bar": $true} error: &error];
                AssertNil(error);
            }
        }
        return YES;
    }];

    Log(@"Pushing non-pre-populated documents ...");
    pusher = [anotherDB createPushReplication: remoteDbURL];
    pusher.createTarget = NO;
    [pusher start];
    [self runReplication: pusher expectedChangesCount: (unsigned)numNonPrePopulatedDocs];
    AssertEq(pusher.status, kCBLReplicationStopped);
    AssertEq(pusher.completedChangesCount, numNonPrePopulatedDocs);
    AssertEq(pusher.changesCount, numNonPrePopulatedDocs);

    // Close pre-populated db before replacing:
    Assert([prePopulateDB close: &error], @"Couldn't close db: %@", error);

    // Import pre-populated database to a new database called 'importdb':
    BOOL replaced = [dbmgr replaceDatabaseNamed: @"importdb"
                               withDatabaseFile: oldDbPath
                                withAttachments: [prePopulateDB attachmentStorePath]
                                          error: &error];
    Assert(replaced);

    CBLDatabase* importDb = [dbmgr databaseNamed:@"importdb" error:&error];

    pusher = [importDb createPushReplication: remoteDbURL];
    pusher.createTarget = NO;
    [pusher start];
    [self runReplication: pusher expectedChangesCount: 0u];
    AssertEq(pusher.status, kCBLReplicationStopped);
    AssertEq(pusher.completedChangesCount, 0u);
    AssertEq(pusher.changesCount, 0u);

    puller = [importDb createPullReplication: remoteDbURL];
    puller.createTarget = NO;
    [puller start];
    [self runReplication: puller expectedChangesCount:(unsigned)numNonPrePopulatedDocs];
    AssertEq(puller.status, kCBLReplicationStopped);
    AssertEq(puller.completedChangesCount, numNonPrePopulatedDocs);
    AssertEq(puller.changesCount, numNonPrePopulatedDocs);

    // Clean up, delete all created databases:
    Assert([prePopulateDB deleteDatabase:&error], @"Couldn't delete db: %@", error);
    Assert([anotherDB deleteDatabase:&error], @"Couldn't delete db: %@", error);
    Assert([importDb deleteDatabase:&error], @"Couldn't delete db: %@", error);
}

- (void) test12_StopIdlePush {
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    // Create a continuous push replicator:
    CBLReplication* pusher = [db createPushReplication: remoteDbURL];
    pusher.continuous = YES;

    // Run the replicator:
    [self runReplication:pusher expectedChangesCount: 0];

    // Make sure the replication is now idle:
    AssertEq(pusher.status, kCBLReplicationIdle);

    // Setup replication change notification observver:
    __block BOOL stopped = NO;
    id observer =
        [[NSNotificationCenter defaultCenter] addObserverForName: kCBLReplicationChangeNotification
                                                          object: pusher
                                                           queue: nil
        usingBlock: ^(NSNotification *note) {
            if (pusher.status == kCBLReplicationStopped)
                stopped = YES;
    }];

    // Stop the replicator:
    [pusher stop];

    // Wait to get a notification after the replication is stopped:
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    while (!stopped && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
    }
    [[NSNotificationCenter defaultCenter] removeObserver: observer];

    // Check result:
    Assert(stopped);
}

- (void) test13_StopIdlePullReplication {
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    // Create a continuous push replicator:
    CBLReplication* puller = [db createPullReplication: remoteDbURL];
    puller.continuous = YES;

    // Run the replicator:
    [self runReplication:puller expectedChangesCount: 0];

    // Make sure the replication is now idle:
    AssertEq(puller.status, kCBLReplicationIdle);

    // Setup replication change notification observver:
    __block BOOL stopped = NO;
    id observer =
    [[NSNotificationCenter defaultCenter] addObserverForName: kCBLReplicationChangeNotification
                                                      object: puller
                                                       queue: nil
                                                  usingBlock: ^(NSNotification *note) {
                                                      if (puller.status == kCBLReplicationStopped)
                                                          stopped = YES;
                                                  }];

    // Stop the replicator:
    [puller stop];

    // Wait to get a notification after the replication is stopped:
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    while (!stopped && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
    }
    [[NSNotificationCenter defaultCenter] removeObserver: observer];

    // Check result:
    Assert(stopped);
}

- (void) test14_PullDocWithStubAttachment {
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    NSMutableDictionary* properties;
    CBLUnsavedRevision* newRev;

    NSError* error;
    CBLDatabase* pushDB = [dbmgr createEmptyDatabaseNamed: @"prepopdb" error: &error];

    // Create a document:
    CBLDocument* doc = [pushDB documentWithID: @"mydoc"];
    CBLSavedRevision* rev1 = [doc putProperties: @{@"foo": @"bar"} error: &error];
    Assert(rev1);

    // Attach an attachment:
    NSUInteger size = 50 * 1024;
    unsigned char attachbytes[size];
    for (NSUInteger i = 0; i < size; i++) {
        attachbytes[i] = 1;
    }
    NSData* attachment = [NSData dataWithBytes: attachbytes length: size];
    newRev = [doc newRevision];
    [newRev setAttachmentNamed: @"myattachment"
               withContentType: @"text/plain; charset=utf-8"
                       content: attachment];
    CBLSavedRevision* rev2 = [newRev save: &error];
    Assert(rev2);

    // Push:
    CBLReplication* pusher = [pushDB createPushReplication: remoteDbURL];
    [self runReplication:pusher expectedChangesCount:1];

    // Pull (The db now has a base doc with an attachment.):
    CBLReplication* puller = [db createPullReplication: remoteDbURL];
    [self runReplication: puller expectedChangesCount: 1];

    // Create a new revision and push:
    properties = doc.userProperties.mutableCopy;
    properties[@"tag"] = @3;

    newRev = [rev2 createRevision];
    newRev.userProperties = properties;
    CBLSavedRevision* rev3 = [newRev save: &error];
    Assert(rev3);

    pusher = [pushDB createPushReplication: remoteDbURL];
    [self runReplication: pusher expectedChangesCount: 1];

    // Create another revision and push:
    properties = doc.userProperties.mutableCopy;
    properties[@"tag"] = @4;

    newRev = [rev3 createRevision];
    newRev.userProperties = properties;
    CBLSavedRevision* rev4 = [newRev save: &error];
    Assert(rev4);

    pusher = [pushDB createPushReplication: remoteDbURL];
    [self runReplication: pusher expectedChangesCount: 1];

    // Pull without any errors:
    puller = [db createPullReplication: remoteDbURL];
    [self runReplication: puller expectedChangesCount: 1];

    Assert([pushDB deleteDatabase: &error], @"Couldn't delete db: %@", error);
}

- (void) test15_PushShouldNotSendNonModifiedAttachment {
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    CBLUnsavedRevision* newRev;
    NSError* error;

    // Create a document:
    CBLDocument* doc = [db documentWithID: @"mydoc"];
    CBLSavedRevision* rev1 = [doc putProperties: @{@"foo": @"bar"} error: &error];
    Assert(rev1);

    // Attach an attachment:
    NSUInteger size = 50 * 1024;
    unsigned char attachbytes[size];
    for (NSUInteger i = 0; i < size; i++) {
        attachbytes[i] = 1;
    }
    NSData* attachment = [NSData dataWithBytes: attachbytes length: size];
    newRev = [doc newRevision];
    [newRev setAttachmentNamed: @"myattachment"
               withContentType: @"text/plain; charset=utf-8"
                       content: attachment];
    CBLSavedRevision* rev2 = [newRev save: &error];
    Assert(rev2);

    // Push:
    CBLReplication* pusher = [db createPushReplication: remoteDbURL];
    [self runReplication:pusher expectedChangesCount:1];

    NSMutableDictionary* properties = doc.userProperties.mutableCopy;
    properties[@"tag"] = @3;

    newRev = [rev2 createRevision];
    newRev.userProperties = properties;
    CBLSavedRevision* rev3 = [newRev save: &error];
    Assert(rev3);

    pusher = [db createPushReplication: remoteDbURL];
    [self runReplication: pusher expectedChangesCount: 1];

    // Implicitly verify the result by checking the revpos of the document on the Sync Gateway.
    NSURL* allDocsURL = [remoteDbURL URLByAppendingPathComponent: @"mydoc"];
    NSData* data = [NSData dataWithContentsOfURL: allDocsURL];
    Assert(data);
    NSDictionary* response = [CBLJSON JSONObjectWithData: data options: 0 error: NULL];
    NSDictionary* attachments = response[@"_attachments"];
    Assert(attachments);
    NSDictionary* myAttachment = attachments[@"myattachment"];
    Assert(myAttachment);
    Assert(myAttachment[@"revpos"]);
    int revpos = [myAttachment[@"revpos"] intValue];
    AssertEq(revpos, 2);
}


- (void) test26_CloseDabaseOneTimeReplication {
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSString* dbPath = [dbmgr pathForDatabaseNamed: db.name];
    NSString *dbWALPath = [dbPath stringByAppendingString:@"-wal"];

    // Add some documents:
    for (NSUInteger i = 0; i < 10; i++) {
        NSError* error;
        CBLDocument* doc = [db createDocument];
        CBLSavedRevision* rev = [doc putProperties:@{@"foo":@"bar"} error:&error];
        Assert(rev, @"Error creating a new document: %@", error);
    }

    // Push documents:
    CBLReplication* pusher = [db createPushReplication: remoteDbURL];
    pusher.continuous = NO;
    [self runReplication:pusher expectedChangesCount:10];

    // Close Database:
    NSError* error;
    BOOL success = [db close: &error];
    Assert(success, @"Couldn't close database: %@", error);

    Assert([[db allReplications] count] == 0);

    // If the WAL file exists, the size of the file should be zero:
    if ([fmgr fileExistsAtPath:dbWALPath]) {
        NSDictionary* attrs = [fmgr attributesOfItemAtPath: dbWALPath error: NULL];
        Assert(attrs.fileSize == 0);
    }

    // Erase test db:
    [self eraseTestDB];

    // Pull documents:
    CBLReplication* pull = [db createPullReplication: remoteDbURL];
    pull.continuous = NO;
    [self runReplication:pull expectedChangesCount:10];

    // Close Database:
    success = [db close: &error];
    Assert(success, @"Couldn't close database: %@", error);

    Assert([[db allReplications] count] == 0);

    // If the WAL file exists, the size of the file should be zero:
    if ([fmgr fileExistsAtPath:dbWALPath]) {
        NSDictionary* attrs = [fmgr attributesOfItemAtPath: dbWALPath error: NULL];
        Assert(attrs.fileSize == 0);
    }
}


- (void) test27_CloseDataseContinuousReplication {
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSString* dbPath = [dbmgr pathForDatabaseNamed: db.name];
    NSString *dbWALPath = [dbPath stringByAppendingString:@"-wal"];

    // Add some documents:
    for (NSUInteger i = 0; i < 10; i++) {
        NSError* error;
        CBLDocument* doc = [db createDocument];
        CBLSavedRevision* rev = [doc putProperties:@{@"foo":@"bar"} error:&error];
        Assert(rev, @"Error creating a new document: %@", error);
    }

    // Push documents:
    CBLReplication* pusher = [db createPushReplication: remoteDbURL];
    pusher.continuous = YES;
    [self runReplication:pusher expectedChangesCount:10];

    // Close Database:
    NSError* error;
    BOOL success = [db close: &error];
    Assert(success, @"Couldn't close database: %@", error);

    Assert(pusher.status == kCBLReplicationStopped);
    Assert([[db allReplications] count] == 0);

    // If the WAL file exists, the size of the file should be zero:
    if ([fmgr fileExistsAtPath:dbWALPath]) {
        NSDictionary* attrs = [fmgr attributesOfItemAtPath: dbWALPath error: NULL];
        Assert(attrs.fileSize == 0);
    }

    // Erase test db:
    [self eraseTestDB];

    // Pull documents:
    CBLReplication* pull = [db createPullReplication: remoteDbURL];
    pull.continuous = YES;
    [self runReplication:pull expectedChangesCount:10];

    // Close Database:
    success = [db close: &error];
    Assert(success, @"Couldn't close database: %@", error);

    Assert(pusher.status == kCBLReplicationStopped);
    Assert([[db allReplications] count] == 0);

    // If the WAL file exists, the size of the file should be zero:
    if ([fmgr fileExistsAtPath:dbWALPath]) {
        NSDictionary* attrs = [fmgr attributesOfItemAtPath: dbWALPath error: NULL];
        Assert(attrs.fileSize == 0);
    }
}


@end
