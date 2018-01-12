//
//  DatabaseTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLDatabase+Internal.h"


@interface DatabaseTest : CBLTestCase
@end

@interface DummyResolver : NSObject <CBLConflictResolver>
@end

@implementation DummyResolver

- (CBLDocument*) resolve: (CBLConflict*)conflict {
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
    Assert([db delete: &error]);
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
    CBLMutableDocument* doc = [self createDocument: docID];
    [doc setValue: @1 forKey:@"key"];
    
    CBLDocument* saveDoc = [self saveDocument: doc];
    AssertEqual(1, (long)self.db.count);
    AssertEqual(1L, (long)saveDoc.sequence);
    return saveDoc;
}


// helper method to store Blob
- (CBLDocument*) storeBlob: (CBLDatabase*)db
                       doc: (CBLMutableDocument*)doc
                   content: (NSData*)content
{
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: content];
    [doc setValue: blob forKey: @"data"];
    return [self saveDocument: doc];
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
    AssertEqualObjects(docID, doc.id);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects(@(value), [doc valueForKey: @"key"]);
}


// helper method to save n number of docs
- (NSArray*) createDocs: (int)n {
    NSMutableArray* docs = [NSMutableArray arrayWithCapacity: n];
    for(int i = 0; i < n; i++){
        CBLMutableDocument* doc = [self createDocument: [NSString stringWithFormat: @"doc_%03d", i]];
        [doc setValue: @(i) forKey:@"key"];
        [docs addObject: [self saveDocument: doc]];
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
    Assert([self.db purgeDocument: doc error: &error]);
    AssertNil(error);
    AssertNil([self.db documentWithID: doc.id]);
}


#pragma mark - DatabaseConfiguration


- (void) testCreateConfiguration {
    // Default:
    CBLDatabaseConfiguration* config1 = [[CBLDatabaseConfiguration alloc] init];
    AssertNotNil(config1.directory);
    Assert(config1.directory.length > 0);
    AssertNotNil(config1.conflictResolver);
    AssertNil(config1.encryptionKey);
    AssertNil(config1.encryptionKey);
#if TARGET_OS_IPHONE
    AssertEqual(config1.fileProtection, 0);
#endif
    
    // Custom:
    CBLEncryptionKey* key = [[CBLEncryptionKey alloc] initWithPassword: @"key"];
    DummyResolver *resolver = [DummyResolver new];
    CBLDatabaseConfiguration* config2 =
        [[CBLDatabaseConfiguration alloc] initWithBlock:
            ^(CBLDatabaseConfigurationBuilder *builder) {
                builder.directory = @"/tmp/mydb";
                builder.conflictResolver = resolver;
                builder.encryptionKey = key;
#if TARGET_OS_IPHONE
                builder.fileProtection = NSDataWritingFileProtectionComplete;
#endif
            }];
    
    AssertEqualObjects(config2.directory, @"/tmp/mydb");
    AssertEqual(config2.conflictResolver, resolver);
    AssertEqualObjects(config2.encryptionKey, key);
#if TARGET_OS_IPHONE
    AssertEqual(config2.fileProtection, NSDataWritingFileProtectionComplete);
#endif
}


- (void) testGetSetConfiguration {
    CBLDatabaseConfiguration* config =
        [[CBLDatabaseConfiguration alloc] initWithBlock:
            ^(CBLDatabaseConfigurationBuilder * _Nonnull builder) {
#if !TARGET_OS_IPHONE
                // MacOS needs directory as there is no bundle in mac unit test:
                builder.directory = _db.config.directory;
#endif
    }];

    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db"
                                                 config: config
                                                  error: &error];
    AssertNotNil(db.config);
    Assert(db.config == config);
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
    [self expectError: @"LiteCore" code: 30 in: ^BOOL(NSError** error) {
        return [self openDBNamed: @"" error: error] != nil;
    }];
}


- (void) testCreateWithCustomDirectory {
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    [CBLDatabase deleteDatabase: @"db" inDirectory: dir error: nil];
    AssertFalse([CBLDatabase databaseExists: @"db" inDirectory: dir]);
    
    // create db with custom directory
    NSError* error;
    CBLDatabaseConfiguration* config =
        [[CBLDatabaseConfiguration alloc] initWithBlock:
            ^(CBLDatabaseConfigurationBuilder *builder) {
                builder.directory = dir;
            }];
    
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
    AssertNotNil([otherDB documentWithID: docID]);
    
    [self verifyGetDocument: otherDB docID: docID];
    
    // close otherDB
    [self closeDatabase: otherDB];
}


- (void) testGetExistingDocWithIDInBatch {
    // save 10 docs
    [self createDocs: 10];
    
    // validate
    NSError* error;
    BOOL success = [self.db inBatch: &error usingBlock: ^{
        [self validateDocs: 10];
    }];
    Assert(success);
    AssertNil(error);
}


- (void) testGetDocFromClosedDB {
    // store doc
    [self generateDocument: @"doc1"];
    
    // close db
    [self closeDatabase: self.db];
    
    // Get doc
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db documentWithID: @"doc1"];
    }];
}


- (void) testGetDocFromDeletedDB {
    // store doc
    [self generateDocument: @"doc1"];
    
    // delete db
    [self deleteDatabase: self.db];
    
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db documentWithID: @"doc1"];
    }];
}


#pragma mark - Save Document


- (void) testSaveNewDocWithID {
    NSString* docID = @"doc1";
    
    [self generateDocument: docID];
    
    AssertEqual(1, (long)self.db.count);
    AssertNotNil([self.db documentWithID: docID]);
    
    [self verifyGetDocument: docID];
}


- (void) testSaveNewDocWithSpecialCharactersDocID {
    NSString* docID = @"`~@#$%^&*()_+{}|\\][=-/.,<>?\":;'";
    
    [self generateDocument: docID];
    
    AssertEqual(1, (long)self.db.count);
    AssertNotNil([self.db documentWithID: docID]);
    
    [self verifyGetDocument: docID];
}


- (void) testSaveDoc {
    // store doc
    NSString* docID = @"doc1";
    CBLMutableDocument* doc = [[self generateDocument: docID] toMutable];
    
    // update doc
    [doc setValue: @2 forKey:@"key"];
    [self saveDocument: doc];
    
    AssertEqual(1, (long)self.db.count);
    AssertNotNil([self.db documentWithID: docID]);
    
    // verify
    [self verifyGetDocument: docID value: 2];
}


- (void) testSaveDocInDifferentDBInstance {
    // store doc
    NSString* docID = @"doc1";
    CBLMutableDocument* doc = [[self generateDocument: docID] toMutable];
    
    // create db with default
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: [self.db name] error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertEqual(1, (long)otherDB.count);
    
    // update doc & store it into different instance
    [doc setValue: @2 forKey: @"key"];
    [self expectError: @"CouchbaseLite" code: 403 in: ^BOOL(NSError** error2) {
        return [otherDB saveDocument: doc error: error2] != nil;
    }]; // forbidden
    
    // close otherDB
    [self closeDatabase: otherDB];
}


- (void) testSaveDocInDifferentDB {
    // store doc
    NSString* docID = @"doc1";
    CBLMutableDocument* doc = [[self generateDocument: docID] toMutable];
    
    // create db with default
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: @"otherDB" error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertEqual(0, (long)otherDB.count);
    
    // update doc & store it into different db
    [doc setValue: @2 forKey: @"key"];
    [self expectError: @"CouchbaseLite" code: 403 in: ^BOOL(NSError** error2) {
        return [otherDB saveDocument: doc error: error2] != nil;
    }]; // forbidden
    
    // delete otherDB
    [self deleteDatabase: otherDB];
}


- (void) testSaveSameDocTwice {
    // store doc
    NSString* docID = @"doc1";
    CBLMutableDocument* doc = [[self generateDocument: docID] toMutable];
    
    // second store
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    AssertEqualObjects(docID, savedDoc.id);
    AssertEqual(1, (long)self.db.count);
}


- (void) testSaveInBatch {
    NSError* error;
    BOOL success = [self.db inBatch: &error usingBlock: ^{
        // save 10 docs
        [self createDocs: 10];
    }];
    Assert(success);
    AssertEqual(10, (long)self.db.count);
    
    [self validateDocs: 10];
}


- (void) testSaveDocToClosedDB {
    [self closeDatabase: self.db];
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @1 forKey:@"key"];
    
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db saveDocument: doc error: nil];
    }];
}


- (void) testSaveDocToDeletedDB {
    // delete db
    [self deleteDatabase: self.db];
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @1 forKey: @"key"];
    
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db saveDocument: doc error: nil];
    }];
}


#pragma mark - Delete Document


- (void) testDeletePreSaveDoc {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @1 forKey: @"key"];
    
    [self expectError: @"CouchbaseLite" code: 405 in: ^BOOL(NSError** error) {
        return [self.db deleteDocument: doc error: error];
    }];
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
    AssertNil([self.db documentWithID: docID]);
}


- (void) testDeleteSameDocTwice {
    // Store doc:
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument:docID];
    
    // First time deletion:
    NSError* error;
    Assert([self.db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertEqual(0, (long)self.db.count);
    AssertNil([self.db documentWithID: docID]);
    
    // Second time deletion:
    Assert([self.db deleteDocument: doc error: &error]);
    AssertNil([self.db documentWithID: docID]);
}


- (void) testDeleteNonExistingDoc {
    // Store doc:
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument:docID];
    
    // Purge doc:
    NSError* error;
    Assert([self.db purgeDocument: doc error: &error]);
    AssertEqual(0, (long)self.db.count);
    AssertNil([self.db documentWithID: docID]);
    
    // Delete doc
    Assert([self.db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertEqual(0, (long)self.db.count);
    AssertNil([self.db documentWithID: docID]);
}

- (void) testDeleteDocInBatch {
    // save 10 docs
    [self createDocs: 10];
    
    NSError* error;
    BOOL success = [self.db inBatch: &error usingBlock: ^{
        for(int i = 0; i < 10; i++){
            NSError* err;
            NSString* docID = [[NSString alloc] initWithFormat: @"doc_%03d", i];
            CBLDocument* doc = [self.db documentWithID: docID];
            Assert([self.db deleteDocument: doc error: &err]);
            AssertNil(err);
            AssertEqual(9 - i, (long)self.db.count);
        }
    }];
    Assert(success);
    AssertNil(error);
    AssertEqual(0, (long)self.db.count);
}


- (void) testDeleteDocOnClosedDB {
    // store doc
    CBLDocument* doc = [self generateDocument: @"doc1"];
    
    // close db
    [self closeDatabase: self.db];
    
    // delete doc from db.
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db deleteDocument: doc error: nil];
    }];
}


- (void) testDeleteDocOnDeletedDB {
    // store doc
    CBLDocument* doc = [self generateDocument:@"doc1"];
    
    // delete db
    [self deleteDatabase: self.db];
    
    // delete doc from db.
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db deleteDocument: doc error: nil];
    }];
}


#pragma mark - Purge Document


- (void) testPurgePreSaveDoc {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    
    [self expectError: @"CouchbaseLite" code: 405 in: ^BOOL(NSError** error) {
        return [self.db purgeDocument: doc error: error];
    }];
    AssertEqual(0, (long)self.db.count);
}


- (void) testPurgeDoc {
    // Store doc:
    CBLDocument* doc = [self generateDocument: @"doc1"];
    
    // Purge Doc:
    [self purgeDocAndVerify: doc];
    AssertEqual(0, (long)self.db.count);
}


- (void) testPurgeDocInDifferentDBInstance {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // create db instance with same name
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: self.db.name error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertNotNil([otherDB documentWithID: docID]);
    AssertEqual(1, (long)otherDB.count);
    
    // purge document against other db instance
    [self expectError: @"CouchbaseLite" code: 403 in: ^BOOL(NSError** error2) {
        return [otherDB purgeDocument: doc error: error2];
    }]; // forbidden
    AssertEqual(1, (long)otherDB.count);
    AssertEqual(1, (long)self.db.count);
    
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
    AssertNil([otherDB documentWithID: docID]);
    AssertEqual(0, (long)otherDB.count);
    
    // purge document against other db
    [self expectError: @"CouchbaseLite" code: 403 in: ^BOOL(NSError** error2) {
        return [otherDB purgeDocument: doc error: error2];
    }]; // forbidden
    
    AssertEqual(0, (long)otherDB.count);
    AssertEqual(1, (long)self.db.count);
    
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
    [self purgeDocAndVerify: doc];
    AssertEqual(0, (long)self.db.count);
}


- (void) testPurgeDocInBatch {
    // save 10 docs
    [self createDocs: 10];

    NSError* error;
    BOOL success = [self.db inBatch: &error usingBlock: ^{
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


- (void) testPurgeDocOnClosedDB {
    // store doc
    CBLDocument* doc = [self generateDocument: @"doc1"];
    
    // close db
    [self closeDatabase: self.db];
    
    // purge doc
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db purgeDocument: doc error: nil];
    }];
}


- (void) testPurgeDocOnDeletedDB {
    // store doc
    CBLDocument* doc = [self generateDocument: @"doc1"];
   
    // delete db
    [self deleteDatabase: self.db];
    
    // purge doc
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db purgeDocument: doc error: nil];
    }];
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
    AssertEqualObjects(docID, doc.id);
    AssertEqualObjects(@(1), [doc valueForKey: @"key"]);
    
    CBLMutableDocument* updatedDoc = [doc toMutable];
    [updatedDoc setValue: @(2) forKey: @"key"];
    [updatedDoc setValue: @"value" forKey: @"key1"];
}


- (void)testCloseThenAccessBlob {
    // store doc with blob
    CBLMutableDocument* doc = [[self generateDocument: @"doc1"] toMutable];
    CBLDocument* savedDoc = [self storeBlob: self.db
                                        doc: doc
                                    content: [@"12345" dataUsingEncoding: NSUTF8StringEncoding]];
    
    // clsoe db
    [self closeDatabase: self.db];
    
    // content should be accessible & modifiable without error
    Assert([[savedDoc valueForKey: @"data"] isKindOfClass: [CBLBlob class]]);
    CBLBlob* blob = [savedDoc valueForKey: @"data"];
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
    BOOL success = [self.db inBatch: &error usingBlock: ^{
        [self expectError: @"LiteCore" code: 26 in: ^BOOL(NSError** error2) {
            return [self.db close: error2];
        }];
        // 26 -> kC4ErrorTransactionNotClosed
    }];
    Assert(success);
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


- (void) testDeleteTwice {
    NSError* error;
    Assert([self.db delete: &error]);
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db delete: nil];
    }];
}


- (void) testDeleteThenAccessDoc {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocument: docID];
    
    // delete db
    [self deleteDatabase: self.db];
    
    // content should be accessible & modifiable without error
    AssertEqualObjects(docID, doc.id);
    AssertEqualObjects(@(1), [doc valueForKey: @"key"]);
    
    CBLMutableDocument* updatedDoc = [doc toMutable];
    [updatedDoc setValue: @(2) forKey: @"key"];
    [updatedDoc setValue: @"value" forKey: @"key1"];
}


- (void) testDeleteThenAccessBlob {
    // store doc with blob
    CBLMutableDocument* doc = [[self generateDocument: @"doc1"] toMutable];
    CBLDocument* savedDoc = [self storeBlob: self.db
                                        doc: doc
                                    content: [@"12345" dataUsingEncoding: NSUTF8StringEncoding]];
    
    // delete db
    [self deleteDatabase: self.db];
    
    // content should be accessible & modifiable without error
    Assert([[savedDoc valueForKey: @"data"] isKindOfClass: [CBLBlob class]]);
    CBLBlob* blob = [savedDoc valueForKey: @"data"];
    AssertEqual(blob.length, 5ull);
    AssertNil(blob.content);
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
    BOOL sucess = [self.db inBatch: &error usingBlock:^{
        [self expectError: @"LiteCore" code: 26 in: ^BOOL(NSError** error2) {
            return [self.db delete: error2];
        }];
        // 26 -> kC4ErrorTransactionNotClosed: Function cannot be called while in a transaction
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
    [self expectError: @"LiteCore" code: 24 in: ^BOOL(NSError** error2) {
        return [self.db delete: error2];
    }];
    // 24 -> kC4ErrorBusy: Database is busy/locked
}


#pragma mark - Delate Database (static)


#if TARGET_OS_IPHONE
- (void) testDeleteWithDefaultDirDB {
    // open db with default dir
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" error: &error];
    AssertNil(error);
    AssertNotNil(db);
    
    // Get path
    NSString* path = db.path;
    AssertNotNil(path);
    
    // close db before delete
    [self closeDatabase: db];
    
    // delete db with nil directory
    Assert([CBLDatabase deleteDatabase: @"db" inDirectory: nil error: &error]);
    AssertNil(error);
    AssertFalse([[NSFileManager defaultManager] fileExistsAtPath: path]);
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
    // 24 -> kC4ErrorBusy: Database is busy/locked
    [self expectError: @"LiteCore" code: 24 in: ^BOOL(NSError** error2) {
        return [CBLDatabase deleteDatabase: @"db" inDirectory: nil error: error2];
    }];
}
#endif


- (void) testDeleteByStaticMethod {
    // create db with custom directory
    NSError* error;
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    
    CBLDatabaseConfiguration* config =
        [[CBLDatabaseConfiguration alloc] initWithBlock:
            ^(CBLDatabaseConfigurationBuilder *builder) {
                builder.directory = dir;
            }];
    
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
    CBLDatabaseConfiguration* config =
        [[CBLDatabaseConfiguration alloc] initWithBlock:
            ^(CBLDatabaseConfigurationBuilder *builder) {
                builder.directory = dir;
            }];
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" config: config error: &error];
    AssertNotNil(db);
    AssertNil(error);
    
    [self expectError: @"LiteCore" code: 24 in: ^BOOL(NSError** error2) {
        return [CBLDatabase deleteDatabase: @"db" inDirectory: dir error: error2];
    }];
    // 24 -> kC4ErrorBusy: Database is busy/locked
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
- (void) testDatabaseExistsWithDefaultDir {
    AssertFalse([CBLDatabase databaseExists: @"db" inDirectory: nil]);
    
    // open db with default dir
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" error: &error];
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
    CBLDatabaseConfiguration* config =
        [[CBLDatabaseConfiguration alloc] initWithBlock:
            ^(CBLDatabaseConfigurationBuilder *builder) {
                builder.directory = dir;
            }];
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
    [_db inBatch: &error usingBlock: ^{
        for (CBLDocument* doc in docs) {
            for (NSUInteger i = 0; i < 25; i++) {
                CBLMutableDocument* mDoc = [doc toMutable];
                [mDoc setValue: @(i) forKey: @"number"];
                [self saveDocument: mDoc];
            }
        }
    }];
    
    // Add each doc with a blob object:
    for (CBLDocument* doc in docs) {
        CBLMutableDocument* mDoc = [[_db documentWithID: doc.id] toMutable];
        NSData* content = [doc.id dataUsingEncoding: NSUTF8StringEncoding];
        CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
        [mDoc setValue: blob forKey: @"blob"];
        [self saveDocument: mDoc];
    }
    
    AssertEqual(_db.count, 20u);
    
    NSString* attsDir = [_db.path stringByAppendingPathComponent:@"Attachments"];
    NSArray* atts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: attsDir error: nil];
    AssertEqual(atts.count, 20u);
    
    // Compact:
    Assert([_db compact: &error], @"Error when compacting the database");
    
    // Delete all docs:
    for (CBLDocument* doc in docs) {
        CBLDocument* savedDoc = [_db documentWithID: doc.id];
        Assert([_db deleteDocument: savedDoc error: &error], @"Error when deleting doc: %@", error);
        AssertNil([_db documentWithID: doc.id]);
    }
    AssertEqual(_db.count, 0u);
    
    // Compact:
    Assert([_db compact: &error], @"Error when compacting the database: %@", error);
    
    atts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: attsDir error: nil];
    AssertEqual(atts.count, 0u);
}


- (void) testCopy {
    for (NSUInteger i = 0; i < 10; i++) {
        NSString* docID = [NSString stringWithFormat: @"doc%lu", (unsigned long)i];
        CBLMutableDocument* doc = [self createDocument: docID];
        [doc setValue: docID forKey: @"name"];
        
        NSData* data = [docID dataUsingEncoding: NSUTF8StringEncoding];
        CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: data];
        [doc setValue: blob forKey: @"data"];
        
        [self saveDocument: doc];
    }
    
    NSString* dbName = @"nudb";
    CBLDatabaseConfiguration* config = _db.config;
    NSString* dir = config.directory;
    
    // Make sure no an existing database at the new location:
    Assert([CBLDatabase deleteDatabase: dbName inDirectory: dir error: nil]);
    
    // Copy:
    NSError* error;
    Assert([CBLDatabase copyFromPath: _db.path toDatabase: dbName withConfig: config error: &error],
           @"Error when copying the database: %@", error);
    
    // Verify:
    Assert([CBLDatabase databaseExists: dbName inDirectory: dir]);
    CBLDatabase* nudb = [[CBLDatabase alloc] initWithName: dbName config: config  error: &error];
    Assert(nudb, @"Cannot open the new database: %@", error);
    AssertEqual(nudb.count, 10u);
    
    CBLQueryExpression* DOCID = [CBLQueryMeta id];
    CBLQuerySelectResult* S_DOCID = [CBLQuerySelectResult expression: DOCID];
    CBLQuery* query = [CBLQuery select: @[S_DOCID]
                                  from: [CBLQueryDataSource database: nudb]];
    CBLQueryResultSet* rs = [query execute: &error];
    
    for (CBLQueryResult* r in rs) {
        NSString* docID = [r stringAtIndex: 0];
        Assert(docID);
        
        CBLDocument* doc = [nudb documentWithID: docID];
        Assert(doc);
        AssertEqualObjects([doc stringForKey:@"name"], docID);
        
        CBLBlob* blob = [doc blobForKey: @"data"];
        Assert(blob);
        
        NSString* data = [[NSString alloc] initWithData: blob.content encoding: NSUTF8StringEncoding];
        AssertEqualObjects(data, docID);
    }
    
    // Clean up:
    Assert([nudb close: nil]);
    Assert([CBLDatabase deleteDatabase: dbName inDirectory: dir error: nil]);
}


- (void) testCreateIndex {
    // Precheck:
    Assert(self.db.indexes);
    AssertEqual(self.db.indexes.count, 0u);
    
    // Create value index:
    CBLQueryExpression* fName = [CBLQueryExpression property: @"firstName"];
    CBLQueryExpression* lName = [CBLQueryExpression property: @"lastName"];
    
    CBLValueIndexItem* fNameItem = [CBLValueIndexItem expression: fName];
    CBLValueIndexItem* lNameItem = [CBLValueIndexItem expression: lName];
    
    NSError* error;
    
    CBLIndex* index1 = [CBLIndex valueIndexWithItems: @[fNameItem, lNameItem]];
    Assert([self.db createIndex: index1 withName: @"index1" error: &error],
           @"Error when creating value index: %@", error);
    
    // Create FTS index:
    CBLFullTextIndexItem* detailItem = [CBLFullTextIndexItem property: @"detail"];
    CBLIndex* index2 = [CBLIndex fullTextIndexWithItems: @[detailItem] options: nil];
    Assert([self.db createIndex: index2 withName: @"index2" error: &error],
           @"Error when creating FTS index without options: %@", error);
    
    CBLFullTextIndexItem* detailItem2 = [CBLFullTextIndexItem property: @"es-detail"];
    CBLFullTextIndexOptions* options = [[CBLFullTextIndexOptions alloc] init];
    options.locale = @"es";
    options.ignoreAccents = YES;
    CBLIndex* index3 = [CBLIndex fullTextIndexWithItems: @[detailItem2] options: options];
    Assert([self.db createIndex: index3 withName: @"index3" error: &error],
           @"Error when creating FTS index with options: %@", error);
    
    NSArray* names = self.db.indexes;
    AssertEqual(names.count, 3u);
    AssertEqualObjects(names, (@[@"index1", @"index2", @"index3"]));
}


- (void) testCreateSameIndexTwice {
    // Create index with first name:
    NSError* error;
    CBLValueIndexItem* item = [CBLValueIndexItem expression:
                               [CBLQueryExpression property: @"firstName"]];
    CBLIndex* index = [CBLIndex valueIndexWithItems: @[item]];
    Assert([self.db createIndex: index withName: @"myindex" error: &error],
           @"Error when creating value index: %@", error);
    
    // Call create index again:
    Assert([self.db createIndex: index withName: @"myindex" error: &error],
           @"Error when creating value index: %@", error);
    
    NSArray* names = self.db.indexes;
    AssertEqual(names.count, 1u);
    AssertEqualObjects(names, (@[@"myindex"]));
}


- (void) testCreateSameNameIndexes {
    NSError* error;
    
    CBLQueryExpression* fName = [CBLQueryExpression property: @"firstName"];
    CBLQueryExpression* lName = [CBLQueryExpression property: @"lastName"];
    
    // Create value index with first name:
    CBLValueIndexItem* fNameItem = [CBLValueIndexItem expression: fName];
    CBLIndex* fNameIndex = [CBLIndex valueIndexWithItems: @[fNameItem]];
    Assert([self.db createIndex: fNameIndex withName: @"myindex" error: &error],
           @"Error when creating value index: %@", error);

    // Create value index with last name:
    CBLValueIndexItem* lNameItem = [CBLValueIndexItem expression: lName];
    CBLIndex* lNameIndex = [CBLIndex valueIndexWithItems: @[lNameItem]];
    Assert([self.db createIndex: lNameIndex withName: @"myindex" error: &error],
           @"Error when creating value index: %@", error);
    
    // Check:
    NSArray* names = self.db.indexes;
    AssertEqual(names.count, 1u);
    AssertEqualObjects(names, (@[@"myindex"]));
    
    // Create FTS index:
    CBLFullTextIndexItem* detailItem = [CBLFullTextIndexItem property: @"detail"];
    CBLIndex* detailIndex = [CBLIndex fullTextIndexWithItems: @[detailItem] options: nil];
    Assert([self.db createIndex: detailIndex withName: @"myindex" error: &error],
           @"Error when creating FTS index without options: %@", error);
    
    // Check:
    names = self.db.indexes;
    AssertEqual(names.count, 1u);
    AssertEqualObjects(names, (@[@"myindex"]));
}


- (void) testDeleteIndex {
    // Precheck:
    AssertEqual(self.db.indexes.count, 0u);
    
    // Create value index:
    CBLQueryExpression* fName = [CBLQueryExpression property: @"firstName"];
    CBLQueryExpression* lName = [CBLQueryExpression property: @"lastName"];
    
    CBLValueIndexItem* fNameItem = [CBLValueIndexItem expression: fName];
    CBLValueIndexItem* lNameItem = [CBLValueIndexItem expression: lName];
    
    NSError* error;
    
    CBLIndex* index1 = [CBLIndex valueIndexWithItems: @[fNameItem, lNameItem]];
    Assert([self.db createIndex: index1 withName: @"index1" error: &error],
           @"Error when creating value index: %@", error);
    
    // Create FTS index:
    CBLFullTextIndexItem* detailItem = [CBLFullTextIndexItem property: @"detail"];
    CBLIndex* index2 = [CBLIndex fullTextIndexWithItems: @[detailItem] options: nil];
    Assert([self.db createIndex: index2 withName: @"index2" error: &error],
           @"Error when creating FTS index without options: %@", error);
    
    CBLFullTextIndexItem* detail2Item = [CBLFullTextIndexItem property: @"es-detail"];
    CBLFullTextIndexOptions* options = [[CBLFullTextIndexOptions alloc] init];
    options.locale = @"es";
    options.ignoreAccents = YES;
    CBLIndex* index3 = [CBLIndex fullTextIndexWithItems: @[detail2Item] options: options];
    Assert([self.db createIndex: index3 withName: @"index3" error: &error],
           @"Error when creating FTS index with options: %@", error);
    
    NSArray* names = self.db.indexes;
    AssertEqual(names.count, 3u);
    AssertEqualObjects(names, (@[@"index1", @"index2", @"index3"]));
    
    // Delete indexes:
    Assert([self.db deleteIndexForName: @"index1" error: &error]);
    names = self.db.indexes;
    AssertEqual(names.count, 2u);
    AssertEqualObjects(names, (@[@"index2", @"index3"]));
    
    Assert([self.db deleteIndexForName: @"index2" error: &error]);
    names = self.db.indexes;
    AssertEqual(names.count, 1u);
    AssertEqualObjects(names, (@[@"index3"]));
    
    Assert([self.db deleteIndexForName: @"index3" error: &error]);
    names = self.db.indexes;
    Assert(names);
    AssertEqual(names.count, 0u);
    
    // Delete non existing index:
    Assert([self.db deleteIndexForName: @"dummy" error: &error]);
    
    // Delete deleted indexes:
    Assert([self.db deleteIndexForName: @"index1" error: &error]);
    Assert([self.db deleteIndexForName: @"index2" error: &error]);
    Assert([self.db deleteIndexForName: @"index3" error: &error]);
}

@end
