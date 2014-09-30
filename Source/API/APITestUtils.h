//
//  APITestUtils.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/8/14.
//
//

#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"
#import "CBL_Shared.h"
#import "Test.h"


#if DEBUG


__unused
static CBLDatabase* createManagerAndEmptyDBAtPath(NSString* path) {
    CBLManager* dbmgr = [CBLManager createEmptyAtTemporaryPath: path];
    CAssert(dbmgr);
    NSError* error;
    CBLDatabase* db = [dbmgr createEmptyDatabaseNamed: @"test_db" error: &error];
    CAssert(db, @"Couldn't create test_db: %@", error);
    return db;
}


static CBLDatabase* createEmptyDB(void) {
    CBLManager* dbmgr = [CBLManager sharedInstance];
    CAssert(dbmgr);
    Assert(![dbmgr.shared isDatabaseOpened: @"test_db"], @"Last test forgot to close test_db!");
    NSError* error;
    CBLDatabase* db = [dbmgr createEmptyDatabaseNamed: @"test_db" error: &error];
    CAssert(db, @"Couldn't create test_db: %@", error);
    AfterThisTest(^{
        [db _close];
        Assert(![[CBLManager sharedInstance].shared isDatabaseOpened: @"test_db"],
               @"Someone still has test_db open!");
    });
    return db;
}


__unused
static CBLDatabase* reopenTestDB(CBLDatabase* db) {
    [db _close];
    [[CBLManager sharedInstance] _forgetDatabase: db];
    NSError* error;
    CBLDatabase* db2 = [[CBLManager sharedInstance] databaseNamed: @"test_db" error: &error];
    CAssert(db2, @"Couldn't reopen db: %@", error);
    CAssert(db2 != db, @"reopenTestDB couldn't make a new instance");
    AfterThisTest(^{
        [db2 _close];
    });
    return db2;
}


__unused
static CBLDocument* createDocumentWithProperties(CBLDatabase* db,
                                                 NSDictionary* properties) {
    CBLDocument* doc;
    NSDictionary* userProperties;
    if (properties.cbl_id) {
        doc = [db documentWithID: properties.cbl_id];
        NSMutableDictionary* props = [properties mutableCopy];
        [props removeObjectForKey: @"_id"];
        userProperties = props;
    } else {
        doc = [db createDocument];
        userProperties = properties;
    }
    CAssert(doc != nil);
    CAssertNil(doc.currentRevisionID);
    CAssertNil(doc.currentRevision);
    CAssert(doc.documentID, @"Document has no ID"); // 'untitled' docs are no longer untitled (8/10/12)

    NSError* error;
    CAssert([doc putProperties: properties error: &error], @"Couldn't save: %@", error);  // save it!
    
    CAssert(doc.documentID);
    CAssert(doc.currentRevisionID);

    CAssertEqual(doc.userProperties, userProperties);
    CAssertEq(db[doc.documentID], doc);
    //Log(@"Created %p = %@", doc, doc);
    return doc;
}


__unused
static void createDocuments(CBLDatabase* db, unsigned n) {
    [db inTransaction:^BOOL{
        for (unsigned i=0; i<n; i++) {
            @autoreleasepool {
                NSDictionary* properties = @{@"testName": @"testDatabase", @"sequence": @(i)};
                createDocumentWithProperties(db, properties);
            }
        }
        return YES;
    }];
}

#endif // DEBUG
