//
//  CBLTestCase.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/19/14.
//
//

#import <CouchbaseLite/CouchbaseLite.h>
#import <CouchbaseLite/CouchbaseLitePrivate.h>
#import <XCTest/XCTest.h>
#import "CollectionUtils.h"
@protocol CBLAuthorizer;


// Map the MYUtilities assertion names and test macros onto the XCTest ones:
#define Assert          XCTAssert
#define AssertEq        XCTAssertEqual
#define AssertEqual     XCTAssertEqualObjects
#define AssertNil       XCTAssertNil
#define RequireTestCase(TC) // ignored; there's no equivalent of this

#define Log             NSLog
#define Warn(FMT, ...)  NSLog(@"WARNING: " FMT, ##__VA_ARGS__)


// Similar to AssertEqual, but (a) allows float NSNumbers to be "almost" equal,
// and (b) logs a diff of the object trees when they differ.
#define AssertEqualish(A, B)    [self _assertEqualish: (A) to: (B)]


// Adds a non-persistent credential to the NSURLCredentialStorage.
void AddTemporaryCredential(NSURL* url, NSString* realm,
                            NSString* username, NSString* password);


/** Base class for Couchbase Lite unit tests. */
@interface CBLTestCase : XCTestCase

/** Locates a test fixture by name, in the unit-test bundle. */
- (NSString*) pathToTestFile: (NSString*)name;

/** Returns the contents of a named test fixture in the unit-test bundle. */
- (NSData*) contentsOfTestFile: (NSString*)name;

// internal:
- (void) _assertEqualish: (id)a to: (id)b;
@end


/** A Couchbase Lite unit test that creates a temporary empty database. */
@interface CBLTestCaseWithDB : CBLTestCase
{
    @protected
    // These are created and empty at the start of each test, and deleted afterwards:
    CBLManager* dbmgr;
    CBLDatabase* db;
}

// Closes and re-opens 'db'.
- (void) reopenTestDB;

// Deletes and re-creates 'db'
- (void) eraseTestDB;

/** Creates a document in the test database with the given properties. */
- (CBLDocument*) createDocumentWithProperties: (NSDictionary*)properties;

/** Creates a document in 'indb' with the given properties. */
- (CBLDocument*) createDocumentWithProperties: (NSDictionary*)properties
                                   inDatabase: (CBLDatabase*)indb;

/** Creates any number of documents, with properties "testName" and "sequence". */
- (void) createDocuments: (unsigned)numberOfDocs;


/** Returns the base URL of a replication-compatible server that has the necessary databases for
    unit tests. All unit tests that connect to a server should call this function to get the server
    address, so it can be configured at runtime.
    This is configured by the following environment variables; the best way to set
    them up is to use the Xcode scheme editor, under "Arguments" in the "Run" section.
        CBL_TEST_SERVER :    The base URL of the server (defaults to http://127.0.0.1:5984/)
        CBL_TEST_USERNAME :  The user name to authenticate as [optional]
        CBL_TEST_PASSWORD :  The password [required if username is given]
        CBL_TEST_REALM :     The server's "Realm" string [required if username is given]
*/
- (NSURL*) remoteTestDBURL: (NSString*)dbName;

/** Same as remoteTestDBURL: but with a server that uses/requires SSL.
    The environment variable that controls this is CBL_SSL_TEST_SERVER. */
- (NSURL*) remoteSSLTestDBURL: (NSString*)dbName;

/** A CBLAuthorizer to use when talking to the remote test server. */
@property (readonly) id<CBLAuthorizer> authorizer;

/** The self-signed cert(s) of the remote test server's SSL identity. */
@property (readonly) NSArray* remoteTestDBAnchorCerts;

/** Deletes a remote database. Works only with CouchDB, not Sync Gateway. */
- (void) eraseRemoteDB: (NSURL*)url;

@end
