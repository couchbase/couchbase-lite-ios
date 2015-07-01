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
#import "CBL_BlobStore.h"
#import "CBLSymmetricKey.h"


// The default remote server URL used by RemoteTestDBURL().
#define kDefaultRemoteTestServer @"http://127.0.0.1:4984/"
#define kDefaultRemoteSSLTestServer @"https://localhost:4994/"


extern NSString* WhyUnequalObjects(id a, id b); // from Test.m


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
    Assert(data, @"Couldn't read test file '%@': %@", name, error);
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


@end


@implementation CBLTestCaseWithDB
{
    BOOL _useForestDB;
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

    dbmgr = [CBLManager createEmptyAtTemporaryPath: @"CBL_iOS_Unit_Tests"];
    dbmgr.storageType = _useForestDB ? @"ForestDB" : @"SQLite";
    Assert(dbmgr);
    Log(@"---- Using %@ ----", dbmgr.storageType);
    NSError* error;
    db = [dbmgr createEmptyDatabaseNamed: @"db" error: &error];
    Assert(db, @"Couldn't create db: %@", error);

    AssertEq(db.lastSequenceNumber, 0); // Ensure db was deleted properly by the previous test
}

- (void)tearDown {
    NSError* error;
    Assert(!db || [db deleteDatabase: &error], @"Couldn't close db: %@", error);
    [dbmgr close];

    [super tearDown];
}

- (void) reopenTestDB {
    Log(@"---- closing db ----");
    Assert(db != nil);
    NSString* dbName = db.name;
    NSError* error;
    Assert([db close: &error], @"Couldn't close db: %@", error);
    db = nil;

    Log(@"---- reopening db ----");
    CBLDatabase* db2 = [dbmgr databaseNamed: dbName error: &error];
    Assert(db2, @"Couldn't reopen db: %@", error);
    Assert(db2 != db, @"-reopenTestDB couldn't make a new instance");
    db = db2;
}


- (void) eraseTestDB {
    NSString* dbName = db.name;
    NSError* error;
    Assert([db deleteDatabase: &error], @"Couldn't delete test db: %@", error);
    db = [dbmgr createEmptyDatabaseNamed: dbName error: &error];
    Assert(db, @"Couldn't recreate test db: %@", error);
}


- (BOOL) encryptedAttachmentStore {
    return db.attachmentStore.encryptionKey != nil;
}

- (void) setEncryptedAttachmentStore: (BOOL)encrypted {
    if (!encrypted)
        db.attachmentStore.encryptionKey = nil;
    else if (db.attachmentStore.encryptionKey == nil)
        db.attachmentStore.encryptionKey = [[CBLSymmetricKey alloc] init];
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
    Assert([doc putProperties: properties error: &error], @"Couldn't save: %@", error);  // save it!

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
    NSString* urlStr = [[NSProcessInfo processInfo] environment][@"CBL_TEST_SERVER"];
    if (!urlStr)
        urlStr = kDefaultRemoteTestServer;
    else if (urlStr.length == 0) {
        Assert(NO, @"Skipping test: no remote DB SSL URL configured");
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

    return [server URLByAppendingPathComponent: dbName];
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
    return [server URLByAppendingPathComponent: dbName];
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
    __block NSError* error = nil;
    __block BOOL finished = NO;
    
    // Post to /db/_flush is supported by Sync Gateway 1.1, but not by CouchDB
    NSURLComponents* comp = [NSURLComponents componentsWithURL: dbURL resolvingAgainstBaseURL: YES];
    comp.port = @4985;
    comp.path = [comp.path stringByAppendingPathComponent: @"_flush"];

    CBLRemoteRequest* request = [[CBLRemoteRequest alloc] initWithMethod: @"POST"
                                                                     URL: comp.URL
                                                                    body: nil
                                                          requestHeaders: nil
                                                            onCompletion:
                                 ^(id result, NSError *err) {
                                     finished = YES;
                                     error = err;
                                 }
                                 ];
    request.authorizer = self.authorizer;
    [request start];
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10];
    while (!finished && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                                 beforeDate: timeout])
        ;
    Assert(error == nil, @"Couldn't delete remote: %@", error);
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


@end