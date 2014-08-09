//
//  APITestUtils.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/8/14.
//
//

#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"
#import "Test.h"


#if DEBUG

static CBLDatabase* createEmptyDB(void) {
    CBLManager* dbmgr = [CBLManager sharedInstance];
    CAssert(dbmgr);
    NSError* error;
    CBLDatabase* db = [dbmgr createEmptyDatabaseNamed: @"test_db" error: &error];
    CAssert(db, @"Couldn't create test_db: %@", error);
    return db;
}


static void closeTestDB(CBLDatabase* db) {
    CAssert(db != nil);
    CAssert([db close]);
}


__unused
static CBLDatabase* reopenTestDB(CBLDatabase* db) {
    closeTestDB(db);
    [[CBLManager sharedInstance] _forgetDatabase: db];
    NSError* error;
    CBLDatabase* db2 = [[CBLManager sharedInstance] databaseNamed: @"test_db" error: &error];
    CAssert(db2, @"Couldn't reopen db: %@", error);
    CAssert(db2 != db, @"reopenTestDB couldn't make a new instance");
    return db2;
}


__unused
static CBLDocument* createDocumentWithProperties(CBLDatabase* db,
                                                 NSDictionary* properties) {
    CBLDocument* doc = [db createDocument];
    CAssert(doc != nil);
    CAssertNil(doc.currentRevisionID);
    CAssertNil(doc.currentRevision);
    CAssert(doc.documentID, @"Document has no ID"); // 'untitled' docs are no longer untitled (8/10/12)

    NSError* error;
    CAssert([doc putProperties: properties error: &error], @"Couldn't save: %@", error);  // save it!
    
    CAssert(doc.documentID);
    CAssert(doc.currentRevisionID);
    CAssertEqual(doc.userProperties, properties);
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
