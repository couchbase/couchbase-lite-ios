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
#import "CBLScope.h"
#import "CollectionUtils.h"
#import "CBLQueryFullTextIndexExpressionProtocol.h"

@interface DatabaseTest : CBLTestCase
@end

@implementation DatabaseTest

// Helper method to save n number of docs
- (NSArray*) createDocs: (int)n {
    NSMutableArray* docs = [NSMutableArray arrayWithCapacity: n];
    for(int i = 0; i < n; i++){
        CBLMutableDocument* doc = [self createDocument: [NSString stringWithFormat: @"doc_%03d", i]];
        [doc setValue: @(i) forKey:@"key"];
        [self saveDocument: doc collection: self.defaultCollection];
        [docs addObject: doc];
    }
    AssertEqual(n, (long) self.defaultCollection.count);
    return docs;
}

// check the given collection list with the expected collection name list
- (void) checkCollections: (NSArray<CBLCollection*>*)collections
       expCollectionNames: (NSArray<NSString*>*)names {
    AssertEqual(collections.count, names.count, @"Collection count mismatch");
    for (CBLCollection* c in collections) {
        Assert([names containsObject: c.name], @"%@ is missing", c.name);
    }
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
    
    // delete database
    [self deleteDatabase: db];
}

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
    
    // delete database
    [self deleteDatabase: db];
}

- (void) testCreateWithSpecialCharacterDBNames {
    // create db with default configuration
    NSError* error;
    CBLDatabase* db = [self openDBNamed: @"`~@#$%^&*()_+{}|\\][=-.,<>?\":;'" error: &error];
    AssertNil(error);
    AssertNotNil(db, @"Couldn't open db: %@", db.name);
    AssertEqualObjects(db.name, @"`~@#$%^&*()_+{}|\\][=-.,<>?\":;'");
    Assert([db.path.lastPathComponent hasSuffix: @".cblite2"]);
    
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

    // delete database
    [self deleteDatabase: db];
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
    NSError* error;
    // store doc with blob
    CBLMutableDocument* doc = [self generateDocumentWithID: @"doc1"];
    NSData* data = [@"12345" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: data];
    [doc setBlob: blob forKey: @"data"];
    [self saveDocument: doc collection: self.defaultCollection];
    
    // Get doc1 from the database:
    CBLDocument* doc1 = [self.defaultCollection documentWithID: doc.id error: &error];
    
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
    [self closeDatabase: self.db];
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
    
    CBLQuery* q1 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: kDATA_SRC_DB];
    [q1 addChangeListener: ^(CBLQueryChange *ch) { [change1 fulfill]; }];
    
    CBLQuery* q2 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: kDATA_SRC_DB];
    [q2 addChangeListener: ^(CBLQueryChange *ch) { [change2 fulfill]; }];
    
    [self waitForExpectations: @[change1, change2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)2);
    
    [self closeDatabase: self.db];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

#ifdef COUCHBASE_ENTERPRISE

- (void) testCloseWithActiveReplicators {
    [self openOtherDB];
    
    CBLDatabaseEndpoint* target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLCollectionConfiguration* collectionConfig = [[CBLCollectionConfiguration alloc] initWithCollection: self.defaultCollection];
    CBLReplicatorConfiguration* config =
        [[CBLReplicatorConfiguration alloc] initWithCollections: @[collectionConfig] target: target];
    config.continuous = YES;
    
    config.replicatorType = kCBLReplicatorTypePush;
    CBLReplicator* r1 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle1 = [self allowOverfillExpectationWithDescription: @"Idle 1"];
    XCTestExpectation *stopped1 = [self expectationWithDescription: @"Stopped 1"];
    [self startReplicator: r1 idleExpectation: idle1 stoppedExpectation: stopped1];
    
    config.replicatorType = kCBLReplicatorTypePull;
    CBLReplicator* r2 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle2 = [self allowOverfillExpectationWithDescription: @"Idle 2"];
    XCTestExpectation *stopped2 = [self expectationWithDescription: @"Stopped 2"];
    [self startReplicator: r2 idleExpectation: idle2 stoppedExpectation: stopped2];
    
    [self waitForExpectations: @[idle1, idle2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)2);
    
    [self closeDatabase: self.db];
    
    [self waitForExpectations: @[stopped1, stopped2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

- (void) testCloseWithActiveLiveQueriesAndReplicators {
    // Live Queries:
    
    XCTestExpectation* change1 = [self expectationWithDescription: @"changes 1"];
    XCTestExpectation* change2 = [self expectationWithDescription: @"changes 2"];
    
    CBLQuery* q1 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: kDATA_SRC_DB];
    [q1 addChangeListener: ^(CBLQueryChange *ch) { [change1 fulfill]; }];
    
    CBLQuery* q2 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: kDATA_SRC_DB];
    [q2 addChangeListener: ^(CBLQueryChange *ch) { [change2 fulfill]; }];
    
    [self waitForExpectations: @[change1, change2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)2);
    
    // Replicators:
    
    [self openOtherDB];
    
    CBLDatabaseEndpoint* target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLCollectionConfiguration* collectionConfig = [[CBLCollectionConfiguration alloc] initWithCollection: self.defaultCollection];
    CBLReplicatorConfiguration* config =
        [[CBLReplicatorConfiguration alloc] initWithCollections: @[collectionConfig] target: target];
    config.continuous = YES;
    
    config.replicatorType = kCBLReplicatorTypePush;
    CBLReplicator* r1 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle1 = [self allowOverfillExpectationWithDescription: @"Idle 1"];
    XCTestExpectation *stopped1 = [self expectationWithDescription: @"Stop 1"];
    [self startReplicator: r1 idleExpectation: idle1 stoppedExpectation: stopped1];
    
    config.replicatorType = kCBLReplicatorTypePull;
    CBLReplicator* r2 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle2 = [self allowOverfillExpectationWithDescription: @"Idle 2"];
    XCTestExpectation *stopped2 = [self expectationWithDescription: @"Stoped 2"];
    [self startReplicator: r2 idleExpectation: idle2 stoppedExpectation: stopped2];
    
    [self waitForExpectations: @[idle1, idle2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)4); // total services
    
    // Close database:
    [self closeDatabase: self.db];
    
    [self waitForExpectations: @[stopped1, stopped2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)0);
    AssertEqual([self.db activeServiceCount], (unsigned long)0);
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
    AssertNil(error);
    
    [self expectError: CBLErrorDomain code: CBLErrorNotOpen in: ^BOOL(NSError** err) {
        return [self.db delete: err];
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
    NSError* error;
    // store doc with blob
    CBLMutableDocument* doc = [self generateDocumentWithID: @"doc1"];
    NSData* data = [@"12345" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: data];
    [doc setBlob: blob forKey: @"data"];
    [self saveDocument: doc collection: self.defaultCollection];
    
    // Get doc1 from the database:
    CBLDocument* doc1 = [self.defaultCollection documentWithID: doc.id error: &error];
    
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
    
    CBLQuery* q1 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: kDATA_SRC_DB];
    [q1 addChangeListener: ^(CBLQueryChange *ch) { [change1 fulfill]; }];
    
    CBLQuery* q2 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: kDATA_SRC_DB];
    [q2 addChangeListener: ^(CBLQueryChange *ch) { [change2 fulfill]; }];
    
    [self waitForExpectations: @[change1, change2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)2);
    
    [self deleteDatabase: self.db];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

#ifdef COUCHBASE_ENTERPRISE

- (void) testDeleteWithActiveReplicators {
    [self openOtherDB];
    
    CBLDatabaseEndpoint* target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLCollectionConfiguration* collectionConfig = [[CBLCollectionConfiguration alloc] initWithCollection: self.defaultCollection];
    CBLReplicatorConfiguration* config =
        [[CBLReplicatorConfiguration alloc] initWithCollections: @[collectionConfig] target: target];
    config.continuous = YES;
    
    config.replicatorType = kCBLReplicatorTypePush;
    CBLReplicator* r1 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle1 = [self allowOverfillExpectationWithDescription: @"Idle 1"];
    XCTestExpectation *stopped1 = [self expectationWithDescription: @"Stopped 1"];
    [self startReplicator: r1 idleExpectation: idle1 stoppedExpectation: stopped1];
    
    config.replicatorType = kCBLReplicatorTypePull;
    CBLReplicator* r2 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle2 = [self allowOverfillExpectationWithDescription: @"Idle 2"];
    XCTestExpectation *stopped2 = [self expectationWithDescription: @"Stopped 2"];
    [self startReplicator: r2 idleExpectation: idle2 stoppedExpectation: stopped2];
    
    [self waitForExpectations: @[idle1, idle2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)2);
    
    [self deleteDatabase: self.db];
    
    [self waitForExpectations: @[stopped1, stopped2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

- (void) testDeleteWithActiveLiveQueriesAndReplicators {
    [self openOtherDB];
    
    XCTestExpectation* change1 = [self expectationWithDescription: @"changes 1"];
    XCTestExpectation* change2 = [self expectationWithDescription: @"changes 2"];
    
    CBLQuery* q1 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: kDATA_SRC_DB];
    [q1 addChangeListener: ^(CBLQueryChange *ch) { [change1 fulfill]; }];
    
    CBLQuery* q2 = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]] from: kDATA_SRC_DB];
    [q2 addChangeListener: ^(CBLQueryChange *ch) { [change2 fulfill]; }];
    
    [self waitForExpectations: @[change1, change2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)2);
    
    CBLDatabaseEndpoint* target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLCollectionConfiguration* collectionConfig = [[CBLCollectionConfiguration alloc] initWithCollection: self.defaultCollection];
    CBLReplicatorConfiguration* config =
        [[CBLReplicatorConfiguration alloc] initWithCollections: @[collectionConfig] target: target];
    config.continuous = YES;
    
    config.replicatorType = kCBLReplicatorTypePush;
    CBLReplicator* r1 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle1 = [self allowOverfillExpectationWithDescription: @"Idle 1"];
    XCTestExpectation *stopped1 = [self expectationWithDescription: @"Stop 1"];
    [self startReplicator: r1 idleExpectation: idle1 stoppedExpectation: stopped1];
    
    config.replicatorType = kCBLReplicatorTypePull;
    CBLReplicator* r2 = [[CBLReplicator alloc] initWithConfig: config];
    XCTestExpectation *idle2 = [self allowOverfillExpectationWithDescription: @"Idle 2"];
    XCTestExpectation *stopped2 = [self expectationWithDescription: @"Stoped 2"];
    [self startReplicator: r2 idleExpectation: idle2 stoppedExpectation: stopped2];
    
    [self waitForExpectations: @[idle1, idle2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)4); // total services
    
    [self deleteDatabase: self.db];
    
    [self waitForExpectations: @[stopped1, stopped2] timeout: kExpTimeout];
    
    AssertEqual([self.db activeServiceCount], (unsigned long)0);
    AssertEqual([self.db activeServiceCount], (unsigned long)0);
    Assert([self.db isClosedLocked]);
}

#endif

#pragma mark - Delete Database (static)

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

- (void) testPerformMaintenanceCompact {
    NSError* error;
    // Create docs:
    NSArray* docs = [self createDocs: 20];
    
    // Update each doc 25 times:
    [_db inBatch: &error usingBlock: ^{
        for (CBLDocument* doc in docs) {
            for (NSUInteger i = 0; i < 25; i++) {
                CBLMutableDocument* mDoc = [doc toMutable];
                [mDoc setValue: @(i) forKey: @"number"];
                [self saveDocument: mDoc collection: self.defaultCollection];
            }
        }
    }];
    
    // Add each doc with a blob object:
    for (CBLDocument* doc in docs) {
        CBLMutableDocument* mDoc = [[self.defaultCollection documentWithID: doc.id error: &error] toMutable];
        NSData* content = [doc.id dataUsingEncoding: NSUTF8StringEncoding];
        CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
        [mDoc setValue: blob forKey: @"blob"];
        [self saveDocument: mDoc collection: self.defaultCollection];
    }
    
    AssertEqual(self.defaultCollection.count, 20u);
    
    NSString* attsDir = [_db.path stringByAppendingPathComponent:@"Attachments"];
    NSArray* atts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: attsDir error: nil];
    AssertEqual(atts.count, 20u);
    
    // Compact:
    Assert([_db performMaintenance: kCBLMaintenanceTypeCompact error: &error],
           @"Error when compacting the database");
    
    // Delete all docs:
    for (CBLDocument* doc in docs) {
        CBLDocument* savedDoc = [self.defaultCollection documentWithID: doc.id error: &error];
        Assert([self.defaultCollection deleteDocument: savedDoc error: &error], @"Error when deleting doc: %@", error);
        AssertNil([self.defaultCollection documentWithID: doc.id error: &error]);
    }
    AssertEqual(self.defaultCollection.count, 0u);
    
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
    Assert([self.defaultCollection createIndex: keyIndex name: @"KeyIndex" error: &error], @"Error when creating value index: %@", error);
    AssertEqual([self.defaultCollection indexes: &error].count, 1u);
    
    // Check if the index is used:
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: key]]
                                     from: kDATA_SRC_DB
                                    where: [key greaterThan: [CBLQueryExpression integer: 9]]];
    
    Assert([self isUsingIndexNamed: @"KeyIndex" forQuery: q]);
    
    // Reindex:
    Assert([_db performMaintenance: kCBLMaintenanceTypeReindex error: &error],
           @"Error when reindexing the database: %@", error);
    
    // Check if the index is still there and used:
    AssertEqual([self.defaultCollection indexes: &error].count, 1u);
    Assert([self isUsingIndexNamed: @"KeyIndex" forQuery: q]);
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
                [self saveDocument: mDoc collection: self.defaultCollection];
            }
        }
    }];
    
    // Add each doc with a blob object:
    for (CBLDocument* doc in docs) {
        CBLMutableDocument* mDoc = [[self.defaultCollection documentWithID: doc.id error: &error] toMutable];
        NSData* content = [doc.id dataUsingEncoding: NSUTF8StringEncoding];
        CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
        [mDoc setValue: blob forKey: @"blob"];
        [self saveDocument: mDoc collection: self.defaultCollection];
    }
    
    AssertEqual(self.defaultCollection.count, 20u);
    
    NSString* attsDir = [_db.path stringByAppendingPathComponent:@"Attachments"];
    NSArray* atts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: attsDir error: nil];
    AssertEqual(atts.count, 20u);
    
    // Integrity Check:
    Assert([_db performMaintenance: kCBLMaintenanceTypeIntegrityCheck error: &error],
           @"Error when performing integrity check on the database: %@", error);
    
    // Delete all docs:
    for (CBLDocument* doc in docs) {
        CBLDocument* savedDoc = [self.defaultCollection documentWithID: doc.id error: &error];
        Assert([self.defaultCollection deleteDocument: savedDoc error: &error], @"Error when deleting doc: %@", error);
        AssertNil([self.defaultCollection documentWithID: doc.id error: &error]);
    }
    AssertEqual(self.defaultCollection.count, 0u);
    
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
        
        [self saveDocument: doc collection: self.defaultCollection];
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
    CBLCollection* nudbCollection = [nudb defaultCollection: &error];
    Assert(nudb, @"Cannot open the new database: %@", error);
    AssertEqual(nudbCollection.count, 10u);
    
    CBLQueryExpression* DOCID = [CBLQueryMeta id];
    CBLQuerySelectResult* S_DOCID = [CBLQuerySelectResult expression: DOCID];
    CBLQuery* query = [CBLQueryBuilder select: @[S_DOCID]
                                         from: [CBLQueryDataSource collection: nudbCollection]];
    CBLQueryResultSet* rs = [query execute: &error];
    
    for (CBLQueryResult* r in rs) {
        NSString* docID = [r stringAtIndex: 0];
        Assert(docID);
        
        CBLDocument* doc = [nudbCollection documentWithID: docID error: &error];
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
        
        [self saveDocument: doc collection: self.defaultCollection];
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
    CBLCollection* nudbCollection = [nudb defaultCollection: &error];
    Assert(nudb, @"Cannot open the new database: %@", error);
    AssertEqual(nudbCollection.count, 10u);
    
    CBLQueryExpression* DOCID = [CBLQueryMeta id];
    CBLQuerySelectResult* S_DOCID = [CBLQuerySelectResult expression: DOCID];
    CBLQuery* query = [CBLQueryBuilder select: @[S_DOCID]
                                         from: [CBLQueryDataSource collection: nudbCollection]];
    CBLQueryResultSet* rs = [query execute: &error];
    
    for (CBLQueryResult* r in rs) {
        NSString* docID = [r stringAtIndex: 0];
        Assert(docID);
        
        CBLDocument* doc = [nudbCollection documentWithID: docID error: &error];
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
        return [CBLDatabase copyFromPath: self->_db.path toDatabase: dbName withConfig: config error: error2];
    }];
    
    // Clean up:
    Assert([nudb close: nil]);
    Assert([[NSFileManager defaultManager] removeItemAtPath: config.directory error: nil]);
}

- (void) testCreateCollectionIndex {
    NSError* error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertNil(error);
    
    // Precheck:
    NSArray* indexes = [colA indexes: &error];
    Assert(indexes);
    AssertNil(error);
    AssertEqual(indexes.count, 0u);
    
    // Create value index:
    CBLQueryExpression* fName = [CBLQueryExpression property: @"firstName"];
    CBLQueryExpression* lName = [CBLQueryExpression property: @"lastName"];
    
    CBLValueIndexItem* fNameItem = [CBLValueIndexItem expression: fName];
    CBLValueIndexItem* lNameItem = [CBLValueIndexItem expression: lName];
    
    CBLValueIndex* index1 = [CBLIndexBuilder valueIndexWithItems: @[fNameItem, lNameItem]];
    Assert([colA createIndex: index1 name: @"index1" error: &error],
           @"Error when creating value index: %@", error);
    
    // Create FTS index:
    CBLFullTextIndexItem* detailItem = [CBLFullTextIndexItem property: @"detail"];
    CBLFullTextIndex* index2 = [CBLIndexBuilder fullTextIndexWithItems: @[detailItem]];
    Assert([colA createIndex: index2 name: @"index2" error: &error],
           @"Error when creating FTS index without options: %@", error);
    
    CBLFullTextIndexItem* detailItem2 = [CBLFullTextIndexItem property: @"es-detail"];
    CBLFullTextIndex* index3 = [CBLIndexBuilder fullTextIndexWithItems: @[detailItem2]];
    index3.language = @"es";
    index3.ignoreAccents = YES;
    
    Assert([colA createIndex: index3 name: @"index3" error: &error],
           @"Error when creating FTS index with options: %@", error);
    
    NSArray* names = [colA indexes: &error];
    AssertNil(error);
    AssertEqual(names.count, 3u);
    AssertEqualObjects(names, (@[@"index1", @"index2", @"index3"]));
}

- (void) testFullTextIndexExpression {
    NSError* error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertNil(error);
    
    // Create FTS index:
    CBLFullTextIndexItem* detailItem = [CBLFullTextIndexItem property: @"passage"];
    CBLFullTextIndex* index2 = [CBLIndexBuilder fullTextIndexWithItems: @[detailItem]];
    Assert([colA createIndex: index2 name: @"passageIndex" error: &error],
           @"Error when creating FTS index without options: %@", error);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setString: @"The boy said to the child, 'Mommy, I want a cat.'" forKey: @"passage"];
    [self saveDocument: doc collection: colA];
    
    doc = [self createDocument: @"doc2"];
    [doc setString: @"The mother replied 'No, you already have too many cats.'" forKey: @"passage"];
    [self saveDocument: doc collection: colA];
    
    id plainIndex = [CBLQueryExpression fullTextIndex: @"passageIndex"];
    id qualifiedIndex = [[CBLQueryExpression fullTextIndex: @"passageIndex"] from: @"colAa"];
    
    CBLQuerySelectResult* S_DOCID = [CBLQuerySelectResult expression: [CBLQueryMeta id]];
    CBLQuery* query = [CBLQueryBuilder select: @[S_DOCID]
                                         from: [CBLQueryDataSource collection: colA as: @"colAa"]
                                        where: [CBLQueryFullTextFunction matchWithIndex: plainIndex query: @"cat"]];
    
    uint64_t numRows = [self verifyQuery: query randomAccess: NO test: ^(uint64_t n, CBLQueryResult *result) {
        AssertEqualObjects([result stringAtIndex: 0], ($sprintf(@"doc%llu", n)));
    }];
    AssertEqual(numRows, 2);
    
    query = [CBLQueryBuilder select: @[S_DOCID]
                               from: [CBLQueryDataSource collection: colA as: @"colAa"]
                              where: [CBLQueryFullTextFunction matchWithIndex: qualifiedIndex query: @"cat"]];
    numRows = [self verifyQuery: query randomAccess: NO test: ^(uint64_t n, CBLQueryResult *result) {
        AssertEqualObjects([result stringAtIndex: 0], ($sprintf(@"doc%llu", n)));
    }];
    AssertEqual(numRows, 2);
}

- (void) testFTSQueryWithJoin {
    NSError* error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA" scope: @"scopeA" error: &error];
    AssertNil(error);
    
    // Create FTS index:
    CBLFullTextIndexItem* detailItem = [CBLFullTextIndexItem property: @"passage"];
    CBLFullTextIndex* index2 = [CBLIndexBuilder fullTextIndexWithItems: @[detailItem]];
    Assert([colA createIndex: index2 name: @"passageIndex" error: &error],
           @"Error when creating FTS index without options: %@", error);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setString: @"The boy said to the child, 'Mommy, I want a cat.'" forKey: @"passage"];
    [doc setString: @"en" forKey: @"lang"];
    [self saveDocument: doc collection: colA];
    
    doc = [self createDocument: @"doc2"];
    [doc setString: @"The mother replied 'No, you already have too many cats.'" forKey: @"passage"];
    [doc setString: @"en" forKey: @"lang"];
    [self saveDocument: doc collection: colA];
    
    
    id qualifiedIndex = [[CBLQueryExpression fullTextIndex: @"passageIndex"] from: @"main"];
    
    CBLQuerySelectResult* S_DOCID = [CBLQuerySelectResult expression: [CBLQueryMeta idFrom: @"main"]];
    CBLQueryJoin* join = [CBLQueryJoin leftJoin: [CBLQueryDataSource collection: colA as: @"secondary"]
                                             on: [[CBLQueryExpression property: @"lang" from: @"main"] equalTo:
                                                  [CBLQueryExpression property: @"lang" from: @"secondary"]]];
    
    id plainIndex = [CBLQueryExpression fullTextIndex: @"passageIndex"];
    CBLQuery* query = [CBLQueryBuilder select: @[S_DOCID]
                                         from: [CBLQueryDataSource collection: colA as: @"main"]
                                         join: @[join]
                                        where: [CBLQueryFullTextFunction matchWithIndex: plainIndex query: @"cat"]
                                      orderBy: @[[[CBLQueryOrdering expression: [CBLQueryMeta idFrom: @"main"]] ascending]]];

    uint64_t numRows = [self verifyQuery: query randomAccess: NO test: ^(uint64_t n, CBLQueryResult *result) {
        Assert([[result stringAtIndex: 0] hasPrefix: @"doc"]);
    }];
    AssertEqual(numRows, 4);
    
    query = [CBLQueryBuilder select: @[S_DOCID]
                               from: [CBLQueryDataSource collection: colA as: @"main"]
                               join: @[join]
                              where: [CBLQueryFullTextFunction matchWithIndex: qualifiedIndex query: @"cat"]
                            orderBy: @[[[CBLQueryOrdering expression: [CBLQueryMeta idFrom: @"main"]] ascending]]];
    
    numRows = [self verifyQuery: query randomAccess: NO test: ^(uint64_t n, CBLQueryResult *result) {
        Assert([[result stringAtIndex: 0] hasPrefix: @"doc"]);
    }];
    AssertEqual(numRows, 4);
}

- (void) testCreateCollection {
    // Verify collections in Default Scope
    NSError* error = nil;
    NSArray<CBLCollection*>* collections = [self.db collections: kCBLDefaultScopeName error: &error];
    AssertEqual(collections.count, 1);
    AssertEqualObjects(collections[0].name, kCBLDefaultCollectionName);
    AssertEqualObjects(collections[0].scope.name, kCBLDefaultScopeName);
    
    // Create in Default Scope
    CBLCollection* c = [self.db createCollectionWithName: @"collection1" scope: nil error: &error];
    AssertNotNil(c);
    
    // verify
    collections = [self.db collections: kCBLDefaultScopeName error: &error];
    AssertEqual(collections.count, 2); // 'collection1', '_default'
    Assert([(@[@"collection1", @"_default"]) containsObject: collections[0].name]);
    Assert([(@[@"collection1", @"_default"]) containsObject: collections[1].name]);
    
    // Create in Custom Scope
    c = [self.db createCollectionWithName: @"collection2" scope: @"scope1" error: &error];
    AssertNotNil(c);
    
    // verify
    collections = [self.db collections: @"scope1" error: &error];
    AssertEqual(collections.count, 1);
    AssertEqualObjects(collections[0].name, @"collection2");
}

- (void) testDeleteCollection {
    NSError* error = nil;
    CBLCollection* c1 = [self.db createCollectionWithName: @"collection1" scope: nil error: &error];
    AssertNotNil(c1);
    CBLCollection* c2 = [self.db createCollectionWithName: @"collection2" scope: nil error: &error];
    AssertNotNil(c2);
    NSArray<CBLCollection*>* collections = [self.db collections: kCBLDefaultScopeName error: &error];
    AssertEqual(collections.count, 3);
    
    // delete without scope
    Assert([self.db deleteCollectionWithName: c1.name scope: nil error: &error]);
    collections = [self.db collections: kCBLDefaultScopeName error: &error];
    AssertEqual(collections.count, 2);
    
    // delete with default scope
    Assert([self.db deleteCollectionWithName: c2.name scope: kCBLDefaultScopeName error: &error]);
    collections = [self.db collections: kCBLDefaultScopeName error: &error];
    AssertEqual(collections.count, 1);
    AssertEqualObjects(collections[0].name, kCBLDefaultCollectionName);
}

- (void) testCreateDuplicateCollection {
    // Create in Default Scope
    NSError* error = nil;
    CBLCollection* c1 = [self.db createCollectionWithName: @"collection1" scope: nil error: &error];
    AssertNotNil(c1);
    CBLCollection* c2 = [self.db createCollectionWithName: @"collection1" scope: nil error: &error];
    AssertNotNil(c2);
    
    // verify no duplicate is created.
    NSArray<CBLCollection*>* collections = [self.db collections: kCBLDefaultScopeName error: &error];
    [self checkCollections: collections expCollectionNames: @[@"collection1", @"_default"]];
    
    // Create in Custom Scope
    c1 = [self.db createCollectionWithName: @"collection2" scope: @"scope1" error: &error];
    AssertNotNil(c1);
    c2 = [self.db createCollectionWithName: @"collection2" scope: @"scope1" error: &error];
    AssertNotNil(c2);
    
    // verify no duplicate is created.
    collections = [self.db collections: @"scope1" error: &error];
    [self checkCollections: collections expCollectionNames: @[@"collection2"]];
}

- (void) testEmptyCollection {
    NSError* error = nil;
    AssertNil([self.db collectionWithName: @"dummy" scope: nil error: &error]);
    AssertNil(error);
    
    AssertNil([self.db collectionWithName: @"dummy" scope: kCBLDefaultScopeName error: &error]);
    AssertNil(error);
    
    AssertNil([self.db collectionWithName: @"dummy" scope: @"scope1" error: &error]);
    AssertNil(error);
}

#pragma mark - Collection Indexable

- (void) testCollectionIndex {
    NSError* error = nil;
    CBLCollection* c = [self.db createCollectionWithName: @"collection1" scope: nil error: &error];
    
    // CREATE INDEX
    // index1
    CBLValueIndexConfiguration* config = [[CBLValueIndexConfiguration alloc] initWithExpression: @[@"firstName", @"lastName"]];
    Assert([c createIndexWithName: @"index1" config: config error: &error]);
    
    
    // index2
    CBLFullTextIndexConfiguration* config2 = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"detail"]
                                                                                         ignoreAccents: NO
                                                                                              language: nil];
    Assert([c createIndexWithName: @"index2" config: config2 error: &error]);
    
    // index3
    CBLFullTextIndexConfiguration* config3 = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"es_detail"]
                                                                                         ignoreAccents: YES
                                                                                              language: @"es"];
    Assert([c createIndexWithName: @"index3" config: config3 error: &error]);
    
    // same index twice!
    CBLFullTextIndexConfiguration* config4 = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"detail"]
                                                                                         ignoreAccents: NO
                                                                                              language: nil];
    Assert([c createIndexWithName: @"index2" config: config4 error: &error]);
    
    // index4: use backtick in case of property with hyphen
    CBLFullTextIndexConfiguration* config5 = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"`es-detail`"]
                                                                                         ignoreAccents: YES
                                                                                              language: @"es"];
    Assert([c createIndexWithName: @"index4" config: config5 error: &error]);
    
    // verify indexes returning them
    NSArray* names = [c indexes: &error];
    AssertEqual(names.count, 4u);
    AssertEqualObjects(names, (@[@"index1", @"index2", @"index3", @"index4"]));
    
    // DELETE INDEX
    Assert([c deleteIndexWithName: @"index1" error: &error]);
    Assert([c deleteIndexWithName: @"index2" error: &error]);
    names = [c indexes: &error];
    AssertEqual(names.count, 2u);
    AssertEqualObjects(names, (@[@"index3", @"index4"]));
}

#pragma mark - Full Sync Option

/** 
 Test Spec v1.0.0: https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0003-SQLite-Options.md
 */

/**
 1. TestSQLiteFullSyncConfig
 Description
    Test that the FullSync default is as expected and that it's setter and getter work.
 Steps
    1. Create a DatabaseConfiguration object.
    2. Get and check the value of the FullSync property: it should be false.
    3. Set the FullSync property true.
    4. Get the config FullSync property and verify that it is true.
    5. Set the FullSync property false.
    6. Get the config FullSync property and verify that it is false.
 */
- (void) testSQLiteFullSyncConfig {
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    AssertFalse(config.fullSync);
    
    config.fullSync = true;
    Assert(config.fullSync);
    
    config.fullSync = false;
    AssertFalse(config.fullSync);
}

/**
 2. TestDBWithFullSync
 Description
    Test that a Database respects the FullSync property.
 Steps
    1. Create a DatabaseConfiguration object and set Full Sync false.
    2. Create a database with the config.
    3. Get the configuration object from the Database and verify that FullSync is false.
    4. Use c4db_config2 (perhaps necessary only for this test) to confirm that its config does not contain the kC4DB_DiskSyncFull flag.
    5. Set the config's FullSync property true.
    6. Create a database with the config.
    7. Get the configuration object from the Database and verify that FullSync is true.
    8. Use c4db_config2 to confirm that its config contains the kC4DB_DiskSyncFull flag.
 */
- (void) testDBWithFullSync {
    NSString* dbName = @"fullsyncdb";
    [CBLDatabase deleteDatabase: dbName inDirectory: self.directory error: nil];
    AssertFalse([CBLDatabase databaseExists: dbName inDirectory: self.directory]);
    
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = self.directory;
    NSError* error;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: dbName
                                                 config: config
                                                  error: &error];
    AssertNil(error);
    AssertNotNil(db, @"Couldn't open db: %@", error);
    AssertFalse([db config].fullSync);
    AssertFalse(([db getC4DBConfig]->flags & kC4DB_DiskSyncFull) == kC4DB_DiskSyncFull);
    
    [self closeDatabase: db];
    
    config.fullSync = true;
    db = [[CBLDatabase alloc] initWithName: dbName
                                    config: config
                                     error: &error];
    AssertNil(error);
    AssertNotNil(db, @"Couldn't open db: %@", error);
    Assert([db config].fullSync);
    Assert(([db getC4DBConfig]->flags & kC4DB_DiskSyncFull) == kC4DB_DiskSyncFull);

    [self closeDatabase: db];
}

#pragma mark - MMap
/** Test Spec v1.0.1:
    https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0006-MMap-Config.md
 */

/**
 1. TestDefaultMMapConfig
 Description
    Test that the mmapEnabled default value is as expected and that it's setter and getter work.
 Steps
    1. Create a DatabaseConfiguration object.
    2. Get and check that the value of the mmapEnabled property is true.
    3. Set the mmapEnabled property to false and verify that the value is false.
    4. Set the mmapEnabled property to true, and verify that the mmap value is true.
 */

- (void) testDefaultMMapConfig {
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    Assert(config.mmapEnabled);
    
    config.mmapEnabled = false;
    AssertFalse(config.mmapEnabled);
    
    config.mmapEnabled = true;
    Assert(config.mmapEnabled);
}

/**
2. TestDatabaseWithConfiguredMMap
Description
    Test that a Database respects the mmapEnabled property.
Steps
    1. Create a DatabaseConfiguration object and set mmapEnabled to false.
    2. Create a database with the config.
    3. Get the configuration object from the database and check that the mmapEnabled is false.
    4. Use c4db_config2 to confirm that its config contains the kC4DB_MmapDisabled flag
    5. Set the config's mmapEnabled property true
    6. Create a database with the config.
    7. Get the configuration object from the database and verify that mmapEnabled is true
    8. Use c4db_config2 to confirm that its config doesn't contains the kC4DB_MmapDisabled flag
 */

- (void) testDatabaseWithConfiguredMMap {
    NSError* err;
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    
    config.mmapEnabled = false;
    CBLDatabase* db1 = [[CBLDatabase alloc] initWithName: @"mmap1" config: config error:&err];
    CBLDatabaseConfiguration* tempConfig = [db1 config];
    AssertFalse(tempConfig.mmapEnabled);
    Assert(([db1 getC4DBConfig]->flags & kC4DB_MmapDisabled) == kC4DB_MmapDisabled);
    
    config.mmapEnabled = true;
    CBLDatabase* db2 = [[CBLDatabase alloc] initWithName: @"mmap2" config: config error:&err];
    tempConfig = [db2 config];
    Assert(tempConfig.mmapEnabled);
    AssertFalse(([db2 getC4DBConfig]->flags & kC4DB_MmapDisabled) == kC4DB_MmapDisabled);
    
    db1 = nil;
    db2 = nil;
}

@end
