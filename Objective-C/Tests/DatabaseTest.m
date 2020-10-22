//
//  DatabaseTest.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLTestCase.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"

@interface DatabaseTest : CBLTestCase
@end

@implementation DatabaseTest

// Helper methods to verify document
- (void) verifyDocumentWithID: (NSString*)documentID data: (NSDictionary*)data {
    CBLDocument* doc = [self.db documentWithID: documentID];
    AssertNotNil(doc);
    AssertEqualObjects(doc.id, documentID);
    AssertEqualObjects([doc toDictionary], data);
}

// Helper method to save n number of docs
- (NSArray*) createDocs: (int)n {
    NSMutableArray* docs = [NSMutableArray arrayWithCapacity: n];
    for(int i = 0; i < n; i++){
        CBLMutableDocument* doc = [self createDocument: [NSString stringWithFormat: @"doc_%03d", i]];
        [doc setValue: @(i) forKey:@"key"];
        [self saveDocument: doc];
        [docs addObject: doc];
    }
    AssertEqual(n, (long)self.db.count);
    return docs;
}

// Helper method to verify n number of docs
- (void) validateDocs: (int)n {
    for (int i = 0; i < n; i++) {
        NSString* documentID = [NSString stringWithFormat: @"doc_%03d", i];
        [self verifyDocumentWithID: documentID data: @{@"key": @(i)}];
    }
}

// Helper method to purge doc and verify doc.
- (void) purgeDocAndVerify: (CBLDocument*)doc {
    NSError* error;
    Assert([self.db purgeDocument: doc error: &error]);
    AssertNil(error);
    AssertNil([self.db documentWithID: doc.id]);
}

// Helper method to save a document with concurrency control
- (BOOL) saveDocument: (CBLMutableDocument *)document
   concurrencyControl: (int)concurrencyControl
{
    NSError* error;
    BOOL success = YES;
    if (concurrencyControl >= 0) {
        success = [self.db saveDocument: document
                     concurrencyControl: concurrencyControl error: &error];
        if (concurrencyControl == kCBLConcurrencyControlFailOnConflict) {
            AssertFalse(success);
            AssertEqual(error.domain, CBLErrorDomain);
            AssertEqual(error.code, CBLErrorConflict);
        } else {
            Assert(success && error == nil, @"Save Error: %@", error);
        }
    } else {
        Assert([self.db saveDocument: document error: &error], @"Save Error: %@", error);
    }
    return success;
}

// Helper method to delete a document with concurrency control
- (BOOL) deleteDocument: (CBLMutableDocument *)document
     concurrencyControl: (int)concurrencyControl
{
    NSError* error;
    BOOL success = YES;
    if (concurrencyControl >= 0) {
        success = [self.db deleteDocument: document
                     concurrencyControl: concurrencyControl error: &error];
        if (concurrencyControl == kCBLConcurrencyControlFailOnConflict) {
            AssertFalse(success);
            AssertEqual(error.domain, CBLErrorDomain);
            AssertEqual(error.code, CBLErrorConflict);
        } else {
            Assert(success && error == nil, @"Delete Error: %@", error);
        }
    } else {
        Assert([self.db deleteDocument: document error: &error], @"Delete Error: %@", error);
    }
    return success;
}

#pragma mark - DatabaseConfiguration

- (void) testCreateConfiguration {
    // Default:
    CBLDatabaseConfiguration* config1 = [[CBLDatabaseConfiguration alloc] init];
    AssertNotNil(config1.directory);
    Assert(config1.directory.length > 0);
    
    // Custom:
    CBLDatabaseConfiguration* config2 = [[CBLDatabaseConfiguration alloc] init];
    config2.directory = @"/tmp/mydb";
    AssertEqualObjects(config2.directory, @"/tmp/mydb");
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
    
    // Configuration from the database is readonly:
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        self.db.config.directory = @"";
    }];
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
    CBLDatabase* db = [self openDBNamed: @"`~@#$%^&*()_+{}|\\][=-.,<>?\":;'" error: &error];
    AssertNil(error);
    AssertNotNil(db, @"Couldn't open db: %@", db.name);
    AssertEqualObjects(db.name, @"`~@#$%^&*()_+{}|\\][=-.,<>?\":;'");
    Assert([db.path.lastPathComponent hasSuffix: @".cblite2"]);
    AssertEqual(0, (long)db.count);
    
    // delete database
    [self deleteDatabase: db];
}

- (void) testCreateWithEmptyDBNames {
    // create db with default configuration
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in: ^BOOL(NSError** error) {
        return [self openDBNamed: @"" error: error] != nil;
    }];
}

- (void) testCreateWithCustomDirectory {
    [CBLDatabase deleteDatabase: @"db" inDirectory: self.directory error: nil];
    AssertFalse([CBLDatabase databaseExists: @"db" inDirectory: self.directory]);
    
    // create db with custom directory
    NSError* error;
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = self.directory;
    
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" config: config error: &error];
    AssertNil(error);
    AssertNotNil(db, @"Couldn't open db: %@", error);
    AssertEqualObjects(db.name, @"db");
    Assert([db.path.lastPathComponent hasSuffix: @".cblite2"]);
    Assert([db.path containsString: self.directory]);
    Assert([CBLDatabase databaseExists: @"db" inDirectory: self.directory]);
    AssertEqual(0, (long)db.count);

    // delete database
    [self deleteDatabase: db];
}

#pragma mark - Get Document

- (void) testGetNonExistingDocWithID {
    AssertNil([self.db documentWithID:@"non-exist"]);
}

- (void) testGetExistingDocWithID {
    // Store doc:
    CBLDocument* doc = [self generateDocumentWithID: @"doc1"];
    
    // Validate document:
    [self verifyDocumentWithID: doc.id data: [doc toDictionary]];
}

- (void) testGetExistingDocWithIDFromDifferentDBInstance {
    // Store doc:
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocumentWithID: docID];
    
    // Open db with same db name and default option:
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: [self.db name] error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    
    // Get doc from other DB:
    AssertEqual(1, (long)otherDB.count);
    CBLDocument* otherDoc = [otherDB documentWithID: docID];
    AssertEqualObjects([otherDoc toDictionary], [doc toDictionary]);
    
    // Close otherDB:
    [self closeDatabase: otherDB];
}

- (void) testGetExistingDocWithIDInBatch {
    // Save 10 docs:
    [self createDocs: 10];
    
    // Validate:
    NSError* error;
    BOOL success = [self.db inBatch: &error usingBlock: ^{
        [self validateDocs: 10];
    }];
    Assert(success);
    AssertNil(error);
}

- (void) testGetDocFromClosedDB {
    // Store doc:
    [self generateDocumentWithID: @"doc1"];
    
    // Close db:
    [self closeDatabase: self.db];
    
    // Get doc:
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db documentWithID: @"doc1"];
    }];
}

- (void) testGetDocFromDeletedDB {
    // Store doc:
    [self generateDocumentWithID: @"doc1"];
    
    // Delete db:
    [self deleteDatabase: self.db];
    
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db documentWithID: @"doc1"];
    }];
}

#pragma mark - Save Document

- (void) testSaveDocWithID {
    CBLDocument* doc = [self generateDocumentWithID: @"doc1"];
    AssertEqual(self.db.count, 1u);
    [self verifyDocumentWithID: doc.id data: [doc toDictionary]];
}

- (void) testSaveDocWithSpecialCharactersDocID {
    NSString* docID = @"`~@#$%^&*()_+{}|\\][=-/.,<>?\":;'";
    CBLDocument* doc = [self generateDocumentWithID: docID];
    AssertEqual(1, (long)self.db.count);
    [self verifyDocumentWithID: doc.id data: [doc toDictionary]];
}

- (void) testSaveDocWIthAutoGeneratedID {
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertEqual(1, (long)self.db.count);
    [self verifyDocumentWithID: doc.id data: [doc toDictionary]];
}

- (void) testSaveDocInDifferentDBInstance {
    CBLMutableDocument* doc = [self generateDocumentWithID: @"doc1"];
    
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: [self.db name] error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    AssertEqual(otherDB.count, 1u);
    
    [doc setValue: @2 forKey: @"key"];
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in: ^BOOL(NSError** error2) {
        return [otherDB saveDocument: doc error: error2];
    }]; // forbidden
    
    // close otherDB
    [self closeDatabase: otherDB];
}

- (void) testSaveDocInDifferentDB {
    CBLMutableDocument* doc = [self generateDocumentWithID: @"doc1"];
    
    // create db with default
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: @"otherDB" error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    AssertEqual(otherDB.count, 0u);
    
    // update doc & store it into different db
    [doc setValue: @2 forKey: @"key"];
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in: ^BOOL(NSError** error2) {
        return [otherDB saveDocument: doc error: error2];
    }]; // forbidden
    
    // delete otherDB
    [self deleteDatabase: otherDB];
}

- (void) testSaveSameDocTwice {
    CBLMutableDocument* doc = [self generateDocumentWithID: @"doc1"];
    [self saveDocument: doc];
    
    CBLDocument* doc1 = [self.db documentWithID: doc.id];
    AssertEqual(doc1.sequence, 2u);
    AssertEqual(self.db.count, 1u);
}

- (void) testSaveInBatch {
    NSError* error;
    BOOL success = [self.db inBatch: &error usingBlock: ^{
        // save 10 docs
        [self createDocs: 10];
    }];
    Assert(success);
    AssertEqual(self.db.count, 10u);
    [self validateDocs: 10];
}

- (void) testSaveWithErrorInBatch {
    __block NSError* error = nil;
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db inBatch: &error usingBlock: ^{
            [self createDocs: 5];
            AssertEqual(self.db.count, 5);
            [NSException raise: NSInternalInconsistencyException format: @"some exception"];
        }];
    }];
    AssertEqual(self.db.count, 0u);
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

- (void) testSaveManyDocs {
    [self createDocs: 1000];
    AssertEqual(self.db.count, 1000u);
    [self validateDocs: 1000];
    
    // Clean up:
    NSError* error;
    Assert([self.db delete:&error]);
    [self reopenDB];
    
    // Run in batch:
    BOOL success = [self.db inBatch: &error usingBlock: ^{
        // save 1000 docs
        [self createDocs: 1000];
    }];
    Assert(success);
    AssertEqual(self.db.count, 1000u);
    [self validateDocs: 1000];
}

- (void) testSaveAndUpdateMutableDoc {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc setString: @"Daniel" forKey: @"firstName"];
    NSError* error;
    Assert([self.db saveDocument: doc error: &error], @"Error: %@", error);
    
    // Update:
    [doc setString: @"Tiger" forKey: @"lastName"];
    Assert([self.db saveDocument: doc error: &error], @"Error: %@", error);
    
    // Update:
    [doc setInteger: 20 forKey: @"age"];
    Assert([self.db saveDocument: doc error: &error], @"Error: %@", error);
    
    NSDictionary* expectedResult = @{@"firstName": @"Daniel",
                                     @"lastName": @"Tiger",
                                     @"age": @(20)};
    AssertEqualObjects([doc toDictionary], expectedResult);
    AssertEqual(doc.sequence, 3u);
    
    CBLDocument* savedDoc = [self.db documentWithID: doc.id];
    AssertEqualObjects([savedDoc toDictionary], expectedResult);
    AssertEqual(savedDoc.sequence, 3u);
}

- (void) testSaveDocWithConflict {
    [self testSaveDocWithConflictUsingConcurrencyControl: -1];
    [self testSaveDocWithConflictUsingConcurrencyControl: kCBLConcurrencyControlLastWriteWins];
    [self testSaveDocWithConflictUsingConcurrencyControl: kCBLConcurrencyControlFailOnConflict];
}

- (void) testSaveDocWithConflictUsingConcurrencyControl: (int)concurrencyControl {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc setString: @"Daniel" forKey: @"firstName"];
    [doc setString: @"Tiger" forKey: @"lastName"];
    NSError* error;
    Assert([self.db saveDocument: doc error: &error], @"Error: %@", error);
    
    // Get two doc1 document objects (doc1a and doc1b):
    CBLMutableDocument* doc1a = [[self.db documentWithID: @"doc1"] toMutable];
    CBLMutableDocument* doc1b = [[self.db documentWithID: @"doc1"] toMutable];
    
    // Modify doc1a:
    [doc1a setString: @"Scott" forKey: @"firstName"];
    Assert([self.db saveDocument: doc1a error: &error], @"Error: %@", error);
    [doc1a setString: @"Scotty" forKey: @"nickName"];
    Assert([self.db saveDocument: doc1a error: &error], @"Error: %@", error);
    AssertEqualObjects([doc1a toDictionary], (@{@"firstName": @"Scott",
                                                @"lastName": @"Tiger",
                                                @"nickName": @"Scotty"}));
    AssertEqual(doc1a.sequence, 3u);
    
    // Modify doc1b, result to conflict when save:
    [doc1b setString: @"Lion" forKey: @"lastName"];
    if ([self saveDocument: doc1b concurrencyControl: concurrencyControl]) {
        CBLDocument* savedDoc = [self.db documentWithID: doc.id];
        AssertEqualObjects([savedDoc toDictionary], [doc1b toDictionary]);
        AssertEqual(savedDoc.sequence, 4u);
    }
    
    // Cleanup:
    [self cleanDB];
}

- (void) testSaveDocWithNoParentConflict {
    [self testSaveDocWithNoParentConflictUsingConcurrencyControl: -1];
    [self testSaveDocWithNoParentConflictUsingConcurrencyControl: kCBLConcurrencyControlLastWriteWins];
    [self testSaveDocWithNoParentConflictUsingConcurrencyControl: kCBLConcurrencyControlFailOnConflict];
}

- (void) testSaveDocWithNoParentConflictUsingConcurrencyControl: (int)concurrencyControl {
    CBLMutableDocument* doc1a = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1a setString: @"Daniel" forKey: @"firstName"];
    [doc1a setString: @"Tiger" forKey: @"lastName"];
    NSError* error;
    Assert([self.db saveDocument: doc1a error: &error], @"Error: %@", error);
    AssertEqual(doc1a.sequence, 1u);
    
    CBLDocument* savedDoc = [self.db documentWithID: doc1a.id];
    AssertEqualObjects([savedDoc toDictionary], [doc1a toDictionary]);
    AssertEqual(savedDoc.sequence, 1u);
    
    CBLMutableDocument* doc1b = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1b setString: @"Scott" forKey: @"firstName"];
    [doc1b setString: @"Tiger" forKey: @"lastName"];
    if ([self saveDocument: doc1b concurrencyControl: concurrencyControl]) {
        savedDoc = [self.db documentWithID: doc1b.id];
        AssertEqualObjects([savedDoc toDictionary], [doc1b toDictionary]);
        AssertEqual(savedDoc.sequence, 2u);
    }
    
    // Cleanup:
    [self cleanDB];
}

- (void) testSaveDocWithDeletedConflict {
    [self testSaveDocWithDeletedConflictUsingConcurrencyControl: -1];
    [self testSaveDocWithDeletedConflictUsingConcurrencyControl: kCBLConcurrencyControlLastWriteWins];
    [self testSaveDocWithDeletedConflictUsingConcurrencyControl: kCBLConcurrencyControlFailOnConflict];
}

- (void) testSaveDocWithDeletedConflictUsingConcurrencyControl: (int)concurrencyControl {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc setString: @"Daniel" forKey: @"firstName"];
    [doc setString: @"Tiger" forKey: @"lastName"];
    NSError* error;
    Assert([self.db saveDocument: doc error: &error], @"Error: %@", error);
    
    // Get two doc1 document objects (doc1a and doc1b):
    CBLDocument* doc1a = [self.db documentWithID: @"doc1"];
    CBLMutableDocument* doc1b = [[self.db documentWithID: @"doc1"] toMutable];
    
    // Delete doc1a:
    Assert([self.db deleteDocument: doc1a error: &error], @"Error: %@", error);
    AssertEqual(doc1a.sequence, 2u);
    AssertNil([self.db documentWithID: doc.id]);
    
    // Modify doc1b:
    [doc1b setString: @"Lion" forKey: @"lastName"];
    if ([self saveDocument: doc1b concurrencyControl: concurrencyControl]) {
        CBLDocument* savedDoc = [self.db documentWithID: doc.id];
        AssertEqualObjects([savedDoc toDictionary], [doc1b toDictionary]);
        AssertEqual(savedDoc.sequence, 3u);
    }
    
    // Cleanup:
    [self cleanDB];
}

- (void) testSavePurgedDoc {
    NSString* docID = @"doc1";
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: docID];
    [doc setString: @"Tiger" forKey: @"name"];
    NSError* error;
    Assert([self.db saveDocument: doc error: &error], @"Error: %@", error);
    
    CBLMutableDocument* doc1b = [[self.db documentWithID: docID] toMutable];
    
    Assert([self.db purgeDocumentWithID: docID error: &error], @"Error: %@", error);
    
    // try saving the purged doc instance: Should return NotFound!!
    [doc1b setString: @"Peter" forKey: @"firstName"];
    AssertFalse([self.db saveDocument: doc1b error: &error]);
    AssertEqual(error.code, CBLErrorNotFound);
    AssertEqual(error.domain, CBLErrorDomain);
    
    // try saving the doc with same name, which should be saved without any issue.
    CBLMutableDocument* doc1c = [[CBLMutableDocument alloc] initWithID: docID];
    Assert([self.db saveDocument: doc1c error: &error], @"Error: %@", error);
}

#pragma mark Save Conflict Handler

- (void) testConflictHandler {
    NSString* docID = @"doc1";
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: docID];
    [doc setString: @"Tiger" forKey: @"firstName"];
    [self saveDocument: doc];
    AssertEqual([self.db documentWithID: docID].generation, 1u);
    
    CBLMutableDocument* doc1a = [[self.db documentWithID: docID] toMutable];
    CBLMutableDocument* doc1b = [[self.db documentWithID: docID] toMutable];
    
    [doc1a setString: @"Scotty" forKey: @"nickName"];
    [self saveDocument: doc1a];
    AssertEqual([self.db documentWithID: docID].generation, 2u);
    
    NSError* error;
    [doc1b setString: @"Scott" forKey: @"nickName"];
    Assert([self.db saveDocument: doc1b
                 conflictHandler:^BOOL(CBLMutableDocument * document, CBLDocument * old) {
                     Assert(doc1b == document);
                     AssertEqualObjects(doc1b.toDictionary, document.toDictionary);
                     AssertEqualObjects(doc1a.toDictionary, old.toDictionary);
                     AssertEqual(document.generation, 2u);
                     AssertEqual(old.generation, 2u);
                     return YES;
                 } error: &error]);
    AssertEqualObjects([self.db documentWithID: docID].toDictionary, doc1b.toDictionary);
    AssertEqual([self.db documentWithID: docID].generation, 3u);
    
    doc1a = [[self.db documentWithID: docID] toMutable];
    doc1b = [[self.db documentWithID: docID] toMutable];
    
    [doc1a setString: @"Sccotty" forKey: @"nickName"];
    [self saveDocument: doc1a];
    AssertEqual([self.db documentWithID: docID].generation, 4u);
    
    [doc1b setString: @"Scotty" forKey: @"nickName"];
    Assert([self.db saveDocument: doc1b
                 conflictHandler:^BOOL(CBLMutableDocument * document, CBLDocument * old) {
                     Assert(doc1b == document);
                     AssertEqualObjects(doc1b.toDictionary, document.toDictionary);
                     AssertEqualObjects(doc1a.toDictionary, old.toDictionary);
                     AssertEqual(document.generation, 4u);
                     AssertEqual(old.generation, 4u);
                     [document setString: @"Scott" forKey: @"nickName"];
                     return YES;
                 } error: &error]);
    NSDictionary* expected = @{@"nickName": @"Scott", @"firstName": @"Tiger"};
    AssertEqualObjects([self.db documentWithID: docID].toDictionary, expected);
    AssertEqual([self.db documentWithID: docID].generation, 5u);
}

- (void) testCancelConflictHandler {
    NSString* docID = @"doc1";
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: docID];
    [doc setString: @"Tiger" forKey: @"firstName"];
    [self saveDocument: doc];
    AssertEqual([self.db documentWithID: docID].generation, 1u);
    
    CBLMutableDocument* doc1a = [[self.db documentWithID: docID] toMutable];
    CBLMutableDocument* doc1b = [[self.db documentWithID: docID] toMutable];
    
    [doc1a setString: @"Scotty" forKey: @"nickName"];
    [self saveDocument: doc1a];
    AssertEqual([self.db documentWithID: docID].generation, 2u);
    
    NSError* error;
    [doc1b setString: @"Scott" forKey: @"nickName"];
    AssertFalse([self.db saveDocument: doc1b
                      conflictHandler:^BOOL(CBLMutableDocument * document, CBLDocument * old) {
                          AssertEqualObjects(doc1b.toDictionary, document.toDictionary);
                          AssertEqualObjects(doc1a.toDictionary, old.toDictionary);
                          return NO;
                      } error: &error]);
    AssertEqual(error.code, CBLErrorConflict);
    AssertEqualObjects([self.db documentWithID: docID].toDictionary, doc1a.toDictionary);
    
    // make sure no update to revision and generation
    AssertEqualObjects([self.db documentWithID: docID].revisionID, doc1a.revisionID);
    AssertEqual([self.db documentWithID: docID].generation, 2u);
    
    // Some Updates to Current Mutable Document
    doc1a = [[self.db documentWithID: docID] toMutable];
    doc1b = [[self.db documentWithID: docID] toMutable];
    
    [doc1a setString: @"Sccotty" forKey: @"nickName"];
    [self saveDocument: doc1a];
    AssertEqual([self.db documentWithID: docID].generation, 3u);
    
    [doc1b setString: @"Scotty" forKey: @"nickName"];
    AssertFalse([self.db saveDocument: doc1b
                      conflictHandler:^BOOL(CBLMutableDocument * document, CBLDocument * old) {
                          // with some updates to the existing doc also shouldn't cause any issues
                          [document setString: @"Scott" forKey: @"nickName"];
                          return NO;
                      } error: &error]);
    AssertEqual(error.code, CBLErrorConflict);
    AssertEqualObjects([self.db documentWithID: docID].toDictionary, doc1a.toDictionary);
    
    // make sure no update to revision and generation
    AssertEqual([self.db documentWithID: docID].generation, 3u);
    AssertEqualObjects([self.db documentWithID: docID].revisionID, doc1a.revisionID);
}

- (void) testConflictHandlerWhenDocumentIsPurged {
    NSString* docID = @"doc1";
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: docID];
    [doc setString: @"Tiger" forKey: @"firstName"];
    [self saveDocument: doc];
    AssertEqual([self.db documentWithID: docID].generation, 1u);
    
    CBLMutableDocument* doc1b = [[self.db documentWithID: docID] toMutable];
    
    NSError* error;
    [self.db purgeDocumentWithID: docID error: &error];
    
    [doc1b setString: @"Scott" forKey: @"nickName"];
    AssertFalse([self.db saveDocument: doc1b
                      conflictHandler:^BOOL(CBLMutableDocument * document, CBLDocument * old) {
                          return YES;
                      } error: &error]);
    AssertEqual(error.code, CBLErrorNotFound);
}

// since objc is not exception safe, this exception throw result in memory issue
// TODO: handle the expected memory issue in tests. s
- (void) _testConflictHandlerThrowingException {
    NSString* docID = @"doc1";
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: docID];
    [doc setString: @"Tiger" forKey: @"firstName"];
    [self saveDocument: doc];
    AssertEqual([self.db documentWithID: docID].generation, 1u);
    
    CBLMutableDocument* doc1a = [[self.db documentWithID: docID] toMutable];
    CBLMutableDocument* doc1b = [[self.db documentWithID: docID] toMutable];
    
    [doc1a setString: @"Scotty" forKey: @"nickName"];
    [self saveDocument: doc1a];
    AssertEqual([self.db documentWithID: docID].generation, 2u);
    
    NSError* error;
    [doc1b setString: @"Scott" forKey: @"nickName"];
    BOOL success = [self.db saveDocument: doc1b
                         conflictHandler:^BOOL(CBLMutableDocument * document, CBLDocument * old) {
                             [NSException raise: NSInternalInconsistencyException
                                         format: @"exception inside the conflict handler"];
                             return YES;
                         } error: &error];
    AssertFalse(success);
    AssertEqualObjects([self.db documentWithID: docID].toDictionary, doc1a.toDictionary);
    AssertEqual([self.db documentWithID: docID].generation, 2u);
    AssertEqual(error.code, CBLErrorConflict);
}

- (void) testConflictHandlerWithDeletedOldDoc {
    NSString* docID = @"doc1";
    [self generateDocumentWithID: docID];
    AssertEqual([self.db documentWithID: docID].generation, 1u);
    
    // keeps new doc(non-deleted)
    CBLMutableDocument* doc1a = [[self.db documentWithID: docID] toMutable];
    CBLMutableDocument* doc1b = [[self.db documentWithID: docID] toMutable];
    
    [self deleteDocument: doc1a concurrencyControl: kCBLConcurrencyControlLastWriteWins];
    
    NSError* error = nil;
    [doc1b setString: @"value1" forKey: @"key1"];
    Assert([self.db saveDocument: doc1b
                 conflictHandler:^BOOL(CBLMutableDocument * document, CBLDocument * old) {
                     AssertNil(old);
                     AssertNotNil(document);
                     return YES;
                 } error: &error]);
    AssertEqualObjects([self.db documentWithID: docID].toDictionary, doc1b.toDictionary);
    
    // keeps the deleted(old doc)
    doc1a = [[self.db documentWithID: docID] toMutable];
    doc1b = [[self.db documentWithID: docID] toMutable];
    [self deleteDocument: doc1a concurrencyControl: kCBLConcurrencyControlLastWriteWins];
    
    [doc1b setString: @"value2" forKey: @"key2"];
    AssertFalse([self.db saveDocument: doc1b
                      conflictHandler:^BOOL(CBLMutableDocument * document, CBLDocument * old) {
                          AssertNil(old);
                          AssertNotNil(document);
                          return NO;
                      } error: &error]);
    AssertEqual(error.code, CBLErrorConflict);
    AssertNil([self.db documentWithID: docID]);
    Assert([[CBLDocument alloc] initWithDatabase: self.db
                                      documentID: docID
                                  includeDeleted: YES
                                           error: &error].isDeleted);
}

- (void) testConflictHandlerCalledTwice {
    NSString* docID = @"doc1";
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: docID];
    [doc setString: @"Tiger" forKey: @"firstName"];
    [self saveDocument: doc];
    AssertEqual([self.db documentWithID: docID].generation, 1u);
    
    CBLMutableDocument* doc1a = [[self.db documentWithID: docID] toMutable];
    CBLMutableDocument* doc1b = [[self.db documentWithID: docID] toMutable];
    
    [doc1a setString: @"Scotty" forKey: @"nickName"];
    [self saveDocument: doc1a];
    AssertEqual([self.db documentWithID: docID].generation, 2u);
    
    NSError* error;
    [doc1b setString: @"Scott" forKey: @"nickName"];
    __block int count = 0;
    Assert([self.db saveDocument: doc1b
                 conflictHandler:^BOOL(CBLMutableDocument * document, CBLDocument * old) {
                     Assert(document == doc1b);
                     count++;
                     CBLMutableDocument* doc1c = [[self.db documentWithID: docID] toMutable];
                     if (![doc1c booleanForKey: @"secondUpdate"]) {
                         AssertEqual(old.generation, 2u);
                         AssertEqual(document.generation, 2u);
                         [doc1c setBoolean: YES forKey: @"secondUpdate"];
                         [self saveDocument: doc1c];
                         AssertEqual([self.db documentWithID: docID].generation, 3u);
                     }
                     
                     // Going to merge the two document contents
                     NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary: old.toDictionary];
                     for (NSString* key in document.toDictionary.allKeys) {
                         [dict setValue: [document valueForKey: key] forKey: key];
                     }
                     [document setData: dict];
                     [document setValue: @"local" forKey: @"edit"];
                     return YES;
                 } error: &error]);
    
    // make sure the save handler method called twice due to second conflict
    AssertEqual(count, 2u);
    AssertEqual(self.db.count, 1u);
    
    NSDictionary* expected = @{@"nickName": @"Scott",
                               @"firstName": @"Tiger",
                               @"secondUpdate": @YES,
                               @"edit": @"local"};
    AssertEqualObjects([self.db documentWithID: docID].toDictionary, expected);
    AssertEqual([self.db documentWithID: docID].generation, 4u);
}

#pragma mark - Delete Document

- (void) testDeletePreSaveDoc {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @1 forKey: @"key"];
    
    [self expectError: CBLErrorDomain code: CBLErrorNotFound in: ^BOOL(NSError** err) {
        return [self.db deleteDocument: doc error: err];
    }];
    
    AssertEqual(self.db.count, 0u);
}

- (void) testDeleteDoc {
    CBLDocument* doc = [self generateDocumentWithID: @"doc1"];
    
    NSError* error;
    Assert([self.db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: doc.id]);
}

- (void) testDeleteSameDocTwice {
    CBLDocument* doc = [self generateDocumentWithID: @"doc1"];
    
    // First time deletion:
    NSError* error;
    Assert([self.db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: doc.id]);
    AssertEqual(doc.sequence, 2u);
    
    // Second time deletion:
    Assert([self.db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: doc.id]);
    AssertEqual(doc.sequence, 3u);
}

- (void) testDeleteNonExistingDoc {
    CBLDocument* doc1a = [self generateDocumentWithID: @"doc1"];
    CBLDocument* doc1b = [self.db documentWithID: doc1a.id];
    
    // Purge doc:
    NSError* error;
    Assert([self.db purgeDocument: doc1a error: &error]);
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: doc1a.id]);
    
    // Delete doc1a, 404 error:
    [self expectError: CBLErrorDomain code: CBLErrorNotFound in: ^BOOL(NSError** err) {
        return [self.db deleteDocument: doc1a error: err];
    }];
    
    // Delete doc1b, no-ops:
    Assert([self.db deleteDocument: doc1b error: &error]);
    AssertNil(error);
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: doc1b.id]);
}

- (void) testDeleteDocInBatch {
    // Save 10 docs
    NSArray<CBLDocument*>* docs = [self createDocs: 10];
    
    NSError* error;
    BOOL success = [self.db inBatch: &error usingBlock: ^{
        for(int i = 0; i < 10; i++) {
            NSError* err;
            CBLDocument* doc = [self.db documentWithID: docs[i].id];
            Assert([self.db deleteDocument: doc error: &err]);
            AssertNil(err);
            AssertEqual((int)self.db.count, 9-i);
        }
    }];
    Assert(success);
    AssertNil(error);
    AssertEqual(self.db.count, 0u);
}

- (void) testDeleteDocOnClosedDB {
    // Store doc
    CBLDocument* doc = [self generateDocumentWithID: @"doc1"];
    
    // Close db
    [self closeDatabase: self.db];
    
    // Delete doc from db.
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db deleteDocument: doc error: nil];
    }];
}

- (void) testDeleteDocOnDeletedDB {
    // Store doc
    CBLDocument* doc = [self generateDocumentWithID:@"doc1"];
    
    // Delete db
    [self deleteDatabase: self.db];
    
    // Delete doc from db.
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db deleteDocument: doc error: nil];
    }];
}

- (void) testDeleteAndUpdateDoc {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc setString: @"Daniel" forKey: @"firstName"];
    [doc setString: @"Tiger" forKey: @"lastName"];
    NSError* error;
    Assert([self.db saveDocument: doc error: &error], @"Error: %@", error);
    
    Assert([self.db deleteDocument: doc error: &error], @"Error: %@", error);
    AssertEqual(doc.sequence, 2u);
    AssertNil([self.db documentWithID: doc.id]);
    
    [doc setString: @"Scott" forKey: @"firstName"];
    Assert([self.db saveDocument: doc error: &error], @"Error: %@", error);
    AssertEqual(doc.sequence, 3u);
    AssertEqualObjects([doc toDictionary], (@{@"firstName": @"Scott",
                                              @"lastName": @"Tiger"}));
    
    CBLDocument* savedDoc = [self.db documentWithID: doc.id];
    AssertNotNil(savedDoc);
    AssertEqualObjects([savedDoc toDictionary], [doc toDictionary]);
}

- (void) testDeleteAlreadyDeletedDoc {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc setString: @"Daniel" forKey: @"firstName"];
    [doc setString: @"Tiger" forKey: @"lastName"];
    NSError* error;
    Assert([self.db saveDocument: doc error: &error], @"Error: %@", error);
    
    // Get two doc1 document objects (doc1a and doc1b):
    CBLDocument* doc1a = [self.db documentWithID: doc.id];
    CBLMutableDocument* doc1b = [[self.db documentWithID: doc.id] toMutable];
    
    // Delete doc1a:
    Assert([self.db deleteDocument: doc1a error: &error], @"Error: %@", error);
    AssertEqual(doc1a.sequence, 2u);
    AssertNil([self.db documentWithID: doc.id]);
    
    // Delete doc1b:
    Assert([self.db deleteDocument: doc1b error: &error], @"Error: %@", error);
    AssertEqual(doc1b.sequence, 2u);
    AssertNil([self.db documentWithID: doc.id]);
}

- (void) testDeleteDocWithConflict {
    [self testDeleteDocWithConflictUsingConcurrencyControl: -1];
    [self testDeleteDocWithConflictUsingConcurrencyControl: kCBLConcurrencyControlLastWriteWins];
    [self testDeleteDocWithConflictUsingConcurrencyControl: kCBLConcurrencyControlFailOnConflict];
}

- (void) testDeleteDocWithConflictUsingConcurrencyControl: (int)concurrencyControl {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc setString: @"Daniel" forKey: @"firstName"];
    [doc setString: @"Tiger" forKey: @"lastName"];
    NSError* error;
    Assert([self.db saveDocument: doc error: &error], @"Error: %@", error);
    
    // Get two document objects (doc1a and doc1b):
    CBLMutableDocument* doc1a = [[self.db documentWithID: doc.id] toMutable];
    CBLMutableDocument* doc1b = [[self.db documentWithID: doc.id] toMutable];
    
    // Modify doc1a:
    [doc1a setString: @"Scott" forKey: @"firstName"];
    Assert([self.db saveDocument: doc1a error: &error], @"Error: %@", error);
    AssertEqualObjects([doc1a toDictionary], (@{@"firstName": @"Scott",
                                                @"lastName": @"Tiger"}));
    AssertEqual(doc1a.sequence, 2u);
    
    // Modify doc1b and delete, result to conflict when delete:
    [doc1b setString: @"Lion" forKey: @"lastName"];
    if ([self deleteDocument: doc1b concurrencyControl: concurrencyControl]) {
        AssertEqual(doc1b.sequence, 3u);
        AssertNil([self.db documentWithID: doc1b.id]);
    }
    AssertEqualObjects([doc1b toDictionary], (@{@"firstName": @"Daniel",
                                                @"lastName": @"Lion"}));
    
    // Cleanup:
    [self cleanDB];
}

#pragma mark - Purge Document

- (void) testPurgePreSaveDoc {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self expectError: CBLErrorDomain code: CBLErrorNotFound
                   in: ^BOOL(NSError ** error) {
        return [self.db purgeDocument: doc error: error];
    }];
}

- (void) testPurgeDoc {
    // Store doc:
    CBLDocument* doc = [self generateDocumentWithID: @"doc1"];
    
    // Purge Doc:
    [self purgeDocAndVerify: doc];
    AssertEqual(self.db.count, 0u);
}

- (void) testPurgeDocInDifferentDBInstance {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocumentWithID: docID];
    
    // create db instance with same name
    NSError* error;
    CBLDatabase* otherDB = [self openDBNamed: self.db.name error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertNotNil([otherDB documentWithID: docID]);
    AssertEqual(1, (long)otherDB.count);
    
    // purge document against other db instance
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in: ^BOOL(NSError** error2) {
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
    CBLDocument* doc = [self generateDocumentWithID: docID];
    
    // create db with different name
    NSError* error;
    CBLDatabase* otherDB =  [self openDBNamed: @"otherDB" error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertNil([otherDB documentWithID: docID]);
    AssertEqual(0, (long)otherDB.count);
    
    // purge document against other db
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in: ^BOOL(NSError** error2) {
        return [otherDB purgeDocument: doc error: error2];
    }]; // forbidden
    
    AssertEqual(0, (long)otherDB.count);
    AssertEqual(1, (long)self.db.count);
    
    [self deleteDatabase: otherDB];
}

- (void) testPurgeSameDocTwice {
    // store doc
    NSString* docID = @"doc1";
    CBLDocument* doc = [self generateDocumentWithID: docID];
    
    // Purge Doc first time
    [self purgeDocAndVerify: doc];
    AssertEqual(0, (long)self.db.count);
    
    // Purge Doc second time
    [self expectError: CBLErrorDomain code: CBLErrorNotFound in: ^BOOL(NSError** error) {
        return [self.db purgeDocument: doc error: error];
    }];
}

- (void) testPurgeDocInBatch {
    // save 10 docs
    [self createDocs: 10];

    NSError* error;
    BOOL success = [self.db inBatch: &error usingBlock: ^{
        for(int i = 0; i < 10; i++) {
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
    CBLDocument* doc = [self generateDocumentWithID: @"doc1"];
    
    // close db
    [self closeDatabase: self.db];
    
    // purge doc
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db purgeDocument: doc error: nil];
    }];
}

- (void) testPurgeDocOnDeletedDB {
    // store doc
    CBLDocument* doc = [self generateDocumentWithID: @"doc1"];
   
    // delete db
    [self deleteDatabase: self.db];
    
    // purge doc
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db purgeDocument: doc error: nil];
    }];
}

- (void) testPurgeDocumentOnADeletedDocument {
    CBLDocument* document = [self generateDocumentWithID: nil];
    NSString* documentID = document.id;
    AssertNotNil(documentID);
    
    // Delete doc
    NSError* errorWhileDeletion;
    Assert([self.db deleteDocument: document error: &errorWhileDeletion]);
    AssertNil(errorWhileDeletion);
    NSError* documentReadError;
    CBLDocument* savedDocument = [[CBLDocument alloc] initWithDatabase: self.db
                                                            documentID: documentID
                                                        includeDeleted: YES
                                                                 error: &documentReadError];
    AssertNotNil(savedDocument);
    
    // Purge doc on the deleted document
    NSError* errorWhilePurging;
    Assert([self.db purgeDocument: document error: &errorWhilePurging]);
    AssertNil(errorWhilePurging);
    savedDocument = [[CBLDocument alloc] initWithDatabase: self.db
                                               documentID: documentID
                                           includeDeleted: YES
                                                    error: &documentReadError];
    AssertNil(savedDocument);
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: documentID]);
}

#pragma mark - Purge Document WithID

- (void) testPurgeDocumentWithIDPreSave {
    AssertEqual(0, (long)self.db.count);
    
    // create a doc & not save
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    NSString* documentID = [NSString stringWithFormat:@"%0.0f", timestamp];
    CBLMutableDocument* doc = [self createDocument: documentID];
    
    // not found
    [self expectError: CBLErrorDomain
                 code: CBLErrorNotFound
                   in: ^BOOL(NSError** errorWhilePurging) {
                       return [self.db purgeDocumentWithID: documentID error: errorWhilePurging];
                   }];
    
    documentID = nil;
    doc = nil;
    AssertEqual(0, (long)self.db.count);
}

- (void) testPurgeDocumentWithID {
    CBLDocument* document = [self generateDocumentWithID: nil];
    NSString* documentID = document.id;
    AssertNotNil(documentID);
    
    NSError* errorWhilePurging;
    [self.db purgeDocumentWithID: documentID error: &errorWhilePurging];
    AssertNil(errorWhilePurging);
    
    AssertNil([self.db documentWithID: documentID]);
    AssertEqual(self.db.count, 0u);
}

- (void) testPurgeDocumentWithIDInDifferentDBInstance {
    // store doc
    CBLDocument* document = [self generateDocumentWithID: nil];
    NSString* documentID = document.id;
    AssertNotNil(documentID);
    
    // create db instance with same name
    NSError* errorWhileOpeningDB;
    CBLDatabase* otherDB = [self openDBNamed: self.db.name error: &errorWhileOpeningDB];
    AssertNil(errorWhileOpeningDB);
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertNotNil([otherDB documentWithID: documentID]);
    AssertEqual(1, (long)otherDB.count);
    
    // purge document from other db instance
    NSError* errorWhilePurging;
    [otherDB purgeDocumentWithID: documentID error: &errorWhilePurging];
    
    // should remove doc from both DB instances
    AssertNil(errorWhilePurging);
    AssertNil([self.db documentWithID: documentID]);
    AssertNil([otherDB documentWithID: documentID]);
    AssertEqual(0, (long)otherDB.count);
    AssertEqual(0, (long)self.db.count);
    
    // close otherDB
    [self closeDatabase: otherDB];
}

- (void) testPurgeDocumentWithIDFromUnknownDB {
    // store doc
    CBLDocument* document = [self generateDocumentWithID: nil];
    NSString* documentID = document.id;
    AssertNotNil(documentID);
    
    // create db with different name
    NSError* errorWhileOpeningDB;
    CBLDatabase* otherDB =  [self openDBNamed: @"otherDB" error: &errorWhileOpeningDB];
    AssertNil(errorWhileOpeningDB);
    
    // validate the otherDB
    AssertNotNil(otherDB);
    Assert(otherDB != self.db);
    AssertNil([otherDB documentWithID: documentID]);
    AssertEqual(0, (long)otherDB.count);
    
    // purge document from other db - where no document exists
    [self expectError: CBLErrorDomain
                 code: CBLErrorNotFound
                   in: ^BOOL(NSError** errorWhilePurging) {
                       return [otherDB purgeDocumentWithID: documentID error: errorWhilePurging];
    }];
    
    AssertEqual(0, (long)otherDB.count);
    AssertEqual(1, (long)self.db.count);
    
    [self deleteDatabase: otherDB];
}

- (void) testCallPurgeDocumentWithIDTwice {
    // store doc
    CBLDocument* document = [self generateDocumentWithID: nil];
    NSString* documentID = document.id;
    AssertNotNil(documentID);

    // Purge Doc first time
    NSError* errorWhilePurging;
    [self.db purgeDocumentWithID: documentID error: &errorWhilePurging];
    AssertNil(errorWhilePurging);
    AssertEqual(0, (long)self.db.count);

    // Purge Doc second time
    [self expectError: CBLErrorDomain code: CBLErrorNotFound in: ^BOOL(NSError** error) {
        return [self.db purgeDocumentWithID: documentID error: error];
    }];
}

- (void) testPurgeDocumentWithIDInBatch {
    int totalDocumentsCount = 10;
    [self createDocs: totalDocumentsCount];

    NSError* error;
    BOOL success = [self.db inBatch: &error usingBlock: ^{
        for(int i = 0; i < totalDocumentsCount; i++) {
            NSString* documentID = [[NSString alloc] initWithFormat: @"doc_%03d", i];
            NSError* errorWhilePurging;
            [self.db purgeDocumentWithID: documentID error: &errorWhilePurging];
            AssertNil(errorWhilePurging);
            AssertEqual((totalDocumentsCount - 1) - i, (long)self.db.count);
        }
    }];
    Assert(success);
    AssertNil(error);
    AssertEqual(0, (long)self.db.count);
}

- (void) testPurgeDocumentWithIDOnClosedDB {
    // store doc
    CBLDocument* document = [self generateDocumentWithID: nil];
    NSString* documentID = document.id;
    AssertNotNil(documentID);

    // close db
    [self closeDatabase: self.db];

    // purge doc
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db purgeDocumentWithID: documentID error: nil];
    }];
}

- (void) testPurgeDocumentWithIDOnDeletedDB {
    // store doc
    CBLDocument* document = [self generateDocumentWithID: nil];
    NSString* documentID = document.id;
    AssertNotNil(documentID);

    // delete db
    [self deleteDatabase: self.db];

    // purge doc
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [self.db purgeDocumentWithID: documentID error: nil];
    }];
}

- (void) testDeletePurgedDocumentWithID {
    CBLDocument* document = [self generateDocumentWithID: nil];
    NSString* documentID = document.id;
    AssertNotNil(documentID);
    
    CBLDocument* anotherDBReturnedDocument = [self.db documentWithID: documentID];
    
    // Purge doc
    NSError* errorWhilePurging;
    Assert([self.db purgeDocumentWithID: documentID error: &errorWhilePurging]);
    AssertNil(errorWhilePurging);
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: documentID]);
    
    // Delete doc no-ops:
    NSError* errorWhileDeletion;
    Assert([self.db deleteDocument: document error: &errorWhileDeletion]);
    AssertNil(errorWhileDeletion);
    
    // Delete another DB returned document, no-ops:
    Assert([self.db deleteDocument: anotherDBReturnedDocument error: &errorWhileDeletion]);
    AssertNil(errorWhileDeletion);
    AssertEqual(self.db.count, 0u);
    
    anotherDBReturnedDocument = nil;
}

- (void) testPurgeDocumentWithIDOnADeletedDocument {
    CBLDocument* document = [self generateDocumentWithID: nil];
    NSString* documentID = document.id;
    AssertNotNil(documentID);
    
    // Delete document
    NSError* errorWhileDeletion;
    Assert([self.db deleteDocument: document error: &errorWhileDeletion]);
    AssertNil(errorWhileDeletion);
    
    NSError* documentReadError;
    CBLDocument* savedDocument = [[CBLDocument alloc] initWithDatabase: self.db
                                                            documentID: documentID
                                                        includeDeleted: YES
                                                                 error: &documentReadError];
    
    AssertNotNil(savedDocument);
    
    // Purge the deleted document
    NSError* errorWhilePurging;
    Assert([self.db purgeDocumentWithID: documentID error: &errorWhilePurging]);
    AssertNil(errorWhilePurging);
    
    savedDocument = [[CBLDocument alloc] initWithDatabase: self.db
                                               documentID: documentID
                                           includeDeleted: YES
                                                    error: &documentReadError];
    AssertNil(savedDocument);
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: documentID]);
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
    CBLDocument* doc = [self generateDocumentWithID: docID];
    
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
    CBLMutableDocument* doc = [self generateDocumentWithID: @"doc1"];
    NSData* data = [@"12345" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: data];
    [doc setBlob: blob forKey: @"data"];
    [self saveDocument: doc];
    
    // Get doc1 from the database:
    CBLDocument* doc1 = [self.db documentWithID: doc.id];
    
    // clsoe db
    [self closeDatabase: self.db];
    
    // Content should be accessible from doc:
    Assert([[doc valueForKey: @"data"] isKindOfClass: [CBLBlob class]]);
    CBLBlob* blob1 = [doc valueForKey: @"data"];
    AssertEqual(blob.length, blob1.length);
    AssertNotNil(blob1.content);
    AssertEqualObjects(blob.content, blob1.content);
    
    // Content shouldn't be accessible from doc1:
    Assert([[doc1 valueForKey: @"data"] isKindOfClass: [CBLBlob class]]);
    CBLBlob* blob2= [doc1 valueForKey: @"data"];
    AssertEqual(blob2.length, blob1.length);
    AssertNil(blob2.content);
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
        [self expectError: CBLErrorDomain code: CBLErrorTransactionNotClosed in: ^BOOL(NSError** error2) {
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

- (void) testCloseWithActiveLiveQueries {
    XCTestExpectation* change1 = [self expectationWithDescription: @"changes 1"];
    XCTestExpectation* change2 = [self expectationWithDescription: @"changes 2"];
    
    CBLQueryDataSource* ds = [CBLQueryDataSource database: self.db];
    
    CBLQuery* q1 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: ds];
    [q1 addChangeListener: ^(CBLQueryChange *ch) { [change1 fulfill]; }];
    
    CBLQuery* q2 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: ds];
    [q2 addChangeListener: ^(CBLQueryChange *ch) { [change2 fulfill]; }];
    
    [self waitForExpectations: @[change1, change2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)2);
    
    [self closeDatabase: self.db];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

#ifdef COUCHBASE_ENTERPRISE

- (void) testCloseWithActiveReplicators {
    [self openOtherDB];
    
    CBLDatabaseEndpoint* target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config =
        [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db target: target];
    config.continuous = YES;
    
    CBLReplicator* r1 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle1 = [self expectationWithDescription: @"Idle 1"];
    XCTestExpectation *stopped1 = [self expectationWithDescription: @"Stopped 1"];
    [self startReplicator: r1 idleExpectation: idle1 stoppedExpectation: stopped1];
    
    CBLReplicator* r2 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle2 = [self expectationWithDescription: @"Idle 2"];
    XCTestExpectation *stopped2 = [self expectationWithDescription: @"Stopped 2"];
    [self startReplicator: r2 idleExpectation: idle2 stoppedExpectation: stopped2];
    
    [self waitForExpectations: @[idle1, idle2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)2);
    
    [self closeDatabase: self.db];
    
    [self waitForExpectations: @[stopped1, stopped2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

- (void) testCloseWithActiveLiveQueriesAndReplicators {
    // Live Queries:
    
    XCTestExpectation* change1 = [self expectationWithDescription: @"changes 1"];
    XCTestExpectation* change2 = [self expectationWithDescription: @"changes 2"];
    
    CBLQueryDataSource* ds = [CBLQueryDataSource database: self.db];
    
    CBLQuery* q1 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: ds];
    [q1 addChangeListener: ^(CBLQueryChange *ch) { [change1 fulfill]; }];
    
    CBLQuery* q2 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: ds];
    [q2 addChangeListener: ^(CBLQueryChange *ch) { [change2 fulfill]; }];
    
    [self waitForExpectations: @[change1, change2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)2);
    
    // Replicators:
    
    [self openOtherDB];
    
    CBLDatabaseEndpoint* target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config =
        [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db target: target];
    config.continuous = YES;
    
    CBLReplicator* r1 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle1 = [self expectationWithDescription: @"Idle 1"];
    XCTestExpectation *stopped1 = [self expectationWithDescription: @"Stop 1"];
    [self startReplicator: r1 idleExpectation: idle1 stoppedExpectation: stopped1];
    
    CBLReplicator* r2 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle2 = [self expectationWithDescription: @"Idle 2"];
    XCTestExpectation *stopped2 = [self expectationWithDescription: @"Stoped 2"];
    [self startReplicator: r2 idleExpectation: idle2 stoppedExpectation: stopped2];
    
    [self waitForExpectations: @[idle1, idle2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)4); // total stoppables
    
    // Close database:
    [self closeDatabase: self.db];
    
    [self waitForExpectations: @[stopped1, stopped2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)0);
    AssertEqual([self.db activeStoppableCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

- (void) startReplicator: (CBLReplicator*)repl
         idleExpectation: (XCTestExpectation*)idleExp
      stoppedExpectation: (XCTestExpectation*)stopedExp
{
    [repl addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorIdle) { [idleExp fulfill]; }
        else if (change.status.activity == kCBLReplicatorStopped) { [stopedExp fulfill]; }
    }];
    
    [repl start];
}

#endif

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
    CBLDocument* doc = [self generateDocumentWithID: docID];
    
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
    CBLMutableDocument* doc = [self generateDocumentWithID: @"doc1"];
    NSData* data = [@"12345" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: data];
    [doc setBlob: blob forKey: @"data"];
    [self saveDocument: doc];
    
    // Get doc1 from the database:
    CBLDocument* doc1 = [self.db documentWithID: doc.id];
    
    // delete db
    [self deleteDatabase: self.db];
    
    // Content should be accessible from doc:
    Assert([[doc valueForKey: @"data"] isKindOfClass: [CBLBlob class]]);
    CBLBlob* blob1 = [doc valueForKey: @"data"];
    AssertEqual(blob.length, blob1.length);
    AssertNotNil(blob1.content);
    AssertEqualObjects(blob.content, blob1.content);
    
    
    // Content shouldn't be accessible from doc1:
    Assert([[doc1 valueForKey: @"data"] isKindOfClass: [CBLBlob class]]);
    CBLBlob* blob2= [doc1 valueForKey: @"data"];
    AssertEqual(blob2.length, blob1.length);
    AssertNil(blob2.content);
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
        [self expectError: CBLErrorDomain code: CBLErrorTransactionNotClosed in: ^BOOL(NSError** error2) {
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
    [self expectError: CBLErrorDomain code: CBLErrorBusy in: ^BOOL(NSError** error2) {
        return [self.db delete: error2];
    }];
    // 24 -> kC4ErrorBusy: Database is busy/locked
}

- (void) testDeleteWithActiveLiveQueries {
    XCTestExpectation* change1 = [self expectationWithDescription: @"changes 1"];
    XCTestExpectation* change2 = [self expectationWithDescription: @"changes 2"];
    
    CBLQueryDataSource* ds = [CBLQueryDataSource database: self.db];
    
    CBLQuery* q1 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: ds];
    [q1 addChangeListener: ^(CBLQueryChange *ch) { [change1 fulfill]; }];
    
    CBLQuery* q2 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: ds];
    [q2 addChangeListener: ^(CBLQueryChange *ch) { [change2 fulfill]; }];
    
    [self waitForExpectations: @[change1, change2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)2);
    
    [self deleteDatabase: self.db];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

#ifdef COUCHBASE_ENTERPRISE

- (void) testDeleteWithActiveReplicators {
    [self openOtherDB];
    
    CBLDatabaseEndpoint* target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config =
        [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db target: target];
    config.continuous = YES;
    
    CBLReplicator* r1 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle1 = [self expectationWithDescription: @"Idle 1"];
    XCTestExpectation *stopped1 = [self expectationWithDescription: @"Stopped 1"];
    [self startReplicator: r1 idleExpectation: idle1 stoppedExpectation: stopped1];
    
    CBLReplicator* r2 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle2 = [self expectationWithDescription: @"Idle 2"];
    XCTestExpectation *stopped2 = [self expectationWithDescription: @"Stopped 2"];
    [self startReplicator: r2 idleExpectation: idle2 stoppedExpectation: stopped2];
    
    [self waitForExpectations: @[idle1, idle2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)2);
    
    [self deleteDatabase: self.db];
    
    [self waitForExpectations: @[stopped1, stopped2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

- (void) testDeleteWithActiveLiveQueriesAndReplicators {
    [self openOtherDB];
    
    XCTestExpectation* change1 = [self expectationWithDescription: @"changes 1"];
    XCTestExpectation* change2 = [self expectationWithDescription: @"changes 2"];
    
    CBLQueryDataSource* ds = [CBLQueryDataSource database: self.db];
    
    CBLQuery* q1 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: ds];
    [q1 addChangeListener: ^(CBLQueryChange *ch) { [change1 fulfill]; }];
    
    CBLQuery* q2 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: ds];
    [q2 addChangeListener: ^(CBLQueryChange *ch) { [change2 fulfill]; }];
    
    [self waitForExpectations: @[change1, change2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)2);
    
    CBLDatabaseEndpoint* target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config =
        [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db target: target];
    config.continuous = YES;
    
    CBLReplicator* r1 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle1 = [self expectationWithDescription: @"Idle 1"];
    XCTestExpectation *stopped1 = [self expectationWithDescription: @"Stop 1"];
    [self startReplicator: r1 idleExpectation: idle1 stoppedExpectation: stopped1];
    
    CBLReplicator* r2 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle2 = [self expectationWithDescription: @"Idle 2"];
    XCTestExpectation *stopped2 = [self expectationWithDescription: @"Stoped 2"];
    [self startReplicator: r2 idleExpectation: idle2 stoppedExpectation: stopped2];
    
    [self waitForExpectations: @[idle1, idle2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)4); // total stoppables
    
    [self deleteDatabase: self.db];
    
    [self waitForExpectations: @[stopped1, stopped2] timeout: 5.0];
    
    AssertEqual([self.db activeStoppableCount], (unsigned long)0);
    AssertEqual([self.db activeStoppableCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

#endif

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
    [self expectError: CBLErrorDomain code: CBLErrorBusy in: ^BOOL(NSError** error2) {
        return [CBLDatabase deleteDatabase: @"db" inDirectory: nil error: error2];
    }];
}
#endif

- (void) testDeleteByStaticMethod {
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = self.directory;
    
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" config: config error: &error];
    AssertNotNil(db);
    AssertNil(error);
    
    NSString* path = db.path;
    
    // close db before delete
    [self closeDatabase: db];
    
    Assert([CBLDatabase deleteDatabase: @"db" inDirectory: self.directory error:&error]);
    AssertNil(error);
    AssertFalse([[NSFileManager defaultManager] fileExistsAtPath: path]);
}

- (void) testDeleteOpeningDBByStaticMethod {
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = self.directory;
    
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" config: config error: &error];
    AssertNotNil(db);
    AssertNil(error);
    
    [self expectError: CBLErrorDomain code: CBLErrorBusy in: ^BOOL(NSError** error2) {
        return [CBLDatabase deleteDatabase: @"db" inDirectory: self.directory error: error2];
    }];
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
    Assert([CBLDatabase deleteDatabase: @"notexistdb" inDirectory: self.directory error: &error]);
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
    AssertFalse([CBLDatabase databaseExists:@"db" inDirectory: self.directory]);
    
    // create db with custom directory
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = self.directory;
    
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" config: config error: &error];
    AssertNotNil(db);
    AssertNil(error);
    NSString* path = db.path;
    
    Assert([CBLDatabase databaseExists: @"db" inDirectory: self.directory]);
    
    // close db
    [self closeDatabase: db];
    
    Assert([CBLDatabase databaseExists: @"db" inDirectory: self.directory]);
    
    // delete db
    Assert([CBLDatabase deleteDatabase: @"db" inDirectory: self.directory error: &error]);
    AssertNil(error);
    AssertFalse([[NSFileManager defaultManager] fileExistsAtPath: path]);
    AssertFalse([CBLDatabase databaseExists: @"db" inDirectory: self.directory]);
}

#if TARGET_OS_IPHONE
- (void) testDatabaseExistsAgainstNonExistDBWithDefaultDir {
    AssertFalse([CBLDatabase databaseExists: @"nonexist" inDirectory: nil]);
}
#endif

- (void) testDatabaseExistsAgainstNonExistDB {
    AssertFalse([CBLDatabase databaseExists: @"nonexist" inDirectory: self.directory]);
}

- (void) testCompact {
    // Create docs:
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
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    Assert([_db compact: &error], @"Error when compacting the database");
    #pragma clang diagnostic pop
    
    // Delete all docs:
    for (CBLDocument* doc in docs) {
        CBLDocument* savedDoc = [_db documentWithID: doc.id];
        Assert([_db deleteDocument: savedDoc error: &error], @"Error when deleting doc: %@", error);
        AssertNil([_db documentWithID: doc.id]);
    }
    AssertEqual(_db.count, 0u);
    
    atts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: attsDir error: nil];
    AssertEqual(atts.count, 20u);
    
    // Compact:
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    Assert([_db compact: &error], @"Error when compacting the database: %@", error);
    #pragma clang diagnostic pop
    
    atts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: attsDir error: nil];
    AssertEqual(atts.count, 0u);
}

- (void) testPerformMaintenanceCompact {
    // Create docs:
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
    Assert([_db performMaintenance: kCBLMaintenanceTypeCompact error: &error],
           @"Error when compacting the database");
    
    // Delete all docs:
    for (CBLDocument* doc in docs) {
        CBLDocument* savedDoc = [_db documentWithID: doc.id];
        Assert([_db deleteDocument: savedDoc error: &error], @"Error when deleting doc: %@", error);
        AssertNil([_db documentWithID: doc.id]);
    }
    AssertEqual(_db.count, 0u);
    
    atts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: attsDir error: nil];
    AssertEqual(atts.count, 20u);
    
    // Compact:
    Assert([_db performMaintenance: kCBLMaintenanceTypeCompact error: &error],
           @"Error when compacting the database: %@", error);
    
    atts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: attsDir error: nil];
    AssertEqual(atts.count, 0u);
}

- (void) testPerformMaintenanceReindex {
    // Create docs:
    [self createDocs: 20];
    
    // Reindex when there is no index:
    NSError* error;
    Assert([_db performMaintenance: kCBLMaintenanceTypeReindex error: &error],
           @"Error when reindex the database: %@", error);
    
    // Create an index:
    CBLQueryExpression* key = [CBLQueryExpression property: @"key"];
    CBLValueIndexItem* keyItem = [CBLValueIndexItem expression: key];
    CBLValueIndex* keyIndex = [CBLIndexBuilder valueIndexWithItems: @[keyItem]];
    Assert([self.db createIndex: keyIndex withName: @"KeyIndex" error: &error],
           @"Error when creating value index: %@", error);
    AssertEqual(self.db.indexes.count, 1u);
    
    // Check if the index is used:
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: key]]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [key greaterThan: [CBLQueryExpression integer: 9]]];
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"USING INDEX KeyIndex"].location != NSNotFound);
    
    // Reindex:
    Assert([_db performMaintenance: kCBLMaintenanceTypeReindex error: &error],
           @"Error when reindexing the database: %@", error);
    
    // Check if the index is still there and used:
    AssertEqual(self.db.indexes.count, 1u);
    explain = [q explain: &error];
    Assert([explain rangeOfString: @"USING INDEX KeyIndex"].location != NSNotFound);
}

- (void) testPerformMaintenanceIntegrityCheck {
    // Create docs:
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
    
    // Integrity Check:
    Assert([_db performMaintenance: kCBLMaintenanceTypeIntegrityCheck error: &error],
           @"Error when performing integrity check on the database: %@", error);
    
    // Delete all docs:
    for (CBLDocument* doc in docs) {
        CBLDocument* savedDoc = [_db documentWithID: doc.id];
        Assert([_db deleteDocument: savedDoc error: &error], @"Error when deleting doc: %@", error);
        AssertNil([_db documentWithID: doc.id]);
    }
    AssertEqual(_db.count, 0u);
    
    // Integrity Check:
    Assert([_db performMaintenance: kCBLMaintenanceTypeIntegrityCheck error: &error],
           @"Error when performing integrity check on the database: %@", error);
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
    CBLQuery* query = [CBLQueryBuilder select: @[S_DOCID]
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

- (void) testCopyToNonExistingDirectory {
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
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] initWithConfig: _db.config];
    config.directory = [config.directory stringByAppendingPathComponent: @"nonexistent"];
    
    // Ensure no directory:
    NSString* dir = config.directory;
    [[NSFileManager defaultManager] removeItemAtPath: dir error: nil];
    
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
    CBLQuery* query = [CBLQueryBuilder select: @[S_DOCID]
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
    Assert([[NSFileManager defaultManager] removeItemAtPath: dir error: nil]);
}

- (void) testCopyToExistingDatabase {
    NSString* dbName = @"nudb";
    
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] initWithConfig: _db.config];
    config.directory = [config.directory stringByAppendingPathComponent: @"existent"];
    
    NSError* error;
    CBLDatabase* nudb = [[CBLDatabase alloc] initWithName: dbName config: config  error: &error];
    Assert(nudb, @"Cannot open the new database: %@", error);
    
    [self expectError: NSPOSIXErrorDomain code: EEXIST in: ^BOOL(NSError** error2) {
        return [CBLDatabase copyFromPath: _db.path toDatabase: dbName withConfig: config error: error2];
    }];
    
    // Clean up:
    Assert([nudb close: nil]);
    Assert([[NSFileManager defaultManager] removeItemAtPath: config.directory error: nil]);
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
    
    CBLValueIndex* index1 = [CBLIndexBuilder valueIndexWithItems: @[fNameItem, lNameItem]];
    Assert([self.db createIndex: index1 withName: @"index1" error: &error],
           @"Error when creating value index: %@", error);
    
    // Create FTS index:
    CBLFullTextIndexItem* detailItem = [CBLFullTextIndexItem property: @"detail"];
    CBLFullTextIndex* index2 = [CBLIndexBuilder fullTextIndexWithItems: @[detailItem]];
    Assert([self.db createIndex: index2 withName: @"index2" error: &error],
           @"Error when creating FTS index without options: %@", error);
    
    CBLFullTextIndexItem* detailItem2 = [CBLFullTextIndexItem property: @"es-detail"];
    CBLFullTextIndex* index3 = [CBLIndexBuilder fullTextIndexWithItems: @[detailItem2]];
    index3.language = @"es";
    index3.ignoreAccents = YES;
    
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
    CBLValueIndex* index = [CBLIndexBuilder valueIndexWithItems: @[item]];
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
    CBLValueIndex* fNameIndex = [CBLIndexBuilder valueIndexWithItems: @[fNameItem]];
    Assert([self.db createIndex: fNameIndex withName: @"myindex" error: &error],
           @"Error when creating value index: %@", error);

    // Create value index with last name:
    CBLValueIndexItem* lNameItem = [CBLValueIndexItem expression: lName];
    CBLValueIndex* lNameIndex = [CBLIndexBuilder valueIndexWithItems: @[lNameItem]];
    Assert([self.db createIndex: lNameIndex withName: @"myindex" error: &error],
           @"Error when creating value index: %@", error);
    
    // Check:
    NSArray* names = self.db.indexes;
    AssertEqual(names.count, 1u);
    AssertEqualObjects(names, (@[@"myindex"]));
    
    // Create FTS index:
    CBLFullTextIndexItem* detailItem = [CBLFullTextIndexItem property: @"detail"];
    CBLFullTextIndex* detailIndex = [CBLIndexBuilder fullTextIndexWithItems: @[detailItem]];
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
    CBLValueIndex* index1 = [CBLIndexBuilder valueIndexWithItems: @[fNameItem, lNameItem]];
    Assert([self.db createIndex: index1 withName: @"index1" error: &error],
           @"Error when creating value index: %@", error);
    
    // Create FTS index:
    CBLFullTextIndexItem* detailItem = [CBLFullTextIndexItem property: @"detail"];
    CBLFullTextIndex* index2 = [CBLIndexBuilder fullTextIndexWithItems: @[detailItem]];
    Assert([self.db createIndex: index2 withName: @"index2" error: &error],
           @"Error when creating FTS index without options: %@", error);
    
    CBLFullTextIndexItem* detail2Item = [CBLFullTextIndexItem property: @"es-detail"];
    CBLFullTextIndex* index3 = [CBLIndexBuilder fullTextIndexWithItems: @[detail2Item]];
    index3.language = @"es";
    index3.ignoreAccents = YES;
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
