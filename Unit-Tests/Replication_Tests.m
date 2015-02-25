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


// This db will get deleted and overwritten during every test.
#define kPushThenPullDBName @"cbl_replicator_pushpull"
#define kNDocuments 1000
#define kAttSize 1*1024
// This one too.
#define kEncodedDBName @"cbl_replicator_encoding"
// This one's never actually read or written to.
#define kCookieTestDBName @"cbl_replicator_cookies"


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
                  secure: cookie1.secure];

    [repl setCookieNamed: cookie2.name
               withValue: cookie2.value
                    path: cookie2.path
          expirationDate: cookie2.expiresDate
                  secure: cookie2.secure];

    [repl setCookieNamed: cookie3.name
               withValue: cookie3.value
                    path: cookie3.path
          expirationDate: cookie3.expiresDate
                  secure: cookie3.secure];

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

@end
