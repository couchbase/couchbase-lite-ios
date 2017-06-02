//
//  DatabaseTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLInternal.h"


@interface DatabaseTest : CBLTestCase
@end

@interface DummyResolver : NSObject <CBLConflictResolver>
@end

@implementation DummyResolver

- (CBLReadOnlyDocument*) resolve: (CBLConflict*)conflict {
    NSAssert(NO, @"Resolver should not have been called!");
    return nil;
}

@end


@implementation DatabaseTest


// helper method to delete database
- (void) deleteDatabase: (CBLDatabase*)db {
    NSError* error;
    NSString* path = db.path;
    Assert([[NSFileManager defaultManager] fileExistsAtPath: path]);
    Assert([db deleteDatabase:&error]);
    AssertNil(error);
    AssertFalse([[NSFileManager defaultManager] fileExistsAtPath: path]);
}


// helper method to close database
- (void) closeDatabase: (CBLDatabase*)db{
    NSError* error;
    Assert([db close:&error]);
    AssertNil(error);
}


// helper method to save document
- (CBLDocument*) generateDocument: (NSString*)docID {
    CBLDocument* doc = [self createDocument: docID];
    [doc setObject:@1 forKey:@"key"];
    
    [self saveDocument: doc];
    AssertEqual(1, (long)self.db.count);
    AssertEqual(1L, (long)doc.sequence);
    return doc;
}


// helper method to store Blob
- (void) storeBlob: (CBLDatabase*)db doc: (CBLDocument*)doc content: (NSData*)content {
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: content];
    [doc setObject: blob forKey: @"data"];
    [self saveDocument: doc];
}


// helper methods to verify getDoc
- (void) verifyGetDocument: (NSString*)docID {
    [self verifyGetDocument: docID value: 1];
}


- (void) verifyGetDocument: (NSString*)docID value: (int)value {
    [self verifyGetDocument: self.db docID: docID value: value];
}


- (void) verifyGetDocument: (CBLDatabase*)db docID: (NSString*)docID {
    [self verifyGetDocument: self.db docID: docID value: 1];
}


- (void) verifyGetDocument: (CBLDatabase*)db docID: (NSString*)docID value: (int)value {
    CBLDocument* doc = [db documentWithID: docID];
    AssertNotNil(doc);
    AssertEqualObjects(docID, doc.documentID);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects(@(value), [doc objectForKey: @"key"]);
}


// helper method to save n number of docs
- (NSArray*) createDocs: (int)n {
    NSMutableArray* docs = [NSMutableArray arrayWithCapacity: n];
    for(int i = 0; i < n; i++){
        CBLDocument* doc = [self createDocument: [NSString stringWithFormat: @"doc_%03d", i]];
        [doc setObject: @(i) forKey:@"key"];
        [self saveDocument: doc];
        [docs addObject: doc];
    }
    AssertEqual(n, (long)self.db.count);
    return docs;
}


- (void)validateDocs: (int)n {
    for (int i = 0; i < n; i++) {
        [self verifyGetDocument: [NSString stringWithFormat: @"doc_%03d", i] value: i];
    }
}


// helper method to purge doc and verify doc.
- (void) purgeDocAndVerify: (CBLDocument*)doc {
    NSError* error;
    NSString* docID = doc.documentID;
    Assert([self.db purgeDocument: doc error: &error]);
    AssertNil(error);
    AssertEqualObjects(docID, doc.documentID); // docID should be same
    AssertEqual(0L, (long)doc.sequence);       // sequence should be reset to 0
    AssertFalse(doc.isDeleted);                // delete flag should be reset to true
    AssertNil([doc objectForKey:@"key"]);      // content should be empty
}


// helper method to check error
- (void) checkError: (NSError*)error domain: (NSErrorDomain)domain code: (NSInteger)code {
    AssertNotNil(error);
    AssertEqualObjects(domain, error.domain);
    AssertEqual(code, error.code);
}


#pragma mark - DatabaseConfiguration


- (void) testCreateConfiguration {
    // Default:
    CBLDatabaseConfiguration* config1 = [[CBLDatabaseConfiguration alloc] init];
#if !TARGET_OS_IPHONE
    // MacOS needs directory as there is no bundle in mac unit test:
    config1.directory = @"/tmp";
#endif
    AssertNotNil(config1.directory);
    Assert(config1.directory.length > 0);
    AssertNil(config1.conflictResolver);
    AssertNil(config1.encryptionKey);
    AssertNil(config1.encryptionKey);
#if TARGET_OS_IPHONE
    AssertEqual(config1.fileProtection, NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication);
#endif
    
    // Default + Copy:
    CBLDatabaseConfiguration* config1a = [config1 copy];
    AssertNotNil(config1a.directory);
    Assert(config1a.directory.length > 0);
    AssertNil(config1a.conflictResolver);
    AssertNil(config1a.encryptionKey);
#if TARGET_OS_IPHONE
    AssertEqual(config1a.fileProtection, NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication);
#endif
    
    // Custom:
    DummyResolver *resolver = [DummyResolver new];
    CBLDatabaseConfiguration* config2 = [[CBLDatabaseConfiguration alloc] init];
    config2.directory = @"/tmp/mydb";
    config2.conflictResolver = resolver;
    config2.encryptionKey = @"key";
#if TARGET_OS_IPHONE
    config2.fileProtection = NSDataWritingFileProtectionComplete;
#endif
    
    AssertEqualObjects(config2.directory, @"/tmp/mydb");
    AssertEqual(config2.conflictResolver, resolver);
    AssertEqualObjects(config2.encryptionKey, @"key");
#if TARGET_OS_IPHONE
    AssertEqual(config2.fileProtection, NSDataWritingFileProtectionComplete);
#endif
    
    // Custom + Copy:
    CBLDatabaseConfiguration* config2a = [config2 copy];
    AssertEqualObjects(config2a.directory, @"/tmp/mydb");
    AssertEqual(config2a.conflictResolver, resolver);
    AssertEqualObjects(config2a.encryptionKey, @"key");
#if TARGET_OS_IPHONE
    AssertEqual(config2a.fileProtection, NSDataWritingFileProtectionComplete);
#endif
}


- (void) testGetSetConfiguration {
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
#if !TARGET_OS_IPHONE
    // MacOS needs directory as there is no bundle in mac unit test:
    config.directory = _db.config.directory;
#endif
    
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db"
                                                 config: config
                                                  error: &error];
    AssertNotNil(db.config);
    Assert(db.config != config);
    AssertEqualObjects(db.config.directory, config.directory);
    AssertEqualObjects(db.config.conflictResolver, config.conflictResolver);
    AssertEqual(db.config.encryptionKey, config.encryptionKey);
    AssertEqual(db.config.fileProtection, config.fileProtection);
    
}


- (void) testConfigurationIsCopiedWhenGetSet {
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
#if !TARGET_OS_IPHONE
    // MacOS needs directory as there is no bundle in mac unit test:
    config.directory = _db.config.directory;
#endif
    
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db"
                                                 config: config
                                                  error: &error];
    config.conflictResolver = [DummyResolver new];
    AssertNotNil(db.config);
    Assert(db.config != config);
    Assert(db.config.conflictResolver != config.conflictResolver);
}


#pragma mark - Create Database


- (void) testCreate {
    // create db with default
    NSError* error;
    CBLDatabase* db = [self openDBNamed: @"db" error: &error];
    AssertNil(error);
    AssertNotNil(db);
    AssertEqual(0, (long)db.count);
    
    // delete database
    [self deleteDatabase: db];
}


#if TARGET_OS_IPHONE
- (void) testCreateWithDefaultConfiguration {
    // create db with default configuration
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db"
                                                 config: [CBLDatabaseConfiguration new]
                                                  error: &error];
    AssertNil(error);
    AssertNotNil(db, @"Couldn't open db: %@", error);
    AssertEqualObjects(db.name, @"db");
    Assert([db.path.lastPathComponent hasSuffix: @".cblite2"]);
    AssertEqual(0, (long)db.count);
    
    // delete database
    [self deleteDatabase: db];
}
#endif


- (void) testCreateWithSpecialCharacterDBNames {
    // create db with default configuration
    NSError* error;
    CBLDatabase* db = [self openDBNamed: @"`~@#$%^&*()_+{}|\\][=-/.,<>?\":;'" error: &error];
    AssertNil(error);
    AssertNotNil(db, @"Couldn't open db: %@", db.name);
    AssertEqualObjects(db.name, @"`~@#$%^&*()_+{}|\\][=-/.,<>?\":;'");
    Assert([db.path.lastPathComponent hasSuffix: @".cblite2"]);
    AssertEqual(0, (long)db.count);
    
    // delete database
    [self deleteDatabase: db];
}


- (void) testCreateWithEmptyDBNames {
    // create db with default configuration
    NSError* error;
    CBLDatabase* db = [self openDBNamed: @"" error: &error];
    [self checkError: error domain: @"LiteCore" code: 30]; // kC4ErrorWrongFormat
    AssertNil(db, @"Should be fail to open db: %@", error);
}


- (void) testCreateWithCustomDirectory {
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    [CBLDatabase deleteDatabase: @"db" inDirectory: dir error: nil];
    AssertFalse([CBLDatabase databaseExists: @"db" inDirectory: dir]);
    
    // create db with custom directory
    NSError* error;
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = dir;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" config: config error: &error];
    AssertNil(error);
    AssertNotNil(db, @"Couldn't open db: %@", error);
    AssertEqualObjects(db.name, @"db");
    Assert([db.path.lastPathComponent hasSuffix: @".cblite2"]);
    Assert([db.path containsString: dir]);
    Assert([CBLDatabase databaseExists: @"db" inDirectory: dir]);
    AssertEqual(0, (long)db.count);

    // delete database
    [self deleteDatabase: db];
}


#pragma mark - Get Document


- (void) testGetNonExistingDocWithID {
    AssertNil([self.db documentWithID:@"non-exist"]);
}


- (void) testGetExistingDocWithID {
    // store doc
    NSString* docID = @"doc1";
    [self generateDocument: docID];
    
    // validate document by getDocument.
    [self verifyGetDocument: docID];
}


- (void) testGetExistingDocWithIDFromDifferentDBInstance {
    // store doc
    NSString* docID = @"doc1";
    [self generateDocument: docID];
    
    // open db with same db name and default option
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: [self.db name] error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    
    // get doc from other DB.
    AssertEqual(1, (long)otherDB.count);
    Assert([otherDB contains:docID]);
    
    [self verifyGetDocument: otherDB docID: docID];
    
    // close otherDB
    [self closeDatabase: otherDB];
}


- (void) testGetExistingDocWithIDInBatch {
    // save 10 docs
    [self createDocs: 10];
    
    // validate
    NSError* error;
    BOOL success = [self.db inBatch: &error do: ^{
        [self validateDocs: 10];
    }];
    Assert(success);
    AssertNil(error);
}


// TODO: crash in native layer
- (void) failingTestGetDocFromClosedDB {
    // store doc
    [self generateDocument: @"doc1"];
    
    // close db
    [self closeDatabase: self.db];
    
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    AssertNil(doc);
}


// TODO: crash in native layer
- (void) failingTestGetDocFromDeletedDB {
    // store doc
    [self generateDocument: @"doc1"];
    
    // delete db
    [self deleteDatabase: self.db];
    
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    AssertNil(doc);
}


#pragma mark - Save Document


- (void) _testSaveNewDocWithID: (NSString*)docID {
    // store doc
    [self generateDocument: docID];
    
    AssertEqual(1, (long)self.db.count);
    Assert([self.db contains: docID]);
    
    // validate doc
    [self verifyGetDocument: docID];
}


- (void) testSaveNewDocWithID {
    [self _testSaveNewDocWithID: @"doc1"];
}


- (void) testSaveNewDocWithSpecialCharactersDocID {
    [self _testSaveNewDocWithID: @"`~@#$%^&*()_+{}|\\][=-/.,<>?\":;'"];
}


- (void) testSaveDoc {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // update doc
    [doc setObject:@2 forKey:@"key"];
    [self saveDocument: doc];
    
    AssertEqual(1, (long)self.db.count);
    Assert([self.db contains: docID]);
    
    // verify
    [self verifyGetDocument: docID value: 2];
}


- (void) testSaveDocInDifferentDBInstance {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // create db with default
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: [self.db name] error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertEqual(1, (long)otherDB.count);
    
    // update doc & store it into different instance
    [doc setObject: @2 forKey: @"key"];
    AssertFalse([otherDB saveDocument: doc error: &error]);
    [self checkError: error domain: @"CouchbaseLite" code: 403]; // forbidden
    
    // close otherDB
    [self closeDatabase: otherDB];
}


- (void) testSaveDocInDifferentDB {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // create db with default
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: @"otherDB" error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertEqual(0, (long)otherDB.count);
    
    // update doc & store it into different db
    [doc setObject: @2 forKey: @"key"];
    AssertFalse([otherDB saveDocument: doc error: &error]);
    [self checkError: error domain:@"CouchbaseLite" code: 403]; // forbidden
    
    // delete otherDB
    [self deleteDatabase: otherDB];
}


- (void) testSaveSameDocTwice {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // second store
    [self saveDocument: doc];
    
    AssertEqualObjects(docID, doc.documentID);
    AssertEqual(1, (long)self.db.count);
}


- (void) testSaveInBatch {
    NSError* error;
    BOOL success = [self.db inBatch: &error do: ^{
        // save 10 docs
        [self createDocs: 10];
    }];
    Assert(success);
    AssertEqual(10, (long)self.db.count);
    
    [self validateDocs: 10];
}


// TODO: cause crash
- (void) failingTestSaveDocToClosedDB {
    // close db
    [self closeDatabase: self.db];
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject:@1 forKey:@"key"];
    
    NSError* error;
    AssertFalse([self.db saveDocument: doc error: &error]);
    [self checkError: error domain: @"CouchbaseLite" code: 403]; // forbidden
}


// TODO: cause crash
- (void) failingTestSaveDocToDeletedDB {
    // delete db
    [self deleteDatabase: self.db];
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @1 forKey: @"key"];
    
    NSError* error;
    AssertFalse([self.db saveDocument: doc error: &error]);
    [self checkError: error domain: @"CouchbaseLite" code: 403]; // forbidden
}


#pragma mark - Delete Document


- (void) testDeletePreSaveDoc {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @1 forKey: @"key"];
    
    NSError* error;
    AssertFalse([self.db deleteDocument: doc error: &error]);
    [self checkError:error domain: @"CouchbaseLite" code: 404]; // Not Found
    AssertEqual(0, (long)self.db.count);
}


- (void) testDeleteDoc {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    NSError* error;
    Assert([self.db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertEqual(0, (long)self.db.count);
    
    AssertEqualObjects(docID, doc.documentID);
    Assert(doc.isDeleted);
    AssertEqual(2, (int)doc.sequence);
    AssertNil([doc objectForKey: @"key"]);
}


- (void) testDeleteDocInDifferentDBInstance {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // create db with same name
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: [self.db name] error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    Assert([otherDB contains:docID]);
    AssertEqual(1, (long)otherDB.count);
    
    AssertFalse([otherDB deleteDocument: doc error: &error]);
    [self checkError:error domain: @"CouchbaseLite" code: 403]; // forbidden
    
    AssertEqual(1, (long)otherDB.count);
    AssertEqual(1, (long)self.db.count);
    AssertFalse(doc.isDeleted);
    
    // close otherDB
    [self closeDatabase: otherDB];
}


- (void) testDeleteDocInDifferentDB {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // create db with different name
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: @"otherDB" error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertFalse([otherDB contains: docID]);
    AssertEqual(0, (long)otherDB.count);
    
    AssertFalse([otherDB deleteDocument: doc error: &error]);
    [self checkError:error domain: @"CouchbaseLite" code: 403]; // forbidden
    
    AssertEqual(0, (long)otherDB.count);
    AssertEqual(1, (long)self.db.count);
    
    AssertFalse(doc.isDeleted);
    
    // delete otherDB
    [self deleteDatabase: otherDB];
}


- (void) testDeleteSameDocTwice {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument:docID];
    
    // first time deletion
    NSError* error;
    Assert([self.db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertEqual(0, (long)self.db.count);
    AssertNil([doc objectForKey: @"key"]);
    AssertEqual(2, (int)doc.sequence);
    Assert(doc.isDeleted);
    
    // second time deletion
    Assert([self.db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertEqual(0, (long)self.db.count);
    AssertNil([doc objectForKey: @"key"]);
    AssertEqual(3, (int)doc.sequence);
    Assert(doc.isDeleted);
}


- (void) testDeleteDocInBatch {
    // save 10 docs
    [self createDocs: 10];
    
    NSError* error;
    BOOL success = [self.db inBatch: &error do: ^{
        for(int i = 0; i < 10; i++){
            NSError* err;
            NSString* docID = [[NSString alloc] initWithFormat: @"doc_%03d", i];
            CBLDocument* doc = [self.db documentWithID: docID];
            Assert([self.db deleteDocument: doc error: &err]);
            AssertNil(err);
            AssertNil([doc objectForKey: @"key"]);
            Assert(doc.isDeleted);
            AssertEqual(9 - i, (long)self.db.count);
        }
    }];
    Assert(success);
    AssertNil(error);
    AssertEqual(0, (long)self.db.count);
}


// TODO: cause crash
- (void) failingTestDeleteDocOnClosedDB {
    // store doc
    CBLDocument* doc = [self generateDocument: @"doc1"];
    
    // close db
    [self closeDatabase: self.db];
    
    // delete doc from db.
    NSError* error;
    AssertFalse([self.db deleteDocument: doc error: &error]);
    [self checkError: error domain: @"CouchbaseLite" code: 403]; // forbidden
}


// TODO: cause crash
- (void) failingTestDeleteDocOnDeletedDB {
    // store doc
    CBLDocument* doc = [self generateDocument:@"doc1"];
    
    // delete db
    [self deleteDatabase: self.db];
    
    // delete doc from db.
    NSError* error;
    AssertFalse([self.db deleteDocument: doc error: &error]);
    [self checkError: error domain: @"CouchbaseLite" code: 403]; // forbidden
}


#pragma mark - Purge Document


- (void) testPurgePreSaveDoc {
    CBLDocument* doc = [self createDocument: @"doc1"];
    
    NSError* error;
    AssertFalse([self.db purgeDocument: doc error: &error]);
    [self checkError: error domain: @"CouchbaseLite" code: 404];
    AssertEqual(0, (long)self.db.count);
}


// TODO: Check whether purge operation incrases the seq number or not
- (void) testPurgeDoc {
    // Store doc:
    CBLDocument* doc = [self generateDocument: @"doc1"];
    
    // Purge Doc:
    [self purgeDocAndVerify: doc];
    AssertEqual(0, (long)self.db.count);
    
    // Save to check sequence number -> 2
    [self saveDocument: doc];
    AssertEqual(2L, (long)doc.sequence);
}


- (void) testPurgeDocInDifferentDBInstance {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // create db instance with same name
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: [self.db name] error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    Assert([otherDB contains:docID]);
    AssertEqual(1, (long)otherDB.count);
    
    // purge document against other db instance
    AssertFalse([otherDB purgeDocument: doc error: &error]);
    [self checkError: error domain: @"CouchbaseLite" code: 403]; // forbidden
    AssertEqual(1, (long)otherDB.count);
    AssertEqual(1, (long)self.db.count);
    AssertFalse(doc.isDeleted);
    
    // close otherDB
    [self closeDatabase: otherDB];
}


- (void) testPurgeDocInDifferentDB {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // create db with different name
    NSError* error;
    CBLDatabase* otherDB =  [self openDBNamed: @"otherDB" error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertFalse([otherDB contains: docID]);
    AssertEqual(0, (long)otherDB.count);
    
    // purge document against other db
    AssertFalse([otherDB purgeDocument: doc error: &error]);
    [self checkError: error domain: @"CouchbaseLite" code: 403]; // forbidden
    
    AssertEqual(0, (long)otherDB.count);
    AssertEqual(1, (long)self.db.count);
    AssertFalse(doc.isDeleted);
    
    [self deleteDatabase: otherDB];
}


- (void) testPurgeSameDocTwice {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // get document for second purge
    CBLDocument* doc1 = [self.db documentWithID: docID];
    AssertNotNil(doc1);
    
    // Purge Doc first time
    [self purgeDocAndVerify: doc];
    AssertEqual(0, (long)self.db.count);
    
    // Purge Doc second time
    [self purgeDocAndVerify: doc1];
    AssertEqual(0, (long)self.db.count);
}


- (void) testPurgeDocInBatch {
    // save 10 docs
    [self createDocs: 10];

    NSError* error;
    BOOL success = [self.db inBatch: &error do: ^{
        for(int i = 0; i < 10; i++){
            //NSError* err;
            NSString* docID = [[NSString alloc] initWithFormat: @"doc_%03d", i];
            CBLDocument* doc = [self.db documentWithID: docID];
            [self purgeDocAndVerify: doc];
            AssertEqual(9 - i, (long)self.db.count);
        }
    }];
    Assert(success);
    AssertNil(error);
    AssertEqual(0, (long)self.db.count);
}


// TODO: cause crash
- (void) failingTestPurgeDocOnClosedDB {
    // store doc
    CBLDocument* doc = [self generateDocument: @"doc1"];
    
    // close db
    [self closeDatabase:self.db];
    
    // purge doc
    NSError* error;
    AssertFalse([self.db purgeDocument: doc error: &error]);
    [self checkError: error domain: @"CouchbaseLite" code: 403]; // forbidden
}


// TODO: cause crash
- (void) failingTestPurgeDocOnDeletedDB {
    // store doc
    CBLDocument* doc = [self generateDocument: @"doc1"];
   
    // delete db
    [self deleteDatabase: self.db];
    
    // purge doc
    NSError* error;
    AssertFalse([self.db purgeDocument: doc error: &error]);
    [self checkError: error domain: @"CouchbaseLite" code: 403]; // forbidden
}


#pragma mark - Close Database


- (void) testClose {
    // close db
    [self closeDatabase: self.db];
}


- (void) testCloseTwice {
    // close db twice
    [self closeDatabase: self.db];
    [self closeDatabase: self.db];
}


- (void) testCloseThenAccessDoc {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // close db
    [self closeDatabase: self.db];
    
    // content should be accessible & modifiable without error
    AssertEqualObjects(docID, doc.documentID);
    AssertEqualObjects(@(1), [doc objectForKey: @"key"]);
    [doc setObject:@(2) forKey: @"key"];
    [doc setObject: @"value" forKey: @"key1"];
}


- (void)testCloseThenAccessBlob {
    // store doc with blob
    CBLDocument* doc = [self generateDocument: @"doc1"];
    [self storeBlob: self.db doc: doc content: [@"12345" dataUsingEncoding: NSUTF8StringEncoding]];
    
    // clsoe db
    [self closeDatabase: self.db];
    
    // content should be accessible & modifiable without error
    Assert([[doc objectForKey: @"data"] isKindOfClass: [CBLBlob class]]);
    CBLBlob* blob = [doc objectForKey: @"data"];
    AssertEqual(blob.length, 5ull);
    AssertNil(blob.content);
}


- (void) testCloseThenGetDatabaseName {
    // clsoe db
    [self closeDatabase: self.db];
    AssertEqualObjects(@"testdb", self.db.name);
}


- (void) testCloseThenGetDatabasePath {
    // clsoe db
    [self closeDatabase:self.db];
    
    AssertNil(self.db.path);
}


- (void) testCloseThenCallInBatch {
    NSError* error;
    BOOL sucess = [self.db inBatch: &error do: ^{
        NSError* err;
        [self.db close: &err];
        // 26 -> kC4ErrorTransactionNotClosed
        [self checkError: err domain: @"LiteCore" code: 26];
    }];
    Assert(sucess);
    AssertNil(error);
}


- (void) falingTestCloseThenDeleteDatabase {
    [self closeDatabase: self.db];
    [self deleteDatabase: self.db];
}


#pragma mark - Delete Database


- (void) testDelete {
    // delete db
    [self deleteDatabase: self.db];
}


- (void) failingTestDeleteTwice {
    // delete db twice
    [self deleteDatabase: self.db];
    [self deleteDatabase: self.db];
}


- (void) testDeleteThenAccessDoc {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // delete db
    [self deleteDatabase: self.db];
    
    // content should be accessible & modifiable without error
    AssertEqualObjects(docID, doc.documentID);
    AssertEqualObjects(@(1), [doc objectForKey: @"key"]);
    [doc setObject: @(2) forKey: @"key"];
    [doc setObject: @"value" forKey: @"key1"];
}


- (void) testDeleteThenAccessBlob {
    // store doc with blob
    CBLDocument* doc = [self generateDocument: @"doc1"];
    [self storeBlob: self.db doc: doc content: [@"12345" dataUsingEncoding: NSUTF8StringEncoding]];
    
    // delete db
    [self deleteDatabase: self.db];
    
    // content should be accessible & modifiable without error
    Assert([[doc objectForKey: @"data"] isKindOfClass: [CBLBlob class]]);
    CBLBlob* blob = [doc objectForKey: @"data"];
    AssertEqual(blob.length, 5ull);
    AssertNil(blob.content);
    // TODO: TO BE CLARIFIED: Instead of returning nil, should it return Forbidden error?
}


- (void) testDeleteThenGetDatabaseName {
    // delete db
    [self deleteDatabase: self.db];
    AssertEqualObjects(@"testdb", self.db.name);
}


- (void) testDeleteThenGetDatabasePath{
    // delete db
    [self deleteDatabase: self.db];
    AssertNil(self.db.path);
}


- (void) testDeleteThenCallInBatch {
    NSError* error;
    BOOL sucess = [self.db inBatch: &error do:^{
        NSError* err;
        [self.db deleteDatabase: &err];
        // 26 -> kC4ErrorTransactionNotClosed: Function cannot be called while in a transaction
        [self checkError: err domain: @"LiteCore" code: 26];
    }];
    Assert(sucess);
    AssertNil(error);
}


- (void) testDeleteDBOpendByOtherInstance {
    // open db with same db name and default option
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: [self.db name] error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    
    // delete db
    AssertFalse([self.db deleteDatabase: &error]);
    // 24 -> kC4ErrorBusy: Database is busy/locked
    [self checkError: error domain: @"LiteCore" code: 24];
}


#pragma mark - Delate Database (static)


#if TARGET_OS_IPHONE
- (void) testDeleteWithDefaultDirDB {
    // open db with default dir
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" error: &error];
    AssertNil(error);
    AssertNotNil(db);
    
    // close db before delete
    [self closeDatabase: db];
    
    // delete db with nil directory
    Assert([CBLDatabase deleteDatabase: @"db" inDirectory: nil error: &error]);
    AssertNil(error);
    AssertFalse([[NSFileManager defaultManager] fileExistsAtPath: db.path]);
}
#endif


#if TARGET_OS_IPHONE
- (void) testDeleteOpeningDBWithDefaultDir {
    // open db with default dir
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" error: &error];
    AssertNil(error);
    AssertNotNil(db);
    
    // delete db with nil directory
    AssertFalse([CBLDatabase deleteDatabase: @"db" inDirectory: nil error: &error]);
    // 24 -> kC4ErrorBusy: Database is busy/locked
    [self checkError: error domain: @"LiteCore" code: 24];
}
#endif


- (void) testDeleteByStaticMethod {
    // create db with custom directory
    NSError* error;
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = dir;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" config: config error: &error];
    AssertNotNil(db);
    AssertNil(error);
    
    NSString* path = db.path;
    
    // close db before delete
    [self closeDatabase: db];
    
    Assert([CBLDatabase deleteDatabase: @"db" inDirectory: dir error:&error]);
    AssertNil(error);
    AssertFalse([[NSFileManager defaultManager] fileExistsAtPath: path]);
}


- (void) testDeleteOpeningDBByStaticMethod {
    // create db with custom directory
    NSError* error;
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = dir;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" config: config error: &error];
    AssertNotNil(db);
    AssertNil(error);
    
    AssertFalse([CBLDatabase deleteDatabase: @"db" inDirectory: dir error: &error]);
    // 24 -> kC4ErrorBusy: Database is busy/locked
    [self checkError: error domain: @"LiteCore" code: 24];
}


#if TARGET_OS_IPHONE
- (void) testDeleteNonExistingDBWithDefaultDir {
    // Expectation: No operation
    NSError* error;
    Assert([CBLDatabase deleteDatabase: @"notexistdb" inDirectory: nil error: &error]);
    AssertNil(error);
}
#endif


- (void) testDeleteNonExistingDB {
    // Expectation: No operation
    NSError* error;
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    Assert([CBLDatabase deleteDatabase: @"notexistdb" inDirectory: dir error: &error]);
    AssertNil(error);
}


#pragma mark - Database Existing


#if TARGET_OS_IPHONE
- (void) failingTestDatabaseExistsWithDefaultDir {
    AssertFalse([CBLDatabase databaseExists: @"db" inDirectory: nil]);
    
    // open db with default dir
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" error: &error];
    Assert([CBLDatabase databaseExists: @"db" inDirectory: nil]);
    
    // close db
    [self closeDatabase: db];
    
    Assert([CBLDatabase databaseExists: @"db" inDirectory: nil]);
    
    // delete db
    [self deleteDatabase: db];
    
    AssertFalse([CBLDatabase databaseExists: @"db" inDirectory: nil]);

}
#endif


- (void) testDatabaseExistsWithDir {
    NSError* error;
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    
    AssertFalse([CBLDatabase databaseExists:@"db" inDirectory:dir]);
    
    // create db with custom directory
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = dir;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" config: config error: &error];
    AssertNotNil(db);
    AssertNil(error);
    NSString* path = db.path;
    
    Assert([CBLDatabase databaseExists: @"db" inDirectory: dir]);
    
    // close db
    [self closeDatabase: db];
    
    Assert([CBLDatabase databaseExists: @"db" inDirectory: dir]);
    
    // delete db
    Assert([CBLDatabase deleteDatabase: @"db" inDirectory: dir error: &error]);
    AssertNil(error);
    AssertFalse([[NSFileManager defaultManager] fileExistsAtPath: path]);
    
    AssertFalse([CBLDatabase databaseExists: @"db" inDirectory: dir]);
}


#if TARGET_OS_IPHONE
- (void) testDatabaseExistsAgainstNonExistDBWithDefaultDir {
    AssertFalse([CBLDatabase databaseExists: @"nonexist" inDirectory: nil]);
}
#endif


- (void) testDatabaseExistsAgainstNonExistDB {
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    AssertFalse([CBLDatabase databaseExists: @"nonexist" inDirectory: dir]);
}


- (void) testCompact {
    NSArray* docs = [self createDocs: 20];
    
    // Update each doc 25 times:
    NSError* error;
    [_db inBatch: &error do: ^{
        for (CBLDocument* doc in docs) {
            for (NSUInteger i = 0; i < 25; i++) {
                [doc setObject: @(i) forKey: @"number"];
                [self saveDocument: doc];
            }
        }
    }];
    
    // Add each doc with a blob object:
    for (CBLDocument* doc in docs) {
        NSData* content = [doc.documentID dataUsingEncoding: NSUTF8StringEncoding];
        CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
        [doc setObject: blob forKey: @"blob"];
        [self saveDocument: doc];
    }
    
    AssertEqual(_db.count, 20u);
    
    NSString* attsDir = [_db.path stringByAppendingPathComponent:@"Attachments"];
    NSArray* atts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: attsDir error: nil];
    AssertEqual(atts.count, 20u);
    
    // Compact:
    Assert([_db compact: &error], @"Error when compacting the database");
    
    // Delete all docs:
    for (CBLDocument* doc in docs) {
        Assert([_db deleteDocument: doc error: &error], @"Error when deleting doc: %@", error);
        Assert(doc.isDeleted);
    }
    AssertEqual(_db.count, 0u);
    
    // Compact:
    Assert([_db compact: &error], @"Error when compacting the database: %@", error);
    
    atts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: attsDir error: nil];
    AssertEqual(atts.count, 0u);
}


@end
