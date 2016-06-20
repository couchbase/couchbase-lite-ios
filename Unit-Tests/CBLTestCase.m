//
//  CBLTestCase.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/19/14.
//
//

#import "CBLTestCase.h"
#import "CBLDatabase+Internal.h"
#import "CBLManager+Internal.h"
#import "MYURLUtils.h"
#import "CBLRemoteRequest.h"
#import "CBLRemoteSession.h"
#import "CBL_BlobStore+Internal.h"
#import "CBLSymmetricKey.h"
#import "CBLKVOProxy.h"


// The default remote server URL used by RemoteTestDBURL().
#define kDefaultRemoteTestServer @"http://127.0.0.1:4984/"
#define kDefaultRemoteSSLTestServer @"https://localhost:4994/"


extern NSString* WhyUnequalObjects(id a, id b); // from Test.m
extern int c4_getObjectCount(void);             // from c4Base.h (CBForest)


@interface CBLManager (Secret)
+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name;
- (CBLDatabase*) createEmptyDatabaseNamed: (NSString*)name error: (NSError**)outError;
- (void) _forgetDatabase: (CBLDatabase*)db;
@end


@implementation CBLTestCase


- (void)setUp {
    [super setUp];
    [CBLManager setWarningsRaiseExceptions: YES];
}

- (void) tearDown {
    [CBLManager setWarningsRaiseExceptions: NO];
    [super tearDown];
}


- (NSString*) pathToTestFile: (NSString*)name {
    // The iOS and Mac test apps have the TestData folder copied into their Resources dir.
    NSString* path =  [[NSBundle bundleForClass: [self class]] pathForResource: name.stringByDeletingPathExtension
                                                      ofType: name.pathExtension
                                                 inDirectory: @"TestData"];
    Assert(path, @"Can't find test file \"%@\"", name);
    return path;
}

- (NSData*) contentsOfTestFile: (NSString*)name {
    NSError* error;
    NSData* data = [NSData dataWithContentsOfFile: [self pathToTestFile: name] options:0 error: &error];
    Assert(data, @"Couldn't read test file '%@': %@", name, error.my_compactDescription);
    return data;
}

- (void) _assertEqualish: (id)a to: (id)b {
    NSString* why = WhyUnequalObjects(a, b);
    Assert(why==nil, @"Objects not equal-ish:\n%@", why);
}

- (void) allowWarningsIn: (void (^)())block {
    [CBLManager setWarningsRaiseExceptions: NO];
    block();
    [CBLManager setWarningsRaiseExceptions: YES];
}


- (NSInteger) iOSVersion {
#if TARGET_OS_IPHONE
    if (![NSProcessInfo instancesRespondToSelector: @selector(operatingSystemVersion)])
        return 7; // -operatingSystemVersion was added in iOS 8
    return [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
#else
    return 0;
#endif
}

- (NSInteger) macOSVersion {
#if TARGET_OS_IPHONE
    return 0;
#else
    if (![NSProcessInfo instancesRespondToSelector: @selector(operatingSystemVersion)])
        return 9; // -operatingSystemVersion was added in OS X 10.10
    return [NSProcessInfo processInfo].operatingSystemVersion.minorVersion;
#endif
}


#if 1
// NOTE: This is a workaround for XCTest's implementation of this method not being thread-safe.
// We can take it out when our test bot is upgraded to Xcode 7 (beta 5 or later).
- (XCTestExpectation *)keyValueObservingExpectationForObject:(id)objectToObserve
                                                     keyPath:(NSString *)keyPath
                                               expectedValue:(nullable id)expectedValue
{
    CBLKVOProxy* proxy = [[CBLKVOProxy alloc] initWithObject: objectToObserve
                                                     keyPath: keyPath];
    return [super keyValueObservingExpectationForObject: proxy
                                                keyPath: keyPath
                                          expectedValue: expectedValue];
}

- (XCTestExpectation *)keyValueObservingExpectationForObject:(id)objectToObserve
                                                     keyPath:(NSString *)keyPath
                                                     handler:(nullable XCKeyValueObservingExpectationHandler)handler
{
    XCKeyValueObservingExpectationHandler wrappedHandler = ^BOOL(id o, NSDictionary* c) {
        return handler(objectToObserve, c);
    };
    CBLKVOProxy* proxy = [[CBLKVOProxy alloc] initWithObject: objectToObserve
                                                     keyPath: keyPath];
    return [super keyValueObservingExpectationForObject: proxy
                                                keyPath: keyPath
                                                handler: wrappedHandler];

}
#endif


- (BOOL) wait: (NSTimeInterval)timeout for: (BOOL(^)())block {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime lastTime = startTime;
    BOOL done = NO;
    do {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]])
            break;
        // Replication runs on a background thread, so the main runloop should not be blocked.
        // Make sure it's spinning in a timely manner:
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now-lastTime > 0.25)
            Warn(@"Main runloop was blocked for %g sec", now-lastTime);
        lastTime = now;
        if (now-startTime > timeout)
            break;
        done = block();
    } while (!done);
    return done;
}


@end


@implementation CBLTestCaseWithDB
{
    BOOL _useForestDB;
    int _cbForestObjectCount;
}

@synthesize db=db;


- (void)invokeTest {
    // Run each test method twice, once with SQLite storage and once with ForestDB.
    _useForestDB = NO;
    [super invokeTest];
    _useForestDB = YES;
    [super invokeTest];
}


- (void)setUp {
    [super setUp];

    _cbForestObjectCount = c4_getObjectCount();

    dbmgr = [CBLManager createEmptyAtTemporaryPath: @"CBL_iOS_Unit_Tests"];
    dbmgr.storageType = _useForestDB ? kCBLForestDBStorage : kCBLSQLiteStorage;
    Assert(dbmgr);
    Log(@"---- Using %@ ----", dbmgr.storageType);
    NSError* error;
    db = [dbmgr createEmptyDatabaseNamed: @"db" error: &error];
    Assert(db, @"Couldn't create db: %@", error.my_compactDescription);

    AssertEq(db.lastSequenceNumber, 0); // Ensure db was deleted properly by the previous test
}

- (void)tearDown {
    NSError* error;
    Assert(!db || [db deleteDatabase: &error], @"Couldn't close db: %@", error.my_compactDescription);
    [dbmgr close];

    if (_useForestDB) {
        // Some tests create CBForest objects on a background thread, which may take a moment to
        // be cleaned up, so wait a few seconds for the object count to go back to normal:
        int tries = 20;
        while (c4_getObjectCount() > _cbForestObjectCount && --tries > 0) {
            Log(@"(Waiting for CBForest objects to be freed)");
            usleep(100*1000);
        }
        AssertEq(c4_getObjectCount() - _cbForestObjectCount, 0);    // Check for CBForest leaks
    }

    [super tearDown];
}

- (void) reopenTestDB {
    Log(@"---- closing db ----");
    Assert(db != nil);
    NSString* dbName = db.name;
    NSError* error;
    Assert([db close: &error], @"Couldn't close db: %@", error.my_compactDescription);
    db = nil;

    Log(@"---- reopening db ----");
    CBLDatabase* db2 = [dbmgr databaseNamed: dbName error: &error];
    Assert(db2, @"Couldn't reopen db: %@", error.my_compactDescription);
    Assert(db2 != db, @"-reopenTestDB couldn't make a new instance");
    db = db2;
}


- (void) eraseTestDB {
    NSString* dbName = db.name;
    NSError* error;
    Assert([db deleteDatabase: &error], @"Couldn't delete test db: %@", error.my_compactDescription);
    db = [dbmgr createEmptyDatabaseNamed: dbName error: &error];
    Assert(db, @"Couldn't recreate test db: %@", error.my_compactDescription);
}


- (BOOL) encryptedAttachmentStore {
    return db.attachmentStore.encryptionKey != nil;
}

- (void) setEncryptedAttachmentStore: (BOOL)encrypted {
    if (encrypted != self.encryptedAttachmentStore) {
        CBLSymmetricKey* key = encrypted ? [[CBLSymmetricKey alloc] init] : nil;
        NSError* error;
        Assert([db.attachmentStore changeEncryptionKey: key error: &error],
               @"Failed to add/remove encryption: %@", error);
    }
}


- (BOOL) isSQLiteDB {
    return [NSStringFromClass(db.storage.class) isEqualToString: @"CBL_SQLiteStorage"];
}


- (CBLDocument*) createDocumentWithProperties: (NSDictionary*)properties {
    return [self createDocumentWithProperties: properties inDatabase: db];
}

- (CBLDocument*) createDocumentWithProperties: (NSDictionary*)properties
                                   inDatabase: (CBLDatabase*)indb
{
    CBLDocument* doc;
    NSDictionary* userProperties;
    if (properties[@"_id"]) {
        doc = [indb documentWithID: properties[@"_id"]];
        NSMutableDictionary* props = [properties mutableCopy];
        [props removeObjectForKey: @"_id"];
        userProperties = props;
    } else {
        doc = [indb createDocument];
        userProperties = properties;
    }
    Assert(doc != nil);
    AssertNil(doc.currentRevisionID);
    AssertNil(doc.currentRevision);
    Assert(doc.documentID, @"Document has no ID"); // 'untitled' docs are no longer untitled (8/10/12)

    NSError* error;
    Assert([doc putProperties: properties error: &error], @"Couldn't save: %@", error.my_compactDescription);  // save it!

    Assert(doc.documentID);
    Assert(doc.currentRevisionID);

    AssertEqual(doc.userProperties, userProperties);
    AssertEq(indb[doc.documentID], doc);
    //Log(@"Created %p = %@", doc, doc);
    return doc;
}


- (void) createDocuments: (unsigned)n {
    [db inTransaction:^BOOL{
        for (unsigned i=0; i<n; i++) {
            @autoreleasepool {
                NSDictionary* properties = @{@"testName": @"testDatabase", @"sequence": @(i)};
                [self createDocumentWithProperties: properties];
            }
        }
        return YES;
    }];
}


- (NSURL*) remoteTestDBURL: (NSString*)dbName {
    // If the OS has App Transport Security, we have to make all connections over SSL:
    // ...except that Mac OS unit tests don't appear to be restricted by ATS. And there is
    // a CFNetwork bug(?) triggered by using SSL (see #1170)
    if (self.iOSVersion >= 9 /*|| self.macOSVersion >= 11*/) {
        NSArray* serverCerts = [self remoteTestDBAnchorCerts];
        [CBLReplication setAnchorCerts: serverCerts onlyThese: NO];
        return [self remoteSSLTestDBURL: dbName];
    } else {
        return [self remoteNonSSLTestDBURL: dbName];
    }
}


- (NSURL*) remoteNonSSLTestDBURL: (NSString*)dbName {
    NSString* urlStr = [[NSProcessInfo processInfo] environment][@"CBL_TEST_SERVER"];
    if (!urlStr)
        urlStr = kDefaultRemoteTestServer;
    else if (urlStr.length == 0) {
        Assert(NO, @"Skipping test: no remote DB URL configured");
        return nil;
    }
    NSURL* server = [NSURL URLWithString: urlStr];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* username = [[NSProcessInfo processInfo] environment][@"CBL_TEST_USERNAME"];
        NSString* password = [[NSProcessInfo processInfo] environment][@"CBL_TEST_PASSWORD"];
        NSString* realm = [[NSProcessInfo processInfo] environment][@"CBL_TEST_REALM"];
        if (username) {
            Assert(password, @"Didn't setenv CBL_TEST_PASSWORD");
            Assert(realm, @"Didn't setenv CBL_TEST_REALM");
            AddTemporaryCredential(server, realm, username, password);
            Log(@"Registered credentials for %@ as %@  (realm %@)", urlStr, username, realm);
        }
    });

    return dbName ? [server URLByAppendingPathComponent: dbName] : server;
}


- (NSURL*) remoteSSLTestDBURL: (NSString*)dbName {
    NSString* urlStr = [[NSProcessInfo processInfo] environment][@"CBL_SSL_TEST_SERVER"];
    if (!urlStr)
        urlStr = kDefaultRemoteSSLTestServer;
    else if (urlStr.length == 0) {
        Assert(NO, @"Skipping test: no remote DB SSL URL configured");
        return nil;
    }
    NSURL* server = [NSURL URLWithString: urlStr];
    return dbName ? [server URLByAppendingPathComponent: dbName] : server;
}


- (double) remoteServerVersion {
    static double sVersion = -1.0;
    if (sVersion < 0) {
        NSURL* url = [self remoteTestDBURL: nil];
        NSDictionary* info = [self sendRemoteRequest: @"GET" toURL: url];
        sVersion = [[info[@"vendor"] objectForKey: @"version"] doubleValue];
        if (sVersion <= 0)
            Warn(@"Couldn't determine version of server at %@", url);
    }
    return sVersion;
}


- (id<CBLAuthorizer>) authorizer {
#if 1
    return nil;
#else
    NSURLCredential* cred = [NSURLCredential credentialWithUser: @"XXXX" password: @"XXXX"
                                                    persistence:NSURLCredentialPersistenceNone];
    return [[[CBLBasicAuthorizer alloc] initWithCredential: cred] autorelease];
#endif
}


- (NSArray*) remoteTestDBAnchorCerts {
    NSData* certData = [NSData dataWithContentsOfFile: [self pathToTestFile: @"SelfSigned.cer"]];
    Assert(certData, @"Couldn't load cert file");
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert, @"Couldn't parse cert");
    return @[CFBridgingRelease(cert)];
}


- (void) eraseRemoteDB: (NSURL*)dbURL {
    Log(@"Deleting %@", dbURL);
    // Post to /db/_flush is supported by Sync Gateway 1.1, but not by CouchDB
    NSURLComponents* comp = [NSURLComponents componentsWithURL: dbURL resolvingAgainstBaseURL: YES];
    comp.port = ([dbURL.scheme isEqualToString: @"http"]) ? @4985 : @4995;
    comp.path = [comp.path stringByAppendingPathComponent: @"_flush"];
    [self sendRemoteRequest: @"POST" toURL: comp.URL];
}


- (id) sendRemoteRequest: (NSString*)method toURL: (NSURL*)url {
    return [self sendRemoteRequest: [[CBLRemoteJSONRequest alloc] initWithMethod: method
                                                                             URL: url
                                                                            body: nil
                                                                    onCompletion: nil]];
}

- (id) sendRemoteRequest: (CBLRemoteRequest*)request {
    NSURLRequest* urlRequest = request.URLRequest;
    __block id result = nil;
    __block NSError* error = nil;
    XCTestExpectation* finished = [self expectationWithDescription: @"Sent request to server"];
    request.onCompletion = ^(id r, NSError *err) {
        result = r;
        error = err;
        [finished fulfill];
    };
    request.authorizer = self.authorizer;
    request.debugAlwaysTrust = YES;
    CBLRemoteSession* session = [[CBLRemoteSession alloc] initWithDelegate: nil];
    [session startRequest: request];

    [self waitForExpectationsWithTimeout: 10 handler: nil];
    Assert(error == nil, @"Unexpected error for %@ %@: %@", urlRequest.HTTPMethod, urlRequest.URL, error.my_compactDescription);
    return result;
}


void AddTemporaryCredential(NSURL* url, NSString* realm,
                            NSString* username, NSString* password)
{
    NSURLCredential* c = [NSURLCredential credentialWithUser: username password: password
                                                 persistence: NSURLCredentialPersistenceForSession];
    NSURLProtectionSpace* s = [url my_protectionSpaceWithRealm: realm
                                          authenticationMethod: NSURLAuthenticationMethodDefault];
    [[NSURLCredentialStorage sharedCredentialStorage] setCredential: c forProtectionSpace: s];
}


void RemoveTemporaryCredential(NSURL* url, NSString* realm,
                               NSString* username, NSString* password)
{
    NSURLCredential* c = [NSURLCredential credentialWithUser: username password: password
                                                 persistence: NSURLCredentialPersistenceForSession];
    NSURLProtectionSpace* s = [url my_protectionSpaceWithRealm: realm
                                          authenticationMethod: NSURLAuthenticationMethodDefault];
    [[NSURLCredentialStorage sharedCredentialStorage] removeCredential: c forProtectionSpace: s];
}


@end