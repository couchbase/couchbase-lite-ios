//
//  Database_Tests.m
//  CBL iOS Unit Tests
//
//  Created by Jens Alfke on 12/19/14.
//
//

#import "CBLTestCase.h"
#import "CBLInternal.h"


@interface Database_Tests : CBLTestCaseWithDB
@end


@implementation Database_Tests


- (void) test00_Manager {
    NSString* dbName = db.name;
    AssertEqual(dbmgr.allDatabaseNames, @[dbName]);

    NSError* error;
    CBLDatabase* founddb = [dbmgr databaseNamed: dbName error: &error];
    Assert(founddb, @"Couldn't get/create test_db: %@", error);
    AssertEq(founddb, db);

    // openDatabaseNamed:withOptions: returns existing Database object
    CBLDatabaseOptions* dbOptions = [CBLDatabaseOptions new];
    founddb = [dbmgr openDatabaseNamed: dbName withOptions: dbOptions error: &error];
    AssertEq(founddb, db);

    // Can't create a readOnly database
    dbOptions.readOnly = YES;
    founddb = [dbmgr openDatabaseNamed: @"foo" withOptions: dbOptions error: &error];
    AssertNil(founddb);

    // Open a read-only manager on the same directory:
    {
        CBLManagerOptions options = {.readOnly= true};
        CBLManager* ro = [[CBLManager alloc] initWithDirectory: dbmgr.directory options: &options
                                                         error: &error];
        Assert(ro);

        // Read-only Manager can't create a database:
        CBLDatabase *rodb = [ro databaseNamed: @"foo" error: &error];
        AssertNil(rodb);

        // ...even if db is opened without the readOnly flag
        dbOptions.readOnly = NO;
        rodb = [dbmgr openDatabaseNamed: @"foo" withOptions: dbOptions error: &error];
        AssertNil(rodb);

        // ...but it can open an existing one:
        rodb = [ro existingDatabaseNamed: dbName error: &error];
        Assert(rodb);
        // ...but can't create a document:
        CBLDocument* doc = [rodb createDocument];
        Assert(![doc putProperties: @{@"foo": @"bar"} error: &error]);

        Assert(![rodb compact: &error]);
        Assert(![rodb deleteDatabase: &error]);

        [ro close];
    }

    {
        // Open a second read/write Manager
        CBLManager* otherMgr = [[CBLManager alloc] initWithDirectory: dbmgr.directory options: NULL
                                                         error: &error];
        // Open a read-only database:
        dbOptions.readOnly = YES;
        CBLDatabase *rodb = [otherMgr openDatabaseNamed: dbName withOptions: dbOptions error: &error];
        Assert(rodb);
        // Make sure it can't create a document:
        CBLDocument *doc = [rodb createDocument];
        Assert(![doc putProperties: @{@"foo": @"bar"} error: &error]);
        AssertEq(error.code, kCBLStatusForbidden);
        [otherMgr close];
    }
}


- (void) test00_ValidDatabaseNames {
    for (NSString* name in @[@"f", @"foo123", @"foo/($12)", @"f+-_00/"])
        Assert([CBLManager isValidDatabaseName: name]);
    NSMutableString* longName = [@"long" mutableCopy];
    while (longName.length < 240)
        [longName appendString: @"!"];
    for (NSString* name in @[@"", @"0", @"123foo", @"Foo", @"/etc/passwd", @"foo ", @"_foo", longName])
        Assert(![CBLManager isValidDatabaseName: name], @"Db name '%@' should not be valid", name);
}


- (void)test01_ExcludedFromBackup {
    AssertEq(dbmgr.excludedFromBackup, NO);
    dbmgr.excludedFromBackup = YES;
    AssertEq(dbmgr.excludedFromBackup, YES);
}


- (void)test02_DeleteDatabase {
    NSString* dbName = db.name;
    // Delete the database
    NSError* error;
    BOOL result = [db deleteDatabase: &error];
    Assert(result);
    db = nil;

    // Check if the database still exists or not
    error = nil;
    db = [dbmgr existingDatabaseNamed: dbName error: &error];
    Assert(!db);
    Assert(error);
    Assert(error.code == 404);

    // Test with multiple CBLManager operating on the same thread
    // Copy the shared manager and create a new database
    error = nil;
    CBLManager* copiedMgr = [dbmgr copy];
    CBLDatabase* localdb = [copiedMgr databaseNamed: dbName error: &error];
    Assert(localdb, @"Couldn't open db: %@", error);

    // Get the database from the shared manager and delete
    error = nil;
    localdb = [dbmgr databaseNamed: dbName error: &error];
    // Close the copied manager before deleting the database
    [copiedMgr close];
    result = [localdb deleteDatabase: &error];
    Assert(result, @"Couldn't delete db: %@", error);

    // Check if the database still exists or not
    error = nil;
    localdb = [dbmgr existingDatabaseNamed: dbName error: &error];
    Assert(error);
    Assert(error.code == 404);
    Assert(!localdb);

    // Test with multiple CBLManger operating on different threads
    dispatch_queue_t queue = dispatch_queue_create("DeleteDatabaseTest", NULL);
    copiedMgr = [dbmgr copy];
    copiedMgr.dispatchQueue = queue;
    __block CBLDatabase* copiedMgrDb;
    dispatch_sync(queue, ^{
        NSError *error;
        copiedMgrDb = [copiedMgr databaseNamed: dbName error: &error];
        Assert(copiedMgrDb, @"Couldn't open db: %@", error);
    });

    // Get the database from the shared manager and delete
    error = nil;
    localdb = [dbmgr databaseNamed: dbName error: &error];
    result = [localdb deleteDatabase: &error];
    Assert(result, @"Couldn't delete db: %@", error);

    // Cleanup
    dispatch_sync(queue, ^{
        [copiedMgr close];
    });
}


- (void) test03_CreateDocument {
    NSDictionary* properties = @{@"testName": @"testCreateDocument",
                                @"tag": @1337};
    CBLDocument* doc = [self createDocumentWithProperties: properties];
    
    NSString* docID = doc.documentID;
    Assert(docID.length > 10, @"Invalid doc ID: '%@'", docID);
    NSString* currentRevisionID = doc.currentRevisionID;
    Assert(currentRevisionID.length > 10, @"Invalid doc revision: '%@'", currentRevisionID);

    AssertEqual(doc.userProperties, properties);

    AssertEq([db documentWithID: docID], doc);

    [db _clearDocumentCache]; // so we can load fresh copies

    CBLDocument* doc2 = [db existingDocumentWithID: docID];
    AssertEqual(doc2.documentID, docID);
    AssertEqual(doc2.currentRevision.revisionID, currentRevisionID);

    AssertNil([db existingDocumentWithID: @"b0gus"]);
}


- (void) test04_ExistingDocument {
    AssertNil([db existingDocumentWithID: @"missing"]);
    CBLDocument* doc = [db documentWithID: @"missing"];
    Assert(doc != nil);
    AssertNil([db existingDocumentWithID: @"missing"]);
}


- (void) test05_CreateRevisions {
    RequireTestCase(API_CreateDocument);
    NSDictionary* properties = @{@"testName": @"testCreateRevisions",
    @"tag": @1337};
    CBLDocument* doc = [self createDocumentWithProperties: properties];
    CBLSavedRevision* rev1 = doc.currentRevision;
    Assert([rev1.revisionID hasPrefix: @"1-"]);
    AssertEq(rev1.sequence, 1);
    AssertNil(rev1.attachments);

    // Test -createRevisionWithProperties:
    NSMutableDictionary* properties2 = [properties mutableCopy];
    properties2[@"tag"] = @4567;
    NSError* error;
    CBLSavedRevision* rev2 = [rev1 createRevisionWithProperties: properties2 error: &error];
    Assert(rev2, @"Put failed: %@", error);

    Assert([doc.currentRevisionID hasPrefix: @"2-"],
            @"Document revision ID is still %@", doc.currentRevisionID);

    AssertEqual(rev2.revisionID, doc.currentRevisionID);
    Assert(rev2.propertiesAreLoaded);
    AssertEqual(rev2.userProperties, properties2);
    CBLDocument* rev2document = rev2.document;
    AssertEq(rev2document, doc);
    AssertEqual(rev2.properties[@"_id"], doc.documentID);
    AssertEqual(rev2.properties[@"_rev"], rev2.revisionID);

    // Test -createRevision:
    CBLUnsavedRevision* newRev = [rev2 createRevision];
    AssertNil(newRev.revisionID);
    AssertEq(newRev.parentRevision, rev2);
    AssertEqual(newRev.parentRevisionID, rev2.revisionID);
    AssertEqual(([newRev getRevisionHistory: &error]), (@[rev1, rev2]));
    AssertEqual(newRev.properties, rev2.properties);
    AssertEqual(newRev.userProperties, rev2.userProperties);
    newRev.userProperties = @{@"because": @"NoSQL"};
    AssertEqual(newRev.userProperties, @{@"because": @"NoSQL"});
    AssertEqual(newRev.properties,
                 (@{@"because": @"NoSQL", @"_id": doc.documentID, @"_rev": rev2.revisionID}));
    CBLSavedRevision* rev3 = [newRev save: &error];
    Assert(rev3);
    AssertEqual(rev3.userProperties, newRev.userProperties);
}


- (void) test06_RevisionIdEquivalentRevisions {
    NSDictionary* properties = @{@"testName": @"testCreateRevisions",
                                 @"tag": @1337};
    NSDictionary* properties2 = @{@"testName": @"testCreateRevisions",
                                 @"tag": @1338};
    
    CBLDocument* doc = [db createDocument];
    Assert(!doc.isDeleted);
    CBLUnsavedRevision* newRev = [doc newRevision];
    [newRev setUserProperties:properties];
    
    NSError* error;
    CBLSavedRevision* rev1 = [newRev save: &error];
    Assert(rev1, @"Save 1 failed: %@", error);
    
    CBLUnsavedRevision* newRev2a = [rev1 createRevision];
    [newRev2a setUserProperties:properties2];
    CBLSavedRevision* rev2a = [newRev2a save: &error];
    Assert(rev2a, @"Save rev2a failed: %@", error);
    Log(@"rev2a: %@", rev2a);
    
    CBLUnsavedRevision* newRev2b = [rev1 createRevision];
    [newRev2b setUserProperties:properties2];
    CBLSavedRevision* rev2b = [newRev2b saveAllowingConflict:&error];
    Assert(rev2b, @"Save rev2b failed: %@", error);
    Log(@"rev2b: %@", rev2b);
    
    // since both rev2a and rev2b have same content, they should have
    // the same rev ids.
    AssertEqual(rev2a.revisionID, rev2b.revisionID);
}


- (void) test07_CreateNewRevisions {
    RequireTestCase(API_CreateRevisions);
    NSDictionary* properties = @{@"testName": @"testCreateRevisions",
    @"tag": @1337};
    CBLDocument* doc = [db createDocument];
    Assert(!doc.isDeleted);
    CBLUnsavedRevision* newRev = [doc newRevision];

    CBLDocument* newRevDocument = newRev.document;
    AssertEq(newRevDocument, doc);
    AssertEq(newRev.database, db);
    AssertNil(newRev.parentRevisionID);
    AssertNil(newRev.parentRevision);
    AssertEqual(newRev.properties, $mdict({@"_id", doc.documentID}));
    Assert(!newRev.isDeletion);
    AssertEq(newRev.sequence, 0);

    newRev[@"testName"] = @"testCreateRevisions";
    newRev[@"tag"] = @1337;
    AssertEqual(newRev.userProperties, properties);

    NSError* error;
    CBLSavedRevision* rev1 = [newRev save: &error];
    Assert(rev1, @"Save 1 failed: %@", error);
    AssertEqual(rev1, doc.currentRevision);
    Assert([rev1.revisionID hasPrefix: @"1-"]);
    AssertEq(rev1.sequence, 1);
    AssertNil(rev1.parentRevisionID);
    AssertNil(rev1.parentRevision);
    AssertEqual(doc.currentRevision, rev1);
    Assert(!doc.isDeleted);

    newRev = [rev1 createRevision];
    newRevDocument = newRev.document;
    AssertEq(newRevDocument, doc);
    AssertEq(newRev.database, db);
    AssertEqual(newRev.parentRevisionID, rev1.revisionID);
    AssertEqual(newRev.parentRevision, rev1);
    AssertEqual(newRev.properties, rev1.properties);
    AssertEqual(newRev.userProperties, rev1.userProperties);
    Assert(!newRev.isDeletion);

    newRev[@"tag"] = @4567;
    CBLSavedRevision* rev2 = [newRev save: &error];
    Assert(rev2, @"Save 2 failed: %@", error);
    AssertEqual(rev2, doc.currentRevision);
    Assert([rev2.revisionID hasPrefix: @"2-"]);
    AssertEq(rev2.sequence, 2);
    AssertEqual(rev2.parentRevisionID, rev1.revisionID);
    AssertEqual(rev2.parentRevision, rev1);

    Assert([doc.currentRevisionID hasPrefix: @"2-"],
            @"Document revision ID is still %@", doc.currentRevisionID);

    // Add a deletion/tombstone revision:
    newRev = doc.newRevision;
    AssertEqual(newRev.parentRevisionID, rev2.revisionID);
    AssertEqual(newRev.parentRevision, rev2);
    newRev.isDeletion = true;
    CBLSavedRevision* rev3 = [newRev save: &error];
    Assert(rev3, @"Save 2 failed: %@", error);
    Assert([rev3.revisionID hasPrefix: @"3-"], @"Unexpected revID '%@'", rev3.revisionID);
    AssertEq(rev3.sequence, 3);
    Assert(rev3.isDeletion);

    Assert(doc.isDeleted);
    AssertNil(doc.currentRevision);
    AssertEqual([doc getLeafRevisions: &error], @[rev3]);
    CBLDocument* doc2 = db[doc.documentID];
    AssertEq(doc2, doc);
}


- (void) test071_PutExistingRevision {
    CBLDocument* doc = [self createDocumentWithProperties: @{@"foo": @1}];

    NSError* error;
    Assert(([doc putExistingRevisionWithProperties: @{@"foo": @2}
                                       attachments: nil
                                   revisionHistory: @[@"3-cafebabe", @"2-feedba95", doc.currentRevisionID]
                                           fromURL: nil
                                             error: &error]));
    CBLRevision* rev = [doc revisionWithID: @"3-cafebabe"];
    Assert(rev);
    Assert(!rev.isDeletion);
    AssertEqual(rev.properties, (@{@"_id": doc.documentID,
                                   @"_rev": @"3-cafebabe",
                                   @"foo": @2}));

    // Repeat; should be no error:
    Assert(([doc putExistingRevisionWithProperties: @{@"foo": @2}
                                       attachments: nil
                                   revisionHistory: @[@"3-cafebabe", @"2-feedba95", doc.currentRevisionID]
                                           fromURL: nil
                                             error: &error]));

    // Add a deleted revision:
    Assert(([doc putExistingRevisionWithProperties: @{@"foo": @-1, @"_deleted": @YES}
                                       attachments: nil
                                   revisionHistory: @[@"3-deadbeef", @"2-feedba95", doc.currentRevisionID]
                                           fromURL: nil
                                             error: &error]));
    rev = [doc revisionWithID: @"3-deadbeef"];
    Assert(rev);
    Assert(rev.isDeletion);
    AssertEqual(rev.properties, (@{@"_id": doc.documentID,
                                   @"_rev": @"3-deadbeef",
                                   @"_deleted": @YES,
                                   @"foo": @-1}));
}


- (void) test072_PutExistingRevisionWithAttachment {
    CBLDocument* doc = db[@"some-doc"];

    NSData* content = [@"hi there" dataUsingEncoding: NSUTF8StringEncoding];
    NSDictionary* props = @{@"_attachments": @{
                                    @"foo.txt": @{@"content_type": @"text/plain"},
                                    @"bar.txt": @{@"content_type": @"text/plain", @"stub": @YES}}
                            };
    NSDictionary* attachments = @{@"foo.txt": content,
                                  @"bar.txt": content};

    NSError* error;
    Assert(([doc putExistingRevisionWithProperties: props
                                       attachments: attachments
                                   revisionHistory: @[@"1-cafebabe"]
                                           fromURL: nil
                                             error: &error]));

    CBLRevision* rev = doc.currentRevision;
    Assert(rev);
    Assert(!rev.isDeletion);
    AssertEqual(rev.revisionID, @"1-cafebabe");
    CBLAttachment* a = [rev attachmentNamed: @"foo.txt"];
    Assert(a);
    AssertEqual(a.contentType, @"text/plain");
    AssertEqual(a.content, content);
    a = [rev attachmentNamed: @"bar.txt"];
    Assert(a);
    AssertEqual(a.contentType, @"text/plain");
    AssertEqual(a.content, content);
}


- (void) test075_UpdateDocInTransaction {
    // Test for #256, "Conflict error when updating a document multiple times in transaction block"
    CBLDocument* doc = [self createDocumentWithProperties: @{@"testNumber": @7.5,
                                                             @"count": @1}];

    __block BOOL notified = NO;
    id observer = [[NSNotificationCenter defaultCenter]
                                            addObserverForName: kCBLDocumentChangeNotification
                                                        object: doc
                                                         queue: nil
                                                    usingBlock: ^(NSNotification *note) {
                                                        notified = YES;
                                                    }];
    __block CBLRevision* rev3;
    [db inTransaction: ^BOOL {
        // Update doc. The currentRevision should update, but no notification be posted (yet).
        NSError* error;
        NSMutableDictionary* props = [doc.properties mutableCopy];
        props[@"count"] = @2;
        CBLRevision* rev2 = [doc putProperties: props error: &error];
        Assert(rev2 != nil, @"1st update failed: %@", error);
        AssertEqual(doc.currentRevision, rev2);
        Assert(!notified);

        // Update doc again; this should succeed, in the same manner.
        props = [doc.properties mutableCopy];
        props[@"count"] = @3;
        rev3 = [doc putProperties: props error: &error];
        Assert(rev3 != nil, @"2nd update failed: %@", error);
        AssertEqual(doc.currentRevision, rev3);
        Assert(!notified);
        return YES;
    }];
    AssertEqual(doc.currentRevision, rev3);
    // Notifications should be posted as soon as the transaction exits:
    Assert(notified);

    // Now get sneaky and try a failed transaction -- the doc rev change should be backed out:
    notified = NO;
    [db inTransaction: ^BOOL {
        // Update doc. The currentRevision should update, but no notification be posted (yet).
        NSError* error;
        NSMutableDictionary* props = [doc.properties mutableCopy];
        props[@"count"] = @4;
        CBLRevision* rev4 = [doc putProperties: props error: &error];
        Assert(rev4 != nil, @"3rd update failed: %@", error);
        AssertEqual(doc.currentRevision, rev4);
        Assert(!notified);
        return NO;
    }];
    // No notification should be posted by the aborted transaction:
    Assert(!notified);
    // The doc should know that it's back to revision 3:
    AssertEqual(doc[@"count"], @3);
    AssertEqual(doc.currentRevision, rev3);

    [[NSNotificationCenter defaultCenter] removeObserver: observer];
}


- (void) test08_SaveDocumentWithNaNProperty {
    NSDictionary* properties = @{@"aNumber": [NSDecimalNumber notANumber]};
    CBLDocument* doc = [db createDocument];
    NSError* error;
    CBLSavedRevision* rev = [doc putProperties: properties error: &error];
    AssertEq(error.code, 400);
    Assert(!rev);
}


- (void) test09_DeleteDocument {
    NSDictionary* properties = @{@"testName": @"testDeleteDocument"};
    CBLDocument* doc = [self createDocumentWithProperties: properties];
    Assert(!doc.isDeleted);
    Assert(!doc.currentRevision.isDeletion);
    NSError* error;
    Assert([doc deleteDocument: &error]);
    Assert(doc.isDeleted);
    // This test used to check that doc.currentRevision.isDeletion. But having a non-nil
    // currentRevision is inconsistent with a freshly-loaded CBLDocument's behavior, where if the
    // document was previously deleted its currentRevision will initially be nil. (#265)
    AssertNil(doc.currentRevision);
}


- (void) test10_PurgeDocument {
    NSDictionary* properties = @{@"testName": @"testPurgeDocument"};
    CBLDocument* doc = [self createDocumentWithProperties: properties];
    Assert(doc);
    
    NSError* error;
    Assert([doc purgeDocument: &error]);
    
    CBLDocument* redoc = [db _cachedDocumentWithID:doc.documentID];
    Assert(!redoc);
}


- (void) test11_Validation {
    [db setValidationNamed: @"uncool"
                 asBlock: ^void(CBLRevision *newRevision, id<CBLValidationContext> context) {
                     if (!newRevision.properties[@"groovy"])
                         [context rejectWithMessage: @"uncool"];
                 }];
    
    NSDictionary* properties = @{ @"groovy" : @"right on", @"foo": @"bar" };
    CBLDocument* doc = [db createDocument];
    NSError *error;
    Assert([doc putProperties: properties error: &error]);
    
    properties = @{ @"foo": @"bar" };
    doc = [db createDocument];
    Assert(![doc putProperties: properties error: &error]);
    AssertEq(error.code, 403);
    AssertEqual(error.localizedDescription, @"uncool");
    AssertEqual(error.localizedFailureReason, @"uncool");
}


- (void) test12_AllDocuments {
    static const NSUInteger kNDocs = 5;
    [self createDocuments: kNDocs];

    // clear the cache so all documents/revisions will be re-fetched:
    [db _clearDocumentCache];
    
    Log(@"----- all documents -----");
    CBLQuery* query = [db createAllDocumentsQuery];
    //query.prefetch = YES;
    Log(@"Getting all documents: %@", query);
    
    CBLQueryEnumerator* rows = [query run: NULL];
    AssertEq(rows.count, kNDocs);
    NSUInteger n = 0;
    for (CBLQueryRow* row in rows) {
        Log(@"    --> %@", row);
        CBLDocument* doc = row.document;
        Assert(doc, @"Couldn't get doc from query");
        Assert(doc.currentRevision.propertiesAreLoaded, @"QueryRow should have preloaded revision contents");
        Log(@"        Properties = %@", doc.properties);
        Assert(doc.properties, @"Couldn't get doc properties");
        AssertEqual([doc propertyForKey: @"testName"], @"testDatabase");
        n++;
    }
    AssertEq(n, kNDocs);
}

- (void) test12_AllDocumentsPrefixMatchLevel {
    [self createDocumentWithProperties:@{@"_id": @"three"}];
    [self createDocumentWithProperties:@{@"_id": @"four"}];
    [self createDocumentWithProperties:@{@"_id": @"five"}];
    [self createDocumentWithProperties:@{@"_id": @"eight"}];
    [self createDocumentWithProperties:@{@"_id": @"fifteen"}];

    // clear the cache so all documents/revisions will be re-fetched:
    [db _clearDocumentCache];

    CBLQuery* query = [db createAllDocumentsQuery];
    CBLQueryEnumerator* rows = nil;

    // Set prefixMatchLevel = 1, no startKey, ascending:
    query.descending = NO;
    query.endKey = @"f";
    query.prefixMatchLevel = 1;
    rows = [query run: NULL];
    AssertEq(rows.count, 4u);
    AssertEqual(rows.nextRow.key, @"eight");
    AssertEqual(rows.nextRow.key, @"fifteen");
    AssertEqual(rows.nextRow.key, @"five");
    AssertEqual(rows.nextRow.key, @"four");

    // Set prefixMatchLevel = 1, ascending:
    query.descending = NO;
    query.startKey = @"f";
    query.endKey = @"f";
    query.prefixMatchLevel = 1;
    rows = [query run: NULL];
    AssertEq(rows.count, 3u);
    AssertEqual(rows.nextRow.key, @"fifteen");
    AssertEqual(rows.nextRow.key, @"five");
    AssertEqual(rows.nextRow.key, @"four");

    // Set prefixMatchLevel = 1, descending:
    query.descending = YES;
    query.startKey = @"f";
    query.endKey = @"f";
    query.prefixMatchLevel = 1;
    rows = [query run: NULL];
    AssertEq(rows.count, 3u);
    AssertEqual(rows.nextRow.key, @"four");
    AssertEqual(rows.nextRow.key, @"five");
    AssertEqual(rows.nextRow.key, @"fifteen");

    // Set prefixMatchLevel = 1, ascending, prefix = fi:
    query.descending = NO;
    query.startKey = @"fi";
    query.endKey = @"fi";
    query.prefixMatchLevel = 1;
    rows = [query run: NULL];
    AssertEq(rows.count, 2u);
    AssertEqual(rows.nextRow.key, @"fifteen");
    AssertEqual(rows.nextRow.key, @"five");
}


- (void) test12_AllDocumentsBySequence {
    static const NSUInteger kNDocs = 10;
    [self createDocuments: kNDocs];

    // clear the cache so all documents/revisions will be re-fetched:
    [db _clearDocumentCache];

    CBLQuery* query = [db createAllDocumentsQuery];
    query.allDocsMode = kCBLBySequence;
    CBLQueryEnumerator* rows = [query run: NULL];
    SequenceNumber n = 0;
    for (CBLQueryRow* row in rows) {
        n++;
        CBLDocument* doc = row.document;
        Assert(doc, @"Couldn't get doc from query");
        AssertEq(doc.currentRevision.sequence, n);
    }
    AssertEq(n, kNDocs);

    query = [db createAllDocumentsQuery];
    query.allDocsMode = kCBLBySequence;
    query.startKey = @3;
    rows = [query run: NULL];
    n = 2;
    for (CBLQueryRow* row in rows) {
        n++;
        CBLDocument* doc = row.document;
        Assert(doc, @"Couldn't get doc from query");
        AssertEq(doc.currentRevision.sequence, n);
    }
    AssertEq(n, kNDocs);

    query = [db createAllDocumentsQuery];
    query.allDocsMode = kCBLBySequence;
    query.endKey = @6;
    rows = [query run: NULL];
    n = 0;
    for (CBLQueryRow* row in rows) {
        n++;
        CBLDocument* doc = row.document;
        Assert(doc, @"Couldn't get doc from query");
        AssertEq(doc.currentRevision.sequence, n);
    }
    AssertEq(n, 6);

    query = [db createAllDocumentsQuery];
    query.allDocsMode = kCBLBySequence;
    query.startKey = @3;
    query.endKey = @6;
    query.inclusiveStart = query.inclusiveEnd = NO;
    rows = [query run: NULL];
    n = 3;
    for (CBLQueryRow* row in rows) {
        n++;
        CBLDocument* doc = row.document;
        Assert(doc, @"Couldn't get doc from query");
        AssertEq(doc.currentRevision.sequence, n);
    }
    AssertEq(n, 5);
}


- (void) test12_AllDocumentsBySequenceDescending {
    static const NSUInteger kNDocs = 10;
    [self createDocuments: kNDocs];

    // clear the cache so all documents/revisions will be re-fetched:
    [db _clearDocumentCache];

    CBLQuery* query = [db createAllDocumentsQuery];
    query.descending = YES;
    query.allDocsMode = kCBLBySequence;
    CBLQueryEnumerator* rows = [query run: NULL];
    SequenceNumber n = kNDocs;
    for (CBLQueryRow* row in rows) {
        CBLDocument* doc = row.document;
        Assert(doc, @"Couldn't get doc from query");
        AssertEq(doc.currentRevision.sequence, n);
        n--;
    }
    AssertEq(n, 0);

    query = [db createAllDocumentsQuery];
    query.descending = YES;
    query.allDocsMode = kCBLBySequence;
    query.startKey = @3;
    rows = [query run: NULL];
    n = 3;
    for (CBLQueryRow* row in rows) {
        CBLDocument* doc = row.document;
        Assert(doc, @"Couldn't get doc from query");
        AssertEq(doc.currentRevision.sequence, n);
        n--;
    }
    AssertEq(n, 0);

    query = [db createAllDocumentsQuery];
    query.descending = YES;
    query.allDocsMode = kCBLBySequence;
    query.endKey = @6;
    rows = [query run: NULL];
    n = kNDocs;
    for (CBLQueryRow* row in rows) {
        CBLDocument* doc = row.document;
        Assert(doc, @"Couldn't get doc from query");
        AssertEq(doc.currentRevision.sequence, n);
        n--;
    }
    AssertEq(n, 5);

    query = [db createAllDocumentsQuery];
    query.descending = YES;
    query.allDocsMode = kCBLBySequence;
    query.startKey = @6;
    query.endKey = @3;
    query.inclusiveStart = query.inclusiveEnd = NO;
    rows = [query run: NULL];
    n = 5;
    for (CBLQueryRow* row in rows) {
        CBLDocument* doc = row.document;
        Assert(doc, @"Couldn't get doc from query");
        AssertEq(doc.currentRevision.sequence, n);
        n--;
    }
    AssertEq(n, 3);
}


- (void) test13_LocalDocs {
    NSDictionary* props = [db existingLocalDocumentWithID: @"dock"];
    AssertNil(props);
    NSError* error;
    Assert([db putLocalDocument: @{@"foo": @"bar"} withID: @"dock" error: &error],
            @"Couldn't put new local doc: %@", error);
    props = [db existingLocalDocumentWithID: @"dock"];
    AssertEqual(props[@"foo"], @"bar");
    Assert([props[@"_rev"] hasPrefix: @"1-"]);
    
    Assert([db putLocalDocument: @{@"crave": @"mineral"} withID: @"dock" error: &error],
           @"Couldn't update local doc: %@", error);
    props = [db existingLocalDocumentWithID: @"dock"];
    AssertEqual(props[@"crave"], @"mineral");
    Assert([props[@"_rev"] hasPrefix: @"2-"]);

    Assert([db putLocalDocument: @{@"FOOO": @"BARRR"} withID: @"dock" error: &error],
            @"Couldn't update local doc: %@", error);
    props = [db existingLocalDocumentWithID: @"dock"];
    AssertNil(props[@"foo"]);
    AssertEqual(props[@"FOOO"], @"BARRR");

    Assert([db deleteLocalDocumentWithID: @"dock" error: &error],
            @"Couldn't delete local doc: %@", error);
    props = [db existingLocalDocumentWithID: @"dock"];
    AssertNil(props);

    Assert(![db deleteLocalDocumentWithID: @"dock" error: &error],
            @"Second delete should have failed");
    AssertEq(error.code, 404);
}


#pragma mark - Conflict


- (void) test14_Conflict {
    RequireTestCase(API_History);
    CBLDocument* doc = [self createDocumentWithProperties: @{@"foo": @"bar"}];
    CBLSavedRevision* rev1 = doc.currentRevision;

    NSMutableDictionary* properties = doc.properties.mutableCopy;
    properties[@"tag"] = @2;
    NSError* error;
    CBLSavedRevision* rev2a = [doc putProperties: properties error: &error];

    properties = rev1.properties.mutableCopy;
    properties[@"tag"] = @3;
    CBLUnsavedRevision* newRev = [rev1 createRevision];
    newRev.properties = properties;
    CBLSavedRevision* rev2b = [newRev saveAllowingConflict: &error];
    Assert(rev2b, @"Failed to create a a conflict: %@", error);

    AssertEqual([doc getConflictingRevisions: &error], (@[rev2b, rev2a]));
    AssertEqual([doc getLeafRevisions: &error], (@[rev2b, rev2a]));

    CBLSavedRevision* defaultRev, *otherRev;
    if ([rev2a.revisionID compare: rev2b.revisionID] > 0) {
        defaultRev = rev2a; otherRev = rev2b;
    } else {
        defaultRev = rev2b; otherRev = rev2a;
    }
    AssertEqual(doc.currentRevision, defaultRev);

    CBLQuery* query = [db createAllDocumentsQuery];
    query.allDocsMode = kCBLShowConflicts;
    NSArray* rows = [[query run: NULL] allObjects];
    AssertEq(rows.count, 1u);
    CBLQueryRow* row = rows[0];
    NSArray* revs = row.conflictingRevisions;
    AssertEq(revs.count, 2u);
    AssertEqual(revs[0], defaultRev);
    AssertEqual(revs[1], otherRev);
}


- (void) test15_Resolve_Conflict {
    RequireTestCase(API_History);
    CBLDocument* doc = [self createDocumentWithProperties: @{@"foo": @"bar"}];
    CBLSavedRevision* rev1 = doc.currentRevision;

    NSError* error;

    AssertEq([[doc getLeafRevisions: &error] count], 1u);
    AssertEq([[doc getConflictingRevisions: &error] count], 1u);
    AssertNil(error);

    NSMutableDictionary* properties = doc.properties.mutableCopy;
    properties[@"tag"] = @2;

    CBLSavedRevision* rev2a = [doc putProperties: properties error: &error];

    properties = rev1.properties.mutableCopy;
    properties[@"tag"] = @3;
    CBLUnsavedRevision* newRev = [rev1 createRevision];
    newRev.properties = properties;
    CBLSavedRevision* rev2b = [newRev saveAllowingConflict: &error];
    Assert(rev2b, @"Failed to create a a conflict: %@", error);

    AssertEqual([doc getConflictingRevisions: &error], (@[rev2b, rev2a]));
    AssertEqual([doc getLeafRevisions: &error], (@[rev2b, rev2a]));

    CBLSavedRevision* defaultRev, *otherRev;
    if ([rev2a.revisionID compare: rev2b.revisionID] > 0) {
        defaultRev = rev2a; otherRev = rev2b;
    } else {
        defaultRev = rev2b; otherRev = rev2a;
    }
    AssertEqual(doc.currentRevision, defaultRev);

    [defaultRev deleteDocument:&error];
    AssertNil(error);
    AssertEq([[doc getConflictingRevisions: &error] count], 1u);
    AssertNil(error);
    AssertEq([[doc getLeafRevisions: &error] count], 2u);
    AssertNil(error);

    newRev = [otherRev createRevision];
    properties[@"tag"] = @4;
    newRev.properties = properties;
    CBLSavedRevision* newRevSaved = [newRev save: &error];
    AssertNil(error);
    AssertEq([[doc getLeafRevisions: &error] count], 2u);
    AssertEq([[doc getConflictingRevisions: &error] count], 1u);
    AssertEqual(doc.currentRevision, newRevSaved);
}


- (void) test16_CreateIdenticalParentContentRevisions {
    NSMutableDictionary *props = [NSMutableDictionary
                                  dictionaryWithDictionary:@{@"foo": @"bar"}];

    CBLDocument* doc = [self createDocumentWithProperties: props];
    CBLSavedRevision* rev = doc.currentRevision;

    NSError* error;
    CBLUnsavedRevision* unsavedRev1 = [rev createRevision];
    [unsavedRev1 setProperties: props];
    CBLSavedRevision* savedRev1 = [unsavedRev1 saveAllowingConflict: &error];
    AssertNil(error);

    CBLUnsavedRevision* unsavedRev2 = [rev createRevision];
    [unsavedRev2 setProperties: props];
    CBLSavedRevision* savedRev2 = [unsavedRev2 saveAllowingConflict: &error];
    AssertNil(error);

    AssertEqual(savedRev1.revisionID, savedRev2.revisionID);

    NSArray* conflicts = [doc getConflictingRevisions: &error];
    AssertNil(error);
    AssertEq(1u, [conflicts count]);

    CBLQuery* query = [db createAllDocumentsQuery];
    query.allDocsMode = kCBLOnlyConflicts;
    CBLQueryEnumerator* result = [query run:&error];
    AssertNil(error);
    AssertEq(0u, [result count]);
}


#pragma mark - HISTORY


- (void) test17_History {
    NSMutableDictionary* properties = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                @"test06_History", @"testName",
                                @1, @"tag",
                                nil];
    CBLDocument* doc = [self createDocumentWithProperties: properties];
    NSString* rev1ID = [doc.currentRevisionID copy];
    Log(@"1st revision: %@", rev1ID);
    Assert([rev1ID hasPrefix: @"1-"], @"1st revision looks wrong: '%@'", rev1ID);
    AssertEqual(doc.userProperties, properties);
    properties = doc.properties.mutableCopy;
    properties[@"tag"] = @2;
    Assert(![properties isEqual: doc.properties]);
    NSError* error;
    Assert([doc putProperties: properties error: &error]);
    NSString* rev2ID = doc.currentRevisionID;
    Log(@"2nd revision: %@", rev2ID);
    Assert([rev2ID hasPrefix: @"2-"], @"2nd revision looks wrong: '%@'", rev2ID);

    NSArray* revisions = [doc getRevisionHistory: &error];
    Log(@"Revisions = %@", revisions);
    AssertEq(revisions.count, 2u);
    
    CBLSavedRevision* rev1 = revisions[0];
    AssertEqual(rev1.revisionID, rev1ID);
    NSDictionary* gotProperties = rev1.properties;
    AssertEqual(gotProperties[@"tag"], @1);
    
    CBLSavedRevision* rev2 = revisions[1];
    AssertEqual(rev2.revisionID, rev2ID);
    AssertEq(rev2, doc.currentRevision);
    gotProperties = rev2.properties;
    AssertEqual(gotProperties[@"tag"], @2);
    
    AssertEqual([doc getConflictingRevisions: &error], @[rev2]);
    AssertEqual([doc getLeafRevisions: &error], @[rev2]);
}


#pragma mark - ATTACHMENTS


- (void) test18_Attachments {
    NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"testAttachments", @"testName",
                                nil];
    CBLDocument* doc = [self createDocumentWithProperties: properties];
    CBLSavedRevision* rev = doc.currentRevision;
    
    AssertEq(rev.attachments.count, (NSUInteger)0);
    AssertEq(rev.attachmentNames.count, (NSUInteger)0);
    AssertNil([rev attachmentNamed: @"index.html"]);
    
    NSData* body = [@"This is a test attachment!" dataUsingEncoding: NSUTF8StringEncoding];
    CBLUnsavedRevision *rev2 = [doc newRevision];
    [rev2 setAttachmentNamed: @"index.html" withContentType: @"text/plain; charset=utf-8" content:body];

    AssertEq(rev2.attachments.count, (NSUInteger)1);
    AssertEqual(rev2.attachmentNames, [NSArray arrayWithObject: @"index.html"]);
    CBLAttachment* attach = [rev2 attachmentNamed:@"index.html"];
    AssertNil(attach.revision); // No revision set
    AssertNil(attach.document); // No revision set
    AssertEqual(attach.name, @"index.html");
    AssertEqual(attach.contentType, @"text/plain; charset=utf-8");
    AssertEqual(attach.content, body);
    AssertEq(attach.length, (UInt64)body.length);

    NSError * error;
    CBLSavedRevision *rev3 = [rev2 save:&error];
    
    AssertNil(error);
    Assert(rev3);
    AssertEq(rev3.attachments.count, (NSUInteger)1);
    AssertEq(rev3.attachmentNames.count, (NSUInteger)1);

    attach = [rev3 attachmentNamed:@"index.html"];
    Assert(attach);
    AssertEq(attach.document, doc);
    AssertEqual(attach.name, @"index.html");
    AssertEqual(rev3.attachmentNames, [NSArray arrayWithObject: @"index.html"]);

    AssertEqual(attach.contentType, @"text/plain; charset=utf-8");
    AssertEqual(attach.content, body);
    AssertEq(attach.length, (UInt64)body.length);

    // Look at the attachment's file:
    NSURL* bodyURL = attach.contentURL;
    if (self.encryptedAttachmentStore) {
        AssertNil(bodyURL);
    } else {
        Assert(bodyURL.isFileURL);
        AssertEqual([NSData dataWithContentsOfURL: bodyURL], body);
    }

    // Read the attachment from a stream:
    NSInputStream* in = [attach openContentStream];
    NSMutableData* fromStream = [NSMutableData data];
    uint8_t buffer[1024];
    NSInteger bytesRead;
    while ((bytesRead = [in read: buffer maxLength: sizeof(buffer)]) > 0)
        [fromStream appendBytes: buffer length: bytesRead];
    Assert(bytesRead == 0, @"Stream error: %@", in.streamError);
    AssertEqual(fromStream, body);

    CBLUnsavedRevision *newRev = [rev3 createRevision];
    [newRev removeAttachmentNamed: attach.name];
    CBLRevision* rev4 = [newRev save: &error];
    Assert(!error);
    Assert(rev4);
    AssertEq([rev4.attachmentNames count], (NSUInteger)0);

    // Add an attachment with revpos=0 (see #1200)
    NSMutableDictionary* props = [rev3.properties mutableCopy];
    NSMutableDictionary* atts = [props.cbl_attachments mutableCopy];
    props[@"_attachments"] = atts;
    atts[@"zero.txt"] = @{@"content_type": @"text/plain",
                          @"revpos": @0,
                          @"following": @YES};
    BOOL ok = [doc putExistingRevisionWithProperties: props
                                         attachments: @{@"zero.txt": [@"zero" dataUsingEncoding: NSUTF8StringEncoding]}
                                     revisionHistory: @[@"3-0000", rev3.revisionID, rev.revisionID]
                                             fromURL: nil
                                               error: &error];
    Assert(ok, @"Adding attachment with revpos=0 failed: %@", error);

    CBLRevision* rev5 = [doc revisionWithID: @"3-0000"];
    CBLAttachment* att = [rev5 attachmentNamed: @"zero.txt"];
    Assert(att);
}


- (void) test18a_EncryptedAttachments {
    self.encryptedAttachmentStore = YES;
    [self test18_Attachments];
}


- (void) test18b_AttachmentMissingFile {
    NSDictionary* properties = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"testAttachments", @"testName",
                                nil];
    CBLDocument* doc = [self createDocumentWithProperties: properties];

    // Adding an attachment from a nonexistent file should fail:
    NSURL* bodyURL = [NSURL fileURLWithPath: @"/tmp/cbl_body"];
    [NSFileManager.defaultManager removeItemAtURL: bodyURL error: NULL];
    CBLUnsavedRevision *rev2 = [doc newRevision];
    [rev2 setAttachmentNamed: @"index.html"
             withContentType: @"text/plain; charset=utf-8"
                  contentURL: bodyURL];
    AssertNil([rev2 attachmentNamed: @"index.html"]);

    [[@"hi" dataUsingEncoding: NSUTF8StringEncoding] writeToURL: bodyURL atomically: NO];
    [rev2 setAttachmentNamed: @"index.html"
             withContentType: @"text/plain; charset=utf-8"
                  contentURL: bodyURL];
    Assert([rev2 attachmentNamed: @"index.html"]);

    [NSFileManager.defaultManager removeItemAtURL: bodyURL error: NULL];

    [self allowWarningsIn:^{
        NSError * error;
        AssertNil([rev2 save:&error]);
        Assert(error);
        Log(@"Error saving doc: %@", error);
    }];
}


#pragma mark - CHANGE TRACKING


- (void) test19_ChangeTracking {
    __block int changeCount = 0;
    [[NSNotificationCenter defaultCenter] addObserverForName: kCBLDatabaseChangeNotification
                                                      object: db
                                                       queue: nil
                                                  usingBlock: ^(NSNotification *n) {
                                                      ++changeCount;
                                                  }];
    
    [self createDocuments: 5];

    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
    // We expect that the changes reported by the server won't be notified, because those revisions
    // are already cached in memory.
    AssertEq(changeCount, 1);
    
    AssertEq(db.lastSequenceNumber, 5);
}


- (void) test20_ChangeUUID {
    NSString* pub = db.publicUUID;
    NSString* priv = db.privateUUID;
    Assert(pub.length > 10);
    Assert(priv.length > 10);

    NSError* error;
    Assert([db replaceUUIDs: &error], @"replaceUUIDs failed: %@", error);
    Assert(!$equal(pub, db.publicUUID));
    Assert(!$equal(priv, db.privateUUID));
}


#pragma mark - CONCURRENT WRITES:


- (void) lotsaWrites: (NSUInteger)nTransactions ofDocs: (NSUInteger)nDocs
            database: (CBLDatabase*)ondb
{
    NSParameterAssert(ondb);
    for (NSUInteger t = 1; t <= nTransactions; t++) {
        BOOL ok = [ondb inTransaction: ^BOOL {
            Log(@"Transaction #%u ...", (unsigned)t);
            @autoreleasepool {
                for (NSUInteger d = 1; d <= nDocs; d++) {
                    CBLDocument* doc = [ondb createDocument];
                    NSDictionary* props = @{@"transaction": @(t),
                                            @"doc": @(d)};
                    NSError* error;
                    Assert([doc putProperties: props error: &error], @"put failed: %@", error);
                }
                return YES;
            }
        }];
        Assert(ok, @"Transaction failed!");
    }
}

- (void) lotsaReads: (NSUInteger)nReads database: (CBLDatabase*)ondb {
    NSParameterAssert(ondb);
    NSUInteger docCount = 0;
    for (NSUInteger t = 1; t <= nReads; t++) {
        @autoreleasepool {
            usleep(10*1000);
            CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
            NSError* error;
            CBLQueryEnumerator* allDocs = [[ondb createAllDocumentsQuery] run: &error];
            Assert(allDocs, @"getAllDocs failed: %@", error);
            NSUInteger newCount = allDocs.count;
            NSLog(@"#%3u: Reader found %lu docs in %.3g sec", (unsigned)t, (unsigned long)newCount, CFAbsoluteTimeGetCurrent()-time);
            Assert(newCount >= docCount, @"Wrong doc count (used to be %ld)", (unsigned long)docCount);
            docCount = newCount;
        }
    }
}


- (void) test21_ConcurrentWrites {
    const NSUInteger kNTransactions = 100;
    const NSUInteger kNDocs = 100;
    Log(@"Main thread writer: %@", db);

    CBLManager* bgmgr = [dbmgr copy];
    dispatch_queue_t writingQueue = dispatch_queue_create("ConcurrentWritesTest",  NULL);
    dispatch_async(writingQueue, ^{
        Log(@"Writer 2 starting...");
        NSError* error;
        CBLDatabase* bgdb = [bgmgr existingDatabaseNamed: db.name error: &error];
        NSAssert(bgdb, @"Couldn't create bgdb: %@", error);
        Log(@"bg writer: %@", bgdb);
        [self lotsaWrites: kNTransactions ofDocs: kNDocs database: bgdb];
        [bgmgr close];
    });

    CBLManager* readQueueMgr = [dbmgr copy];
    dispatch_queue_t readingQueue = dispatch_queue_create("reading",  NULL);
    dispatch_async(readingQueue, ^{
        Log(@"Reader 1 starting...");
        NSError* error;
        CBLDatabase* bgdb = [readQueueMgr existingDatabaseNamed: db.name error: nil];
        NSAssert(bgdb, @"Couldn't create bgdb: %@", error);
        Log(@"bg reader: %@", bgdb);
        [self lotsaReads: kNTransactions/2 database: bgdb];
        [readQueueMgr close];
    });

    CBLManager* readQueue2Mgr = [dbmgr copy];
    dispatch_queue_t readingQueue2 = dispatch_queue_create("reading",  NULL);
    dispatch_async(readingQueue2, ^{
        Log(@"Reader 2 starting...");
        NSError* error;
        CBLDatabase* bgdb = [readQueue2Mgr existingDatabaseNamed: db.name error: &error];
        NSAssert(bgdb, @"Couldn't create bgdb: %@", error);
        Log(@"bg2 reader: %@", bgdb);
        [self lotsaReads: kNTransactions/2 database: bgdb];
        [readQueue2Mgr close];
    });

    [self lotsaWrites: kNTransactions ofDocs: kNDocs database: db];

    // Wait for all queues to finish:
    dispatch_sync(readingQueue, ^{  });
    dispatch_sync(readingQueue2, ^{  });
    dispatch_sync(writingQueue, ^{  });
}


- (void) test22_CreateDocWithAttachmentInSingleRevision {
    // Set properties:
    CBLDocument* doc1 = [db createDocument];
    CBLUnsavedRevision* newRev1 = [doc1 newRevision];
    NSMutableDictionary* props = [NSMutableDictionary dictionaryWithDictionary:newRev1.properties];
    props[@"foo"] = @"bar";
    newRev1.properties = props;

    NSData* attach1 = [@"attach1" dataUsingEncoding:NSUTF8StringEncoding];
    [newRev1 setAttachmentNamed: @"attach1"
               withContentType: @"text/plain; charset=utf-8"
                       content: attach1];
    NSError* error;
    Assert([newRev1 save: &error], @"Cannot save the document: %@", error);

    // Set userProperties:
    CBLDocument* doc2 = [db createDocument];
    CBLUnsavedRevision* newRev2 = [doc2 newRevision];
    newRev2.userProperties = @{@"foo":@"bar"};
    
    NSData* attach2 = [@"attach2" dataUsingEncoding:NSUTF8StringEncoding];
    [newRev2 setAttachmentNamed: @"attach2"
                withContentType: @"text/plain; charset=utf-8"
                        content: attach2];
    Assert([newRev2 save: &error], @"Cannot save the document: %@", error);
}


#pragma mark - REPLACE DATABASE:

- (void) testReplaceDatabaseAtDir: (NSString*)dir
                       dbFileName: (NSString*)dbFileName
                      attsDirName: (NSString*)attsDirName
                           docIds: (NSArray*)docIds
                      localDocIds: (NSArray*)localDocIds {
    Log(@"Test ReplaceDatabase with the database at %@/%@", dir, dbFileName);

    NSString* dbFile = [self pathToReplaceDbFile: dbFileName inDirectory: dir];
    NSString* attsDir;
    if (attsDirName)
        attsDir = [self pathToReplaceDbFile: attsDirName inDirectory: dir];

    NSError* error;
    BOOL success;
    static NSString* dbName = @"replacedb";
    if (attsDir) {
        success = [dbmgr replaceDatabaseNamed: dbName
                             withDatabaseFile: dbFile
                              withAttachments: attsDir
                                        error: &error];
        Assert(success, @"Couldn't replace database with the database at %@ and"
               " attachments at %@ : %@", dbFile, attsDir, error);
    } else {
        success = [dbmgr replaceDatabaseNamed: dbName
                              withDatabaseDir: dbFile
                                        error: &error];
        Assert(success, @"Couldn't replace database with the database at %@ : %@",
               dbFile, error);
    }

    if (success) {
        [self checkReplacedDatabaseNamed: dbName
                              onComplete: ^(CBLDatabase* replaceDb, CBLQueryEnumerator* rows) {
            NSUInteger attsCount = 0;
            AssertEq(replaceDb.documentCount, docIds.count);
            for (NSString* docId in docIds) {
                CBLDocument* doc = [replaceDb existingDocumentWithID: docId];
                Assert(doc != nil);
                Assert(doc.properties.allKeys > 0);
                for (NSString* name in doc.currentRevision.attachmentNames) {
                    attsCount++;
                    CBLAttachment* attachment = [doc.currentRevision attachmentNamed: name];
                    Assert(attachment != nil);
                    Assert(attachment.content.length > 0);
                }
            }
            Assert(attsCount > 0);

            AssertEq(rows.count, docIds.count);
            for (CBLQueryRow* row in rows) {
                assert([docIds containsObject: row.documentID]);
            }

            for (NSString* localDocId in localDocIds) {
                NSDictionary* localDoc = [replaceDb existingLocalDocumentWithID: localDocId];
                Assert(localDoc.allKeys.count > 0);
            }
        }];
    }

    CBLDatabase* replacedb = [dbmgr databaseNamed: dbName error: &error];
    Assert([replacedb deleteDatabase: &error]);
}

- (void) checkReplacedDatabaseNamed: (NSString*)name
                         onComplete: (void (^)(CBLDatabase*, CBLQueryEnumerator*))onComplete {
    NSError* error;
    CBLDatabase* replaceDb = [dbmgr existingDatabaseNamed: name error: &error];
    Assert(replaceDb, @"Couldn't find the replaced database named %@ : %@", name, error);

    CBLView* view = [replaceDb viewNamed: @"myview"];
    Assert(view);
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"_id"], nil);
    }) version: @"1.0"];

    CBLQuery* query = [view createQuery];
    query.prefetch = YES;
    Assert(query);
    CBLQueryEnumerator* rows = [query run: &error];
    Assert(rows, @"Couldn't query the replaced database named %@ : %@", name, error);

    onComplete(replaceDb, rows);
}


- (NSString*) pathToReplaceDbFile: (NSString*)fileName inDirectory: (NSString*)dir {
    NSString *subDir = @"TestData/replacedb";
    if (dir)
        subDir = [subDir stringByAppendingPathComponent:dir];

    NSString* path = [[NSBundle bundleForClass: [self class]] pathForResource: fileName ofType: nil
                                                                  inDirectory: subDir];
    Assert(path, @"FATAL: Missing file '%@' in bundle directory '%@'", fileName, subDir);
    return path;
}


- (void) test23_ReplaceDatabaseSQLite {
    // Test only SQLite:
    if (!self.isSQLiteDB)
        return;

    // iOS 1.0.4
    [self testReplaceDatabaseAtDir: @"ios104"
                        dbFileName: @"iosdb.cblite"
                       attsDirName: @"iosdb attachments"
                            docIds: @[@"doc1"] localDocIds: nil];

    // Android 1.0.4
    [self testReplaceDatabaseAtDir: @"android104"
                        dbFileName: @"androiddb.cblite"
                       attsDirName: @"androiddb/attachments"
                            docIds: @[@"doc0", @"doc1"] localDocIds: nil];

    // .NET 1.0.4
    [self testReplaceDatabaseAtDir: @"net104"
                        dbFileName: @"netdb.cblite"
                       attsDirName: @"netdb/attachments"
                            docIds: @[@"doc1", @"doc2"] localDocIds: nil];

    // iOS 1.1.0
    [self testReplaceDatabaseAtDir: @"ios110"
                        dbFileName: @"iosdb.cblite"
                       attsDirName: @"iosdb attachments"
                            docIds: @[@"doc1"] localDocIds: nil];

    // Android 1.1.0
    [self testReplaceDatabaseAtDir: @"android110"
                        dbFileName: @"androiddb.cblite"
                       attsDirName: @"androiddb attachments"
                            docIds: @[@"doc0", @"doc1"] localDocIds: nil];

    // .NET 1.1.0
    [self testReplaceDatabaseAtDir: @"net110"
                        dbFileName: @"netdb.cblite"
                       attsDirName: @"netdb attachments"
                            docIds: @[@"doc1"] localDocIds: nil];

    // iOS 1.2.0
    [self testReplaceDatabaseAtDir: @"ios120"
                        dbFileName: @"iosdb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];

    // Android 1.2.0
    [self testReplaceDatabaseAtDir: @"android120"
                        dbFileName: @"androiddb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];

    // .NET 1.2.0
    [self testReplaceDatabaseAtDir: @"net120"
                        dbFileName: @"netdb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];

    // iOS 1.3.0
    [self testReplaceDatabaseAtDir: @"ios130"
                        dbFileName: @"iosdb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];

    // Android 1.3.0
    [self testReplaceDatabaseAtDir: @"android130"
                        dbFileName: @"androiddb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];

    // .NET 1.3.0
    [self testReplaceDatabaseAtDir: @"net130"
                        dbFileName: @"netdb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];
}


- (void) test23b_ReplaceDatabaseForestDB {
    // Test only ForestDB:
    if (self.isSQLiteDB)
        return;

    // iOS 1.2.0
    [self testReplaceDatabaseAtDir: @"ios120-forestdb"
                        dbFileName: @"iosdb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];

    // Android 1.2.0
    [self testReplaceDatabaseAtDir: @"android120-forestdb"
                        dbFileName: @"androiddb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];

    // .NET 1.2.0
    [self testReplaceDatabaseAtDir: @"net120-forestdb"
                        dbFileName: @"netdb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];

    // iOS 1.3.0
    [self testReplaceDatabaseAtDir: @"ios120-forestdb"
                        dbFileName: @"iosdb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];

    // Android 1.3.0
    [self testReplaceDatabaseAtDir: @"android130-forestdb"
                        dbFileName: @"androiddb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];

    // .NET 1.3.0
    [self testReplaceDatabaseAtDir: @"net130-forestdb"
                        dbFileName: @"netdb.cblite2"
                       attsDirName: nil
                            docIds: @[@"doc1", @"doc2"] localDocIds: @[@"local1"]];
}


- (void) test24_upgradeDatabase {
    // Install a canned database:
    NSString* dbDir = [self pathToReplaceDbFile: @"iosdb.cblite2" inDirectory: @"ios130"];
    NSError* error;
    Assert([dbmgr replaceDatabaseNamed: @"replacedb" withDatabaseDir: dbDir error: &error]);

    // Open installed db with storageType set to this test's storage type:
    CBLDatabaseOptions* options = [CBLDatabaseOptions new];
    options.storageType = self.isSQLiteDB ? kCBLSQLiteStorage : kCBLForestDBStorage;
    CBLDatabase* replacedb = [dbmgr openDatabaseNamed: @"replacedb" withOptions: options error: &error];
    Assert(replacedb, @"Opening db failed: %@", error);

    // Verify storage type matches what we requested:
    AssertEqual(replacedb.storage.class.description, self.isSQLiteDB ? @"CBL_SQLiteStorage" : @"CBL_ForestDBStorage");

    // Test db contents:
    [self checkReplacedDatabaseNamed: @"replacedb"
                         onComplete: ^(CBLDatabase* targetDb, CBLQueryEnumerator* rows) {
                             AssertEq(rows.count, 2u);
                             CBLDocument* doc = [rows rowAtIndex:0].document;
                             AssertEqual(doc.documentID, @"doc1");
                             AssertEq(doc.currentRevision.attachments.count, 1u);
                             CBLAttachment* att= [doc.currentRevision attachmentNamed: @"attach1"];
                             Assert(att);
                             AssertEq(att.length, att.content.length);
                             
                             // https://github.com/couchbase/couchbase-lite-ios/issues/1041:
                             NSDictionary* localDoc = [targetDb existingLocalDocumentWithID: @"local1"];
                             Assert(localDoc);
                          }];

    // Close and re-open the db using SQLite storage type. Should fail if it used to be ForestDB:
    Assert([replacedb close: &error]);
    options.storageType = kCBLSQLiteStorage;
    replacedb = [dbmgr openDatabaseNamed: @"replacedb" withOptions: options error: &error];
    if (self.isSQLiteDB) {
        Assert(replacedb, @"Couldn't re-open SQLite db");
    } else {
        Assert(!replacedb, @"Incorrectly re-opened ForestDB db as SQLite");
        AssertEq(error.code, 406);
    }
}


#pragma mark - ETC.


- (void) test25_CloseDatabase {
    // Add some documents:
    for (NSUInteger i = 0; i < 10; i++) {
        CBLDocument* doc = [db createDocument];
        CBLSavedRevision* rev = [doc putProperties: @{@"foo": @"bar"} error: nil];
        Assert(rev);
    }
    
    // Use the background database:
    __block CBLDatabase* bgdb;
    XCTestExpectation* expectation =
        [self expectationWithDescription: @"Adding a document in background"];
    [dbmgr backgroundTellDatabaseNamed: db.name to: ^(CBLDatabase *_bgdb) {
        bgdb = _bgdb;
        CBLDocument* doc = [_bgdb createDocument];
        CBLSavedRevision* rev = [doc putProperties: @{@"foo": @"bar"} error: nil];
        [expectation fulfill];
        Assert(rev);
    }];
    [self waitForExpectationsWithTimeout: 1.0 handler: nil];
    
    // Close database:
    NSError* error;
    [self keyValueObservingExpectationForObject: bgdb keyPath: @"isOpen" expectedValue: @(NO)];
    Assert([db close: &error], @"Cannot close the database: %@", error);
    [self waitForExpectationsWithTimeout: 1.0 handler: nil];
}


- (void) test26_DocumentExpiry {
    NSDate* future = [NSDate dateWithTimeIntervalSinceNow: 12345];
    Log(@"Now is %@", [NSDate date]);
    CBLDocument* doc = [self createDocumentWithProperties: @{@"foo": @17}];
    AssertNil(doc.expirationDate);
    doc.expirationDate = future;
    NSDate* exp = doc.expirationDate;
    Log(@"Doc expiration is %@", exp);
    Assert(exp != nil);
    Assert(fabs([exp timeIntervalSinceDate: future]) < 1.0);

    NSDate* next = [NSDate dateWithTimeIntervalSince1970: db.storage.nextDocumentExpiry];
    Log(@"Next expiration at %@", next);

    doc.expirationDate = nil;
    AssertNil(doc.expirationDate);

    AssertEq(db.storage.nextDocumentExpiry, 0ull);

    // Can a nonexistent document have an expiration date?
    doc = db[@"foo"];
    AssertNil(doc.expirationDate);
    doc.expirationDate = future;
    exp = doc.expirationDate;
    Log(@"Nonexistent doc expiration is %@", exp);
//    Assert(exp != nil);
//    Assert(fabs(exp.timeIntervalSince1970 - now.timeIntervalSince1970) < 1.0);
//    AssertEq(db.storage.nextDocumentExpiry, (UInt64)exp.timeIntervalSince1970);

    Log(@"Creating documents");
    [self createDocuments: 10000];

    Log(@"Marking docs for expiration");
    __block int total = 0, marked = 0;
    __block CBLDocument* someDoc = nil;
    [db inTransaction:^BOOL{
        for (CBLQueryRow* row in [[db createAllDocumentsQuery] run: NULL]) {
            CBLDocument* doc = row.document;
            int sequence = [doc[@"sequence"] intValue];
            if (sequence % 10 == 6) {
                doc.expirationDate = [NSDate dateWithTimeIntervalSinceNow: 2];
                someDoc = doc;
                ++marked;
            } else if (sequence % 10 == 3) {
                doc.expirationDate = future;
            }
            ++total;
        }
        return YES;
    }];
    AssertEq(total, 10001);
    AssertEq(marked, 1000);

    next = [NSDate dateWithTimeIntervalSince1970: db.storage.nextDocumentExpiry];
    Log(@"Next expiration at %@ (in %.3f sec)", next, next.timeIntervalSinceNow);
    Assert(next.timeIntervalSinceNow <= 2);
    Assert(next.timeIntervalSinceNow >= -30);

    __block unsigned dbChangesReceived = 0;
    [self expectationForNotification: kCBLDatabaseChangeNotification
                              object: db
                             handler: ^BOOL(NSNotification* notification) {
                                 NSArray* changes = notification.userInfo[@"changes"];
                                 NSUInteger purges = 0;
                                 for (CBLDatabaseChange* change in changes) {
                                     Assert(change.documentID);
                                     if (!change.revisionID)
                                         ++purges;
                                 }
                                 Log(@"Received %@ with %lu changes, %lu purges",
                                     notification.name, (unsigned long)changes.count, (unsigned long)purges);
                                 dbChangesReceived += purges;
                                 Assert(dbChangesReceived <= 1000);
                                 return (dbChangesReceived >= 1000);
                             }];

    Assert(someDoc.currentRevision != nil);
    [self expectationForNotification: kCBLDocumentChangeNotification
                              object: someDoc
                             handler: ^BOOL(NSNotification* notification) {
                                 Log(@"Received %@", notification);
                                 CBLDatabaseChange* change = notification.userInfo[@"change"];
                                 Assert(change);
                                 AssertEqual(change.documentID, someDoc.documentID);
                                 AssertNil(change.revisionID);
                                 AssertNil(someDoc.currentRevision);
                                 return YES;
                             }];

    Log(@"Waiting for auto-expiration...");
    NSPredicate* expiredPred = [NSPredicate predicateWithFormat: @"documentCount <= 9001"];
    (void)[self expectationForPredicate: expiredPred evaluatedWithObject: db handler: nil];

    [self waitForExpectationsWithTimeout: 30.0 handler: nil];
    AssertEq(db.documentCount, 9001u);

    total = 0;
    for (CBLQueryRow* row in [[db createAllDocumentsQuery] run: NULL]) {
        CBLDocument* doc = row.document;
        int sequence = [doc[@"sequence"] intValue];
        Assert(sequence % 10 != 6);
        ++total;
    }
    AssertEq(total, 9001);

    next = [NSDate dateWithTimeIntervalSince1970: db.storage.nextDocumentExpiry];
    Log(@"Now next expiration is %@", next);
    Assert(fabs([next timeIntervalSinceDate: future]) < 1.0);
}

@end
