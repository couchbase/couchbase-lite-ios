//
//  Replication_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/22/14.
//
//

#import "CBLTestCase.h"
#import "CBLManager+Internal.h"
#import <CommonCrypto/CommonCryptor.h>
#import "CBLCookieStorage.h"
#import "CBL_Body.h"
#import "CBLAttachmentDownloader.h"
#import "CBLRemoteSession.h"
#import "CBLRemoteRequest.h"
#import "CBLOpenIDConnectAuthorizer.h"
#import "CBLRemoteLogin.h"
#import "MYAnonymousIdentity.h"
#import "MYErrorUtils.h"
#import "MYURLUtils.h"


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
@property (nonatomic, readonly) NSString* dir;
@end

@interface Replication_Tests : CBLTestCaseWithDB
@end


@implementation Replication_Tests
{
    CBLReplication* _currentReplication;
    NSUInteger _expectedChangesCount;
    NSArray* _changedCookies;
    BOOL _newReplicator;
    NSTimeInterval _timeout;
}


- (void)invokeTest {
    // Run each test method twice, once with the old replicator and once with the new.
    _newReplicator = NO;
    [super invokeTest];
    if ([[NSUserDefaults standardUserDefaults] boolForKey: @"TestNewReplicator"]) {
        _newReplicator = YES;
        [super invokeTest];
    }
}


- (void) setUp {
    if (_newReplicator)
        Log(@"++++ Now using new replicator");
    [super setUp];
    if (_newReplicator) {
        dbmgr.replicatorClassName = @"CBLBlipReplicator";
        dbmgr.dispatchQueue = dispatch_get_main_queue();
    }
    _timeout = 15.0;
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

    __block bool started = false;
    [repl start];
    Assert(repl.status != kCBLReplicationStopped && repl.status != kCBLReplicationIdle);
    bool done = [self wait: _timeout for: ^BOOL {
        if (repl.running)
            started = true;
        return started && (repl.status == kCBLReplicationStopped ||
                           repl.status == kCBLReplicationIdle);
    }];
    Assert(done, @"Replication failed to complete");
    Log(@"...replicator finished. mode=%u, progress %u/%u, error=%@",
        repl.status, repl.completedChangesCount, repl.changesCount, repl.lastError.my_compactDescription);

    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: kCBLReplicationChangeNotification
                                                  object: _currentReplication];
    _currentReplication = nil;
}


- (void) replChanged: (NSNotification*)n {
    AssertEq(n.object, _currentReplication, @"Wrong replication given to notification");
    Log(@"Replication status=%u; completedChangesCount=%u; changesCount=%u",
        _currentReplication.status, _currentReplication.completedChangesCount, _currentReplication.changesCount);
    if (!_newReplicator) {
        //TODO: New replicator sometimes has too-high completedChangesCount
        Assert(_currentReplication.completedChangesCount <= _currentReplication.changesCount, @"Invalid change counts");
    }
    if (_currentReplication.status == kCBLReplicationStopped) {
        AssertEq(_currentReplication.completedChangesCount, _currentReplication.changesCount);
        if (_expectedChangesCount > 0) {
            AssertNil(_currentReplication.lastError);
            AssertEq(_currentReplication.changesCount, _expectedChangesCount);
        }
    }
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


- (void) test03_RunPushReplicationNoSendAttachmentForUpdatedRev {
    //RequireTestCase(CreateReplicators);
    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    CBLDocument* doc = [db createDocument];
    
    NSError* error;
    __unused CBLSavedRevision *rev1 = [doc putProperties: @{@"dynamic":@1} error: &error];
    
    AssertNil(error);

    unsigned char attachbytes[kAttSize];
    for(int i=0; i<kAttSize; i++) {
        attachbytes[i] = 1;
    }
    
    NSData* attach1 = [NSData dataWithBytes:attachbytes length:kAttSize];
    
    CBLUnsavedRevision *rev2 = [doc newRevision];
    [rev2 setAttachmentNamed: @"attach" withContentType: @"text/plain" content:attach1];
    
    [rev2 save:&error];
    
    AssertNil(error);
    
    AssertEq(rev2.attachments.count, (NSUInteger)1);
    AssertEqual(rev2.attachmentNames, [NSArray arrayWithObject: @"attach"]);
    
    Log(@"Pushing 1...");
    CBLReplication* repl = [db createPushReplication: remoteDbURL];
    repl.createTarget = NO;
    [repl start];

    unsigned expectedChangesCount = _newReplicator ? 2 : 1; // New repl counts attachments
    [self runReplication: repl expectedChangesCount: expectedChangesCount];
    AssertNil(repl.lastError);
    
    
    // Add a third revision that doesn't update the attachment:
    Log(@"Updating doc to rev3");
    
    // copy the document
    NSMutableDictionary *contents = [doc.properties mutableCopy];
    
    // toggle value of check property
    contents[@"dynamic"] = @2;
    
    // save the updated document
    [doc putProperties: contents error: &error];
    
    AssertNil(error);
    
    Log(@"Pushing 2...");
    repl = [db createPushReplication: remoteDbURL];
    repl.createTarget = NO;
    [repl start];
    
    [self runReplication: repl expectedChangesCount: 1];
    AssertNil(repl.lastError);
}



- (void) test02_RunPushReplication {
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
    _timeout = 30; // There are some big attachments that can take time to transfer to a device

    // First pull the read-only "attach_test" database:
    NSURL* pullURL = [self remoteTestDBURL: kAttachTestDBName];
    if (!pullURL)
        return;

    Log(@"Pulling from %@...", pullURL);
    CBLReplication* repl = [db createPullReplication: pullURL];
//    [self allowWarningsIn: ^{
        // This triggers a warning in CBLSyncConnection because the attach-test db is actually
        // missing an attachment body. It's not a CBL error.
        [self runReplication: repl expectedChangesCount: 0];
//    }];
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
    [self allowWarningsIn:^{
        [self runReplication: r1 expectedChangesCount: 0];
    }];

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


- (void) test06_RunSSLReplicationWithClientCert {
    // TODO: This doesn't fully test whether the client cert is sent, because SG currently
    // ignores it. We need to add client-cert support to SG and set up a test database that
    // _requires_ a client cert.
    RequireTestCase(RunPullReplication);
    NSURL* remoteDbURL = [self remoteSSLTestDBURL: @"public"];
    if (!remoteDbURL)
        return;

    Log(@"Pulling SSL...");
    CBLReplication* repl = [db createPullReplication: remoteDbURL];

    NSError* error;
    SecIdentityRef ident = MYGetOrCreateAnonymousIdentity(@"SSLTest",
                                            kMYAnonymousIdentityDefaultExpirationInterval, &error);
    Assert(ident);
    repl.authenticator = [CBLAuthenticator SSLClientCertAuthenticatorWithIdentity: ident
                                                                  supportingCerts: nil];

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

    (void)SecRandomCopyBytes(kSecRandomDefault, sizeof(sEncryptionKey), sEncryptionKey);
    (void)SecRandomCopyBytes(kSecRandomDefault, sizeof(sEncryptionIV), sEncryptionIV);

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
                                   NSHTTPCookieExpires: [NSDate distantFuture]
                                   }];

    NSHTTPCookie* cookie2 = [NSHTTPCookie cookieWithProperties:
                             @{ NSHTTPCookieName: @"UnitTestCookie2",
                                NSHTTPCookieOriginURL: remoteDbURL,
                                NSHTTPCookiePath: remoteDbURL.path,
                                NSHTTPCookieValue: @"logmein",
                                NSHTTPCookieExpires: [NSDate distantFuture]
                                }];

    NSHTTPCookie* cookie3 = [NSHTTPCookie cookieWithProperties:
                             @{ NSHTTPCookieName: @"UnitTestCookie3",
                                NSHTTPCookieOriginURL: remoteDbURL,
                                NSHTTPCookiePath: remoteDbURL.path,
                                NSHTTPCookieValue: @"logmein",
                                NSHTTPCookieExpires: [NSDate distantFuture]
                                }];

    CBLReplication* repl = [db createPullReplication: remoteDbURL];
    repl.continuous = YES;

    // 1: Set and delete cookies before starting the replicator:
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

    // Check cookies:
    NSArray* cookies = repl.cookies;
    AssertEq(cookies.count, 2u);
    AssertEqual(cookies[0], cookie1);
    AssertEqual(cookies[1], cookie3);

    // Run a continuous the replicator:
    [self runReplication: repl expectedChangesCount: 0];

    // 2: Set and delete cookies while the replicator is running:
    [repl setCookieNamed: cookie2.name
               withValue: cookie2.value
                    path: cookie2.path
          expirationDate: cookie2.expiresDate
                  secure: cookie2.isSecure];

    [repl deleteCookieNamed: cookie3.name];

    // Check cookies:
    cookies = repl.cookies;
    AssertEq(cookies.count, 2u);
    AssertEqual(cookies[0], cookie1);
    AssertEqual(cookies[1], cookie2);

    // Stop the replicator:
    [self keyValueObservingExpectationForObject: repl
                                        keyPath: @"status" expectedValue: @(kCBLReplicationStopped)];
    [repl stop];
    [self waitForExpectationsWithTimeout: 2.0 handler: nil];

    // 3: Recreate the replicator (single shot) and delete a cookie:
    Log(@"***** Testing cookie deletion *****");
    repl = [db createPullReplication: remoteDbURL];
    [repl deleteCookieNamed: cookie2.name];
    [repl start];
    [self runReplication: repl expectedChangesCount: 0];
    AssertNil(repl.lastError);

    // Check cookies:
    cookies = repl.cookies;
    AssertEq(cookies.count, 1u);
    AssertEqual(cookies[0], cookie1);
}

- (void) test11_ReplicationWithReplacedDatabase {
    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
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
    NSString* oldDbPath = prePopulateDB.dir;

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
    [self runReplication: puller expectedChangesCount: 0];
    AssertEq(puller.status, kCBLReplicationStopped);

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

    // Import pre-populated database to a new database called 'importdb':
    [dbmgr replaceDatabaseNamed: @"importdb"
                withDatabaseDir: oldDbPath
                          error: &error];

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

- (void) test12_StopIdlePushReplication {
    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
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
    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
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
    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
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
    [self runReplication:pusher expectedChangesCount: (_newReplicator ? 51 : 1)];

    // Pull (The db now has a base doc with an attachment.):
    CBLReplication* puller = [db createPullReplication: remoteDbURL];
    [self runReplication: puller expectedChangesCount: (_newReplicator ? 51 : 1)];

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
    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
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
    [self runReplication:pusher expectedChangesCount: (_newReplicator ? 51 : 1)];

    // Update document body (not attachment)
    NSMutableDictionary* properties = doc.userProperties.mutableCopy;
    properties[@"tag"] = @3;
    newRev = [rev2 createRevision];
    newRev.userProperties = properties;
    CBLSavedRevision* rev3 = [newRev save: &error];
    Assert(rev3);

    // Push again:
    pusher = [db createPushReplication: remoteDbURL];
    [self runReplication: pusher expectedChangesCount: 1];

    // Implicitly verify the result by checking the revpos of the document on the Sync Gateway.
    __block NSDictionary* data;
    NSURL* docUrl = [remoteDbURL URLByAppendingPathComponent: @"mydoc"];
    XCTestExpectation* complete = [self expectationWithDescription: @"didComplete"];
    CBLRemoteRequest *req =
        [[CBLRemoteJSONRequest alloc] initWithMethod: @"GET" URL: docUrl
                                                body: nil
                                        onCompletion:^(id result, NSError *error) {
                                            AssertNil(error);
                                            data = result;
                                            [complete fulfill];
                                        }];
    req.debugAlwaysTrust = YES;
    CBLRemoteSession* session = [[CBLRemoteSession alloc] initWithDelegate: nil];
    [session startRequest: req];
    [self waitForExpectationsWithTimeout: 2.0 handler: nil];

    NSDictionary* attachments = data[@"_attachments"];
    Assert(attachments);
    NSDictionary* myAttachment = attachments[@"myattachment"];
    Assert(myAttachment);
    Assert(myAttachment[@"revpos"]);
    int revpos = [myAttachment[@"revpos"] intValue];
    AssertEq(revpos, 2);
}

- (void) test16_Restart {
    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    // Pusher:
    CBLReplication* pusher = [db createPushReplication: remoteDbURL];
    pusher.continuous = YES;
    [pusher start];
    [pusher restart];

    // Wait to get a notification when the replication is idle:
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    while (pusher.status != kCBLReplicationIdle && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]])
            break;
    }

    // Make sure the replication is now idle:
    AssertEq(pusher.status, kCBLReplicationIdle);

    // Stop the replicator now:
    [pusher stop];
    timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    while (pusher.status != kCBLReplicationStopped && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]])
            break;
    }

    // Make sure the replication is stopped:
    AssertEq(pusher.status, kCBLReplicationStopped);

    // Puller:
    CBLReplication* puller = [db createPullReplication: remoteDbURL];
    puller.continuous = YES;
    [puller start];
    [puller restart];

    // Wait to get a notification when the replication is idle:
    timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    while (puller.status != kCBLReplicationIdle && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]])
            break;
    }

    // Make sure the replication is now idle:
    AssertEq(puller.status, kCBLReplicationIdle);

    // Stop the replicator now:
    [puller stop];
    timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    while (puller.status != kCBLReplicationStopped && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]])
            break;
    }

    // Make sure the replication is stopped:
    AssertEq(puller.status, kCBLReplicationStopped);
}

- (void)test17_RemovedRevision {
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    // Create a new document with grant = true:
    CBLDocument* doc = [db documentWithID: @"doc1"];
    CBLUnsavedRevision* unsaved = [doc newRevision];
    unsaved.userProperties = @{@"_removed": @(YES)};

    NSError* error;
    CBLSavedRevision* rev = [unsaved save: &error];
    Assert(rev != nil, @"Cannot save a new revision: %@", error);

    // Create a push replicator and push _removed revision
    CBLReplication* pusher = [db createPushReplication: remoteDbURL];
    [pusher start];

    // Check pending status:
    Assert([pusher isDocumentPending: doc]);

    [self expectationForNotification: kCBLReplicationChangeNotification
                              object: pusher
                             handler: ^BOOL(NSNotification *notification) {
                                 return pusher.status == kCBLReplicationStopped;
                             }];
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    AssertNil(pusher.lastError);
    AssertEq(pusher.completedChangesCount, 0u);
    AssertEq(pusher.changesCount, 0u);
    Assert(![pusher isDocumentPending: doc]);
}


- (void)test18_PendingDocumentIDs {
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    // Push replication:
    CBLReplication* repl = [db createPushReplication: remoteDbURL];
    Assert(repl.pendingDocumentIDs != nil);
    AssertEq(repl.pendingDocumentIDs.count, 0u);

    [db inTransaction: ^BOOL{
        for (int i = 1; i <= 10; i++) {
            @autoreleasepool {
                CBLDocument* doc = db[ $sprintf(@"doc-%d", i) ];
                NSError* error;
                [doc putProperties: @{@"index": @(i), @"bar": $false} error: &error];
                AssertNil(error);
            }
        }
        return YES;
    }];

    AssertEq(repl.pendingDocumentIDs.count, 10u);
    Assert([repl isDocumentPending: [db documentWithID: @"doc-1"]]);

    [repl start];
    AssertEq(repl.pendingDocumentIDs.count, 10u);
    Assert([repl isDocumentPending: [db documentWithID: @"doc-1"]]);

    [self runReplication: repl expectedChangesCount: 10u];
    Assert(repl.pendingDocumentIDs != nil);
    AssertEq(repl.pendingDocumentIDs.count, 0u);
    Assert(![repl isDocumentPending: [db documentWithID: @"doc-1"]]);

    // Add another set of documents:
    [db inTransaction: ^BOOL{
        for (int i = 11; i <= 20; i++) {
            @autoreleasepool {
                CBLDocument* doc = db[ $sprintf(@"doc-%d", i) ];
                NSError* error;
                [doc putProperties: @{@"index": @(i), @"bar": $false} error: &error];
                AssertNil(error);
            }
        }
        return YES;
    }];

    // Make sure newly-added documents are considered pending: (#1132)
    Assert([repl isDocumentPending: [db documentWithID: @"doc-11"]]);
    AssertEq(repl.pendingDocumentIDs.count, 10u);

    // Create a new replicator:
    repl = [db createPushReplication: remoteDbURL];

    AssertEq(repl.pendingDocumentIDs.count, 10u);
    Assert([repl isDocumentPending: [db documentWithID: @"doc-11"]]);
    Assert(![repl isDocumentPending: [db documentWithID: @"doc-1"]]);

    [repl start];
    AssertEq(repl.pendingDocumentIDs.count, 10u);
    Assert([repl isDocumentPending: [db documentWithID: @"doc-11"]]);
    Assert(![repl isDocumentPending: [db documentWithID: @"doc-1"]]);

    // Pull replication:
    repl = [db createPullReplication: remoteDbURL];
    Assert(repl.pendingDocumentIDs == nil);

    // Start and recheck:
    [repl start];
    Assert(repl.pendingDocumentIDs == nil);

    [self runReplication: repl expectedChangesCount: 0u];
    Assert(repl.pendingDocumentIDs == nil);
}


// Issue #1274: Just-pulled docs shouldn't be treated as pending by the pusher
- (void)test18_PendingDocumentIDs_OnFirstPull {
    NSURL* remoteDbURL = [self remoteTestDBURL: @"public"];
    if (!remoteDbURL)
        return;

    // Push replication:
    CBLReplication* push = [db createPushReplication: remoteDbURL];
    push.continuous = YES;
    [push start];

    // Run a one-shot pull:
    CBLReplication* pull = [db createPullReplication: remoteDbURL];
    [self runReplication: pull expectedChangesCount: 2];

    // Give the push CBLReplication a chance to receive the progress notification,
    // so it learns the current checkpoint
    [NSRunLoop.currentRunLoop runMode: NSDefaultRunLoopMode
                           beforeDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
    AssertEq(push.lastSequencePushed, 2);
    AssertEqual(push.pendingDocumentIDs, [NSSet new]);
}


- (void) test_19_Auth_Failure {
    _timeout = 2.0; // Failure should be immediate, with no retries
    NSURL* remoteDbURL = [self remoteTestDBURL: @"cbl_auth_test"];
    if (!remoteDbURL)
        return;

    CBLReplication* repl = [db createPullReplication: remoteDbURL];
    repl.authenticator = [CBLAuthenticator basicAuthenticatorWithName: @"wrong"
                                                             password: @"wrong"];
    [self runReplication: repl expectedChangesCount: 0];
    NSError* error = repl.lastError;
    AssertEqual(error.domain, CBLHTTPErrorDomain);
    AssertEq(error.code, 401);
    NSDictionary* challenge = error.userInfo[@"AuthChallenge"];
    AssertEqual(challenge[@"Scheme"], @"Basic");
    AssertEqual(challenge[@"realm"], @"Couchbase Sync Gateway");

    repl.authenticator = [CBLAuthenticator OAuth1AuthenticatorWithConsumerKey: @"wrong"
                                                               consumerSecret: @"wrong"
                                                                        token: @"wrong"
                                                                  tokenSecret: @"wrong"
                                                              signatureMethod: @"PLAINTEXT"];
    [self runReplication: repl expectedChangesCount: 0];
    AssertEqual(repl.lastError.domain, CBLHTTPErrorDomain);
    AssertEq(repl.lastError.code, 401);
}


#pragma mark - LAZY ATTACHMENTS:


- (CBLReplication*) pullFromAttachTest {
    NSURL* pullURL = [self remoteTestDBURL: kAttachTestDBName];
    if (!pullURL)
        return nil;

    CBLReplication* repl = [db createPullReplication: pullURL];
    repl.downloadsAttachments = NO;
    [self allowWarningsIn: ^{
        // This triggers a warning in CBLSyncConnection because the attach-test db is actually
        // missing an attachment body. It's not a CBL error.
        [self runReplication: repl expectedChangesCount: 0];
    }];
    AssertNil(repl.lastError);
    return repl.lastError ? nil : repl;
}

- (XCTestExpectation*) expectationForProgress: (NSProgress*)progress
                                      logging: (BOOL)logging
{
    XCKeyValueObservingExpectationHandler handler = ^BOOL(id observedObject, NSDictionary *change) {
        NSProgress* p = observedObject;
        if (logging) {
            Log(@"progress = %@", p);
            Log(@"    desc = %@ / %@",
                p.localizedDescription, p.localizedAdditionalDescription);
        }
        NSError* error = p.userInfo[kCBLProgressErrorKey];
        return p.completedUnitCount == p.totalUnitCount || error != nil;
    };
    return [self keyValueObservingExpectationForObject: progress
                                               keyPath: @"fractionCompleted"
                                               handler: handler];
}

- (void) test20_LazyPullAttachments {
    CBLReplication* repl = [self pullFromAttachTest];
    if (!repl)
        return;
    Log(@"Verifying attachment...");
    CBLDocument* doc = db[@"oneBigAttachment"];
    CBLAttachment* att = [doc.currentRevision attachmentNamed: @"IMG_0450.MOV"];
    Assert(att);
    AssertEq(att.length, 34120085ul);
    Assert(!att.contentAvailable);
    AssertNil(att.content);
    AssertNil(att.contentURL);
    AssertNil(att.openContentStream);

    CBLAttachmentDownloaderFakeTransientFailures = YES;

    Log(@"Downloading attachment...");

    // Request it twice to make sure simultaneous requests work:
    NSProgress* progress1 = [repl downloadAttachment: att];
    NSProgress* progress2 = [repl downloadAttachment: att];
    [self expectationForProgress: progress1 logging: YES];
    [self expectationForProgress: progress2 logging: YES];
    [self waitForExpectationsWithTimeout: _timeout handler: nil];
    AssertNil(progress1.userInfo[kCBLProgressErrorKey]);
    AssertNil(progress2.userInfo[kCBLProgressErrorKey]);

    Assert(att.contentAvailable);
    AssertEq(att.content.length, att.length);
    Assert(att.contentURL != nil);
    NSInputStream* stream = att.openContentStream;
    Assert(stream != nil);
    [stream close];

    Log(@"Purging attachment...");
    Assert([att purge]);
    Assert(!att.contentAvailable);
    AssertNil(att.content);
    AssertNil(att.contentURL);
    AssertNil(att.openContentStream);

    CBLAttachmentDownloaderFakeTransientFailures = NO;
}


- (void) test21_LazyPullMissingAttachment {
    CBLReplication* repl = [self pullFromAttachTest];
    if (!repl)
        return;
    // This attachment has metadata, but the actual contents are missing in SG, which will cause
    // a 404 error when we try to download it
    CBLAttachment* att = [db[@"weirdmeta"].currentRevision attachmentNamed: @"first"];
    Assert(att);

    // Request it twice to make sure simultaneous requests work:
    Log(@"Downloading attachment...");
    NSProgress* progress1 = [repl downloadAttachment: att];
    NSProgress* progress2 = [repl downloadAttachment: att];

    [self keyValueObservingExpectationForObject: progress1.userInfo
                                        keyPath: kCBLProgressErrorKey
                                        handler: ^BOOL(id observedObject, NSDictionary *change) {
                                            Log(@"progress1.userInfo = %@", observedObject);
                                            return YES;
                                        }];
    [self keyValueObservingExpectationForObject: progress2.userInfo
                                        keyPath: kCBLProgressErrorKey
                                        handler: ^BOOL(id observedObject, NSDictionary *change) {
                                            Log(@"progress2.userInfo = %@", observedObject);
                                            return YES;
                                        }];
    [self waitForExpectationsWithTimeout: _timeout handler: nil];
    NSError* error1 = progress1.userInfo[kCBLProgressErrorKey];
    Assert([error1 my_hasDomain: CBLHTTPErrorDomain code: kCBLStatusNotFound]);
    NSError* error2 = progress2.userInfo[kCBLProgressErrorKey];
    Assert([error2 my_hasDomain: CBLHTTPErrorDomain code: kCBLStatusNotFound]);
}


- (void) test22_NonDownloadedAttachments {
    // First pull the read-only "attach_test" database:
    NSURL* pullURL = [self remoteTestDBURL: kAttachTestDBName];
    if (!pullURL)
        return;

    Log(@"Pulling from %@...", pullURL);
    CBLReplication* pull = [db createPullReplication: pullURL];
    pull.downloadsAttachments = NO; // Crucial: Skip attachments on pull!
    [self runReplication: pull expectedChangesCount: 0];
    AssertNil(pull.lastError);

    Log(@"Verifying documents...");
    CBLDocument* doc = db[@"oneBigAttachment"];
    CBLAttachment* att = [doc.currentRevision attachmentNamed: @"IMG_0450.MOV"];
    Assert(att);
    AssertEq(att.length, 34120085ul);
    AssertNil(att.content);

    doc = db[@"extrameta"];
    att = [doc.currentRevision attachmentNamed: @"extra.txt"];
    AssertNil(att.content);

    // Now push it to the scratch database:
    NSURL* pushURL = [self remoteTestDBURL: kScratchDBName];
    [self eraseRemoteDB: pushURL];
    Log(@"Pushing to %@...", pushURL);
    CBLReplication *push = [db createPushReplication: pushURL];
    [self runReplication: push expectedChangesCount: 0];
    AssertNil(push.lastError);

    // Download a missing attachment:
    NSProgress* progress = [pull downloadAttachment: att];
    [self expectationForProgress: progress logging: NO];
    [self waitForExpectationsWithTimeout: _timeout handler: nil];
    AssertNil(progress.userInfo[kCBLProgressErrorKey]);

    // Push again (without clearing scratch) -- will upload 'extrameta'
    [self runReplication: push expectedChangesCount: 1];
    AssertNil(push.lastError);
}


#pragma mark - MISC


- (NSDictionary*) generateSyncGatewayCookieForURL: (NSURL*)remoteURL {
    // Get SyncGatewaySession cookie:
    __block NSDictionary* cookie;
    NSURLComponents* comp = [NSURLComponents componentsWithURL: remoteURL
                                       resolvingAgainstBaseURL: YES];
    comp.port = @(comp.port.intValue + 1); // admin port
    comp.path = [comp.path stringByAppendingPathComponent: @"_session"];
    XCTestExpectation* complete = [self expectationWithDescription: @"didComplete"];
    CBLRemoteRequest *req =
        [[CBLRemoteJSONRequest alloc] initWithMethod: @"POST"
                                                 URL: comp.URL
                                                body: @{@"name": @"test", @"password": @"abc123"}
                                        onCompletion:^(id result, NSError *error) {
                                            AssertNil(error);
                                            cookie = result;
                                            [complete fulfill];
                                        }];
    req.debugAlwaysTrust = YES;
    CBLRemoteSession* session = [[CBLRemoteSession alloc] initWithDelegate: nil];
    [session startRequest: req];
    [self waitForExpectationsWithTimeout: 2.0 handler: nil];
    return cookie;
}

- (void) runReplicationWithSyncGatewayCookie: (NSDictionary*)cookie URL: (NSURL*)remoteURL {
    // Create a continuous pull replicator and set SyncGatewaySession cookie:
    CBLReplication* repl = [db createPullReplication: remoteURL];
    repl.continuous = YES;
    [repl setCookieNamed: cookie[@"cookie_name"]
               withValue: cookie[@"session_id"]
                    path: remoteURL.path
          expirationDate: [CBLJSON dateWithJSONObject: cookie[@"expires"]]
                  secure: NO];
    [self runReplication: repl expectedChangesCount: 0u];
    AssertNil(repl.lastError);
    
    // Stop the pull replicator:
    [self keyValueObservingExpectationForObject: repl
                                        keyPath: @"status" expectedValue: @(kCBLReplicationStopped)];
    [repl stop];
    [self waitForExpectationsWithTimeout: 2.0 handler: nil];
}


- (void) test22a_SyncGatewayPersistentCookie {
    NSURL* remoteURL = [self remoteTestDBURL: @"cbl_auth_test"];
    if (!remoteURL)
        return;
    NSDictionary* cookie = [self generateSyncGatewayCookieForURL: remoteURL];
    [self runReplicationWithSyncGatewayCookie: cookie URL: remoteURL];
}


- (void) test22b_SyncGatewaySessionCookie {
    NSURL* remoteURL = [self remoteTestDBURL: @"cbl_auth_test"];
    if (!remoteURL)
        return;
    NSMutableDictionary* cookie = [[self generateSyncGatewayCookieForURL: remoteURL] mutableCopy];
    [cookie removeObjectForKey: @"expires"];    // Makes it a session (non-persistent) cookie
    [self runReplicationWithSyncGatewayCookie: cookie URL: remoteURL];
}


- (void) test_23_StoppedWhenCloseDatabase {
    NSURL* remoteDbURL = [self remoteTestDBURL: kPushThenPullDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];
    
    NSError* error;
    
    // Run push and pull replication:
    CBLReplication* push = [db createPushReplication: remoteDbURL];
    push.continuous = YES;
    [self runReplication: push expectedChangesCount: 0u];
    
    CBLReplication* pull = [db createPushReplication: remoteDbURL];
    pull.continuous = YES;
    [self runReplication: pull expectedChangesCount: 0u];
    
    [self keyValueObservingExpectationForObject: push keyPath: @"status" expectedValue: @(kCBLReplicationStopped)];
    [self keyValueObservingExpectationForObject: pull keyPath: @"status" expectedValue: @(kCBLReplicationStopped)];
    
    Assert([db close: &error], @"Error when closing the database: %@", error);
    
    [self waitForExpectationsWithTimeout: 2.0 handler: nil];
    AssertEq(db.allReplications.count, 0u);
}


// Test the "purgePushed" and "allNew" push options:
- (void) test24_PushAndPurge {
    static const int nDocuments = 100;
    RequireTestCase(Push);
    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    // Do this twice so we also test the case where the docs _do_ already exist on the server.
    for (int pass = 1; pass <= 2; ++pass) {
        Log(@"Pass #%d: Creating %d documents...", pass, nDocuments);
        [db inTransaction:^BOOL{
            for (int i = 1; i <= nDocuments; i++) {
                @autoreleasepool {
                    CBLDocument* doc = db[ $sprintf(@"doc-%d", i) ];
                    NSError* error;
                    [doc putProperties: @{@"index": @(i), @"bar": $false} error: &error];
                    AssertNil(error);
                }
            }
            return YES;
        }];


        CBLReplication* repl = [db createPushReplication: remoteDbURL];
        repl.customProperties = @{@"purgePushed": @YES, @"allNew": @YES};
        [repl start];

        [self runReplication: repl expectedChangesCount: nDocuments];
        AssertNil(repl.lastError);

        // Did the docs get purged?
        AssertEq(db.documentCount, 0ull);
    }
}


// Creates a doc with a very deep revision history and pushes the entire history to the server.
// Then pulls it into another database.
- (void) test25_DeepRevTree {
    static const unsigned kNumRevisions = 2000;

    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];
    CBLReplication* push = [db createPushReplication: remoteDbURL];

    CBLDocument* doc = db[@"deep"];

    __block unsigned numRevisions;
    for (numRevisions = 0; numRevisions < kNumRevisions;) {
        @autoreleasepool {
            [db inTransaction: ^BOOL {
                // Have to push the doc periodically, to make sure the server gets the whole
                // history, since CBL will only remember the latest 20 revisions.
                unsigned batchSize = MIN((unsigned)db.maxRevTreeDepth-1, kNumRevisions - numRevisions);
                Log(@"Adding revisions %u -- %u ...", numRevisions+1, numRevisions+batchSize);
                for (unsigned i = 0; i < batchSize; ++i) {
                    Assert([doc update: ^BOOL(CBLUnsavedRevision *rev) {
                        rev[@"counter"] = @(++numRevisions);
                        return YES;
                    } error: NULL]);
                }
                return YES;
            }];
            Log(@"Pushing ...");
            [self runReplication: push expectedChangesCount: 1];
        }
    }

    Log(@"\n\n$$$$$$$$$$ PULLING TO DB2 $$$$$$$$$$");

    // Now create a second database and pull the remote db into it:
    CBLDatabase* db2 = [dbmgr createEmptyDatabaseNamed: @"prepopdb" error: NULL];
    Assert(db2);
    //[CBLManager enableLogging: @"DatabaseVerbose"];
    CBLReplication* pull = [db2 createPullReplication: remoteDbURL];
    [self runReplication: pull expectedChangesCount: 1];

    CBLDocument* doc2 = db2[@"deep"];
    AssertEq([doc2 getRevisionHistory: NULL].count, db2.maxRevTreeDepth);
    AssertEq([doc2 getConflictingRevisions: NULL].count, 1u);

    Log(@"\n\n$$$$$$$$$$ PUSHING 1 DOC FROM DB $$$$$$$$$$");

    // Now add a revision to the doc, push, and pull into db2:
    Assert([doc update: ^BOOL(CBLUnsavedRevision *rev) {
        rev[@"counter"] = @(++numRevisions);
        return YES;
    } error: NULL]);
    [self runReplication: push expectedChangesCount: 1];

    Log(@"\n\n$$$$$$$$$$ PULLING 1 DOC INTO DB2 $$$$$$$$$$");

    [self runReplication: pull expectedChangesCount: 1];
    AssertEq([doc2 getRevisionHistory: NULL].count, db2.maxRevTreeDepth);
    AssertEq([doc2 getConflictingRevisions: NULL].count, 1u);
}


// Test for pulling new revisions of lots of existing documents. (See #1276) 
- (void) test26_PullLotsOfUpdates {
    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];
    CBLReplication* push = [db createPushReplication: remoteDbURL];

    // Create 500 docs & push to remote db:
    for (int i = 0; i < 500; ++i)
        [self createDocumentWithProperties: @{@"_id": $sprintf(@"doc-%03d", i), @"n": @(i)}];
    [self runReplication: push expectedChangesCount: 500];

    // Pull to db2:
    CBLDatabase* db2 = [dbmgr createEmptyDatabaseNamed: @"prepopdb" error: NULL];
    Assert(db2);
    CBLReplication* pull = [db2 createPullReplication: remoteDbURL];
    [self runReplication: pull expectedChangesCount: 500];

    // Update 1/3 of the docs:
    for (int i = 0; i < 500; ++i) {
        if (i % 3 == 0) {
            CBLDocument* doc = db[$sprintf(@"doc-%03d", i)];
            CBLSavedRevision* rev = [doc update: ^BOOL(CBLUnsavedRevision *rev) {
                rev[@"updated"] = @YES;
                return YES;
            } error: NULL];
            Assert(rev);
        }
    }
    [self runReplication: push expectedChangesCount: 167];

    // Pull to db2 and verify:
    [self runReplication: pull expectedChangesCount: 167];
    for (int i = 0; i < 500; ++i) {
        CBLDocument* doc = db2[$sprintf(@"doc-%03d", i)];
        AssertEqual(doc[@"n"], @(i));
        AssertEqual(doc[@"updated"], (i%3 ? nil : @YES));
    }
}


#pragma mark - OPENID CONNECT:


- (void) test26_OpenIDConnectAuth {
    NSURL* remoteDbURL = [self remoteNonSSLTestDBURL: @"openid_db"];
    if (!remoteDbURL || !self.isSQLiteDB) return;

    NSError* error;
    Assert([CBLOpenIDConnectAuthorizer forgetIDTokensForServer: remoteDbURL error: &error]);

    id<CBLAuthenticator> auth = [CBLAuthenticator OpenIDConnectAuthenticator:
                                    ^(NSURL* login, NSURL* authBase, CBLOIDCLoginContinuation cont)
    {
        [self assertValidOIDCLogin: login authBase: authBase forRemoteDB: remoteDbURL];
        // Fake a form submission to the OIDC test provider, to get an auth URL redirect:
        NSURL* authURL = [self loginToOIDCTestProvider: remoteDbURL];
        Log(@"**** Callback handing control back to authenticator...");
        cont(authURL, nil);
    }];

    NSError* authError = [self pullWithOIDCAuth: auth expectingUsername: @"pupshaw"];
    AssertNil(authError);

    // Now try again; this should use the ID token from the keychain and/or a session cookie:
    Log(@"**** Second replication...");
    __block BOOL callbackInvoked = NO;
    auth = [CBLAuthenticator OpenIDConnectAuthenticator:
            ^(NSURL* login, NSURL* authBase, CBLOIDCLoginContinuation cont)
    {
        [self assertValidOIDCLogin: login authBase: authBase forRemoteDB: remoteDbURL];
        Assert(!callbackInvoked);
        callbackInvoked = YES;
        cont(nil, nil); // cancel
    }];
    authError = [self pullWithOIDCAuth: auth expectingUsername: @"pupshaw"];
    AssertNil(authError);
    Assert(!callbackInvoked);
}


- (void) test27_OpenIDConnectAuth_ExpiredIDToken {
    NSURL* remoteDbURL = [self remoteNonSSLTestDBURL: @"openid_db"];
    if (!remoteDbURL || !self.isSQLiteDB) return;

    NSError* error;
    Assert([CBLOpenIDConnectAuthorizer forgetIDTokensForServer: remoteDbURL error: &error]);

    __block BOOL callbackInvoked = NO;
    id<CBLAuthenticator> auth = [CBLAuthenticator OpenIDConnectAuthenticator:
                                    ^(NSURL* login, NSURL* authBase, CBLOIDCLoginContinuation cont)
    {
        [self assertValidOIDCLogin: login authBase: authBase forRemoteDB: remoteDbURL];
        Assert(!callbackInvoked);
        callbackInvoked = YES;
        cont(nil, nil); // cancel
    }];

    // Set bogus ID and refresh tokens, so first the session check will fail, then the attempt
    // to refresh the ID token will fail. Finally the callback above will be called.
    ((CBLOpenIDConnectAuthorizer*)auth).IDToken = @"BOGUS_ID";
    ((CBLOpenIDConnectAuthorizer*)auth).refreshToken = @"BOGUS_REFRESH";

    NSError* authError = [self pullWithOIDCAuth: auth expectingUsername: nil];
    Assert(callbackInvoked);
    Assert([authError my_hasDomain: NSURLErrorDomain
                              code: NSURLErrorUserCancelledAuthentication]);
}


// Use the CBLRestLogin class to log in with OIDC without using a replication
- (void) test28_OIDCLoginWithoutReplicator {
    NSURL* remoteDbURL = [self remoteNonSSLTestDBURL: @"openid_db"];
    if (!remoteDbURL || !self.isSQLiteDB)
        return;

    Assert([CBLOpenIDConnectAuthorizer forgetIDTokensForServer: remoteDbURL error: NULL]);

    // Log in 3 times. First will require a UI, which we fake. After that, it should be able to use
    // the refresh token instead.
    for (int pass = 1; pass <= 3; pass++) {
        Log(@"***** Login #%d *****", pass);
        id<CBLAuthenticator> auth = [CBLAuthenticator OpenIDConnectAuthenticator:
                                        ^(NSURL* login, NSURL* authBase, CBLOIDCLoginContinuation cont)
        {
            if (pass == 1) {
                [self assertValidOIDCLogin: login authBase: authBase forRemoteDB: remoteDbURL];
                // Fake a form submission to the OIDC test provider, to get an auth URL redirect:
                NSURL* authURL = [self loginToOIDCTestProvider: remoteDbURL];
                Log(@"**** Callback handing control back to authenticator...");
                cont(authURL, nil);
            } else {
                Assert(NO, @"Login UI should not be required after 1st login");
                cont(nil, [NSError errorWithDomain: @"test" code: 666 userInfo: nil]);
            }
        }];

        __block bool loginDone = false;
        __block NSError* error = nil;
        CBLRemoteLogin* login = [[CBLRemoteLogin alloc] initWithURL: remoteDbURL
                                                          localUUID: db.publicUUID
                                                         authorizer: (id<CBLAuthorizer>)auth
                                                       continuation: ^(NSError* e)
        {
            error = e;
            loginDone = true;
        }];
        [login start];
        [self wait: 5.0 for: ^BOOL { return loginDone; }];
        login = nil;
        AssertNil(error);
    }
}


- (void) test29_OpenIDConnect_PusherBecomesIdle {
    // https://github.com/couchbase/couchbase-lite-ios/issues/1392
    NSURL* remoteDbURL = [self remoteNonSSLTestDBURL: @"openid_db"];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    NSError* error;
    Assert([CBLOpenIDConnectAuthorizer forgetIDTokensForServer: remoteDbURL error: &error]);

    __block BOOL callbackInvoked = NO;
    id<CBLAuthenticator> auth = [CBLAuthenticator OpenIDConnectAuthenticator:
                                 ^(NSURL* login, NSURL* authBase, CBLOIDCLoginContinuation cont)
                                 {
                                     [self assertValidOIDCLogin: login authBase: authBase forRemoteDB: remoteDbURL];
                                     // Fake a form submission to the OIDC test provider, to get an auth URL redirect:
                                     NSURL* authURL = [self loginToOIDCTestProvider: remoteDbURL];
                                     callbackInvoked = YES;
                                     cont(authURL, nil);
                                 }];

    CBLReplication* push = [db createPushReplication: remoteDbURL];
    push.authenticator = auth;
    push.continuous = YES;
    [self runReplication: push expectedChangesCount: 0];
    
    Assert(push.status == kCBLReplicationIdle);
    Assert(callbackInvoked);
}


- (NSError*) pullWithOIDCAuth: (id<CBLAuthenticator>)auth
            expectingUsername: (NSString*)username
{
    NSURL* remoteDbURL = [self remoteNonSSLTestDBURL: @"openid_db"];
    if (!remoteDbURL)
        return nil;
    CBLReplication* repl = [db createPullReplication: remoteDbURL];
    repl.authenticator = auth;
    [self runReplication: repl expectedChangesCount: 0];
    if (username && !repl.lastError) {
        // SG namespaces the username by prefixing it with the hash of
        // the identity provider's registered name (given in the SG config file.)
        Assert([repl.username hasSuffix: username]);
    }
    return repl.lastError;
}


- (void) assertValidOIDCLogin: (NSURL*)login
                     authBase: (NSURL*)authBase
                  forRemoteDB: (NSURL*)remoteDbURL
{
    Log(@"*** Login callback invoked with login URL: <%@>, authBase: <%@>", login, authBase);
    Assert(login);
    AssertEqual(login.host, remoteDbURL.host);
    AssertEqual(login.port, remoteDbURL.port);
    AssertEqual(login.path, [remoteDbURL.path stringByAppendingPathComponent: @"_oidc_testing/authorize"]);
    Assert(authBase);
    AssertEqual(authBase.host, remoteDbURL.host);
    AssertEqual(authBase.port, remoteDbURL.port);
    AssertEqual(authBase.path, [remoteDbURL.path stringByAppendingPathComponent: @"_oidc_callback"]);
}


- (NSURL*) loginToOIDCTestProvider: (NSURL*)remoteDbURL {
    // Fake a form submission to the OIDC test provider, to get an auth URL redirect:
    NSURL* formURL = [NSURL URLWithString: [remoteDbURL.absoluteString stringByAppendingString: @"/_oidc_testing/authenticate?client_id=CLIENTID&redirect_uri=http%3A%2F%2F127.0.0.1%3A4984%2Fopenid_db%2F_oidc_callback&response_type=code&scope=openid+email&state="]];
    NSData *formData = [@"username=pupshaw&authenticated=true" dataUsingEncoding: NSUTF8StringEncoding];
    CBLRemoteRequest* rq = [[CBLRemoteRequest alloc] initWithMethod: @"POST" URL: formURL body: formData onCompletion: nil];
    [rq dontRedirect];
    [self sendRemoteRequest: rq];
    AssertEq(rq.statusCode, 302);
    NSString* authURLStr = rq.responseHeaders[@"Location"];
    Log(@"Redirected to: %@", authURLStr);
    Assert(authURLStr);
    NSURL* authURL = [NSURL URLWithString: authURLStr];
    Assert(authURL);
    return authURL;
}


@end
