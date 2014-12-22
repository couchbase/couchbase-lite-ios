//
//  CBLTestCase.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/19/14.
//
//

#import "CBLTestCase.h"
#import "MYURLUtils.h"
#import "CBLRemoteRequest.h"


// The default remote server URL used by RemoteTestDBURL().
#define kDefaultRemoteTestServer @"http://127.0.0.1:5984/"


extern NSString* WhyUnequalObjects(id a, id b); // from Test.m


@interface CBLManager (Secret)
+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name;
- (CBLDatabase*) createEmptyDatabaseNamed: (NSString*)name error: (NSError**)outError;
- (void) _forgetDatabase: (CBLDatabase*)db;
@end


@implementation CBLTestCase


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


@end


@implementation CBLTestCaseWithDB


- (void)setUp {
    [super setUp];

    dbmgr = [CBLManager createEmptyAtTemporaryPath: @"CBL_iOS_Unit_Tests"];
    Assert(dbmgr);
    NSError* error;
    db = [dbmgr createEmptyDatabaseNamed: @"db" error: &error];
    Assert(db, @"Couldn't create db: %@", error);
}

- (void)tearDown {
    [db close: NULL];
    [dbmgr close];

    [super tearDown];
}

- (void) reopenTestDB {
    Assert(db != nil);
    NSString* dbName = db.name;
    [db close: NULL];
    [dbmgr _forgetDatabase: db];
    NSError* error;

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
    else if (urlStr.length == 0)
        return nil;
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


- (void) deleteRemoteDB: (NSURL*)dbURL {
    Log(@"Deleting %@", dbURL);
    __block NSError* error = nil;
    __block BOOL finished = NO;
    CBLRemoteRequest* request = [[CBLRemoteRequest alloc] initWithMethod: @"DELETE"
                                                                     URL: dbURL
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
    Assert(error == nil || error.code == 404, @"Couldn't delete remote: %@", error);
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