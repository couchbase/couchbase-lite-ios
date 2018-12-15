//
//  DocumentExpirationTest.m
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
#import "CBLDocument+Internal.h"

#define kDOCID      [CBLQuerySelectResult expression: [CBLQueryMeta id]]

@interface DocumentExpirationTest : CBLTestCase

@end

@implementation DocumentExpirationTest

- (void) testGetExpirationBeforeSaveDocument {
    CBLDocument* doc = [self createDocument: nil];
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db getDocumentExpirationWithID: doc.id]);
}

- (void) testGetExpirationBeforeSettingExpiration {
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertEqual(self.db.count, 1u);
    AssertNil([self.db getDocumentExpirationWithID: doc.id]);
}

- (void) testSetAndGetExpiration {
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 3.0];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Validate result
    NSDate* expected = [self.db getDocumentExpirationWithID: doc.id];
    AssertNotNil(expected);
    
    NSTimeInterval delta = [expiryDate timeIntervalSinceDate: expected];
    Assert(fabs(delta) <= 0.1);
}

- (void) testSetExpirationToNonExistingDocument {
    NSDate* expiry = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    [self expectError: CBLErrorDomain
                 code: CBLErrorNotFound
                   in: ^BOOL(NSError** err) {
                       return [self.db setDocumentExpirationWithID: @"someNonExistingDocumentID"
                                                        expiration: expiry
                                                             error: err];
                   }];
}

- (void) testPurgeDocumentAfterSettingExpiry {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    NSError* err;
    CBLMutableDocument* doc = [self generateDocumentWithID: nil];
    AssertEqual(self.db.count, 1u);
    
    NSDate* expiryDateToPurge = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.db setDocumentExpirationWithID: doc.id
                                     expiration: expiryDateToPurge
                                          error: &err]);
    
    // purge doc
    Assert([self.db purgeDocument: doc error: &err]);
    AssertNil(err);
    
    // shouldn't crash due to timer fired
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       [expectation fulfill];
                   });
    
    // Wait for result, it shouldn't crash due to already purged doc
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
}

- (void) testDocumentPurgedAfterExpiration {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    NSError* err;
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertEqual(self.db.count, 1u);
    
    // Setup document change notification
    id token = [self.db addDocumentChangeListenerWithID: doc.id
                                               listener: ^(CBLDocumentChange *change)
    {
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.database documentWithID: change.documentID] == nil) {
            [expectation fulfill];
        }
    }];

    // Set expiry
    AssertNil(err);
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Wait for result, it shouldn't crash due to already purged doc
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    
    // Remove listener
    [self.db removeChangeListenerWithToken: token];
}

- (void) testDocumentNotShowUpInQueryAfterExpiration {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.db getDocumentExpirationWithID: doc.id]);
    
    // Setup document change notification
    __weak DocumentExpirationTest* weakSelf = self;
    id token = [self.db addDocumentChangeListenerWithID: doc.id
                                               listener: ^(CBLDocumentChange *change)
    {
        DocumentExpirationTest* strongSelf = weakSelf;
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.database documentWithID: change.documentID] == nil) {
            [strongSelf verifyQueryResultCount: 0 deletedCount: 0];
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    
    // Remove listener
    [self.db removeChangeListenerWithToken: token];
}

- (void) verifyQueryResultCount: (NSUInteger)count deletedCount: (NSUInteger)deletedCount {
    NSError* error;
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]];
    AssertNotNil(q);
    NSEnumerator* rs = [q execute: &error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], count);
    
    q = [CBLQueryBuilder select: @[kDOCID]
                           from: [CBLQueryDataSource database: self.db]
                          where: [CBLQueryMeta isDeleted]];
    AssertNotNil(q);
    rs = [q execute: &error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], deletedCount);
}

- (void) testDocumentNotPurgedBeforeExpiration {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.db getDocumentExpirationWithID: doc.id]);
    
    __block NSTimeInterval purgeTime;
    id token = [self.db addDocumentChangeListenerWithID: doc.id
                                               listener: ^(CBLDocumentChange *change)
    {
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.database documentWithID: change.documentID] == nil) {
            purgeTime = [[NSDate date] timeIntervalSince1970];
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSTimeInterval begin = [[NSDate date] timeIntervalSince1970];
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSince1970: begin + 2.0];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    
    // Validate
    Assert(purgeTime - begin >= 2.0);
    
    // Remove listener
    [self.db removeChangeListenerWithToken: token];
}

- (void) testSetExpirationAndThenCloseDatabase {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.db getDocumentExpirationWithID: doc.id]);
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Close database
    [self closeDatabase: self.db];
    
    // Validate it is not crashing due to the expiry timer!!
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       [expectation fulfill];
                   });
    
    // Wait for result
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
}

- (void) testExpiredDocumentPurgedAfterReopenDatabase {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.db getDocumentExpirationWithID: doc.id]);
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    AssertNotNil([self.db documentWithID: doc.id]);
    
    // Reopen database
    [self reopenDB];
    
    // Setup document change notification
    id token = [self.db addDocumentChangeListenerWithID: doc.id
                                               listener: ^(CBLDocumentChange *change)
    {
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.database documentWithID: change.documentID] == nil) {
            [expectation fulfill];
        }
    }];
    
    AssertNotNil([self.db documentWithID: doc.id]);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: 5 handler: nil];
    
    // Remove listener
    [self.db removeChangeListenerWithToken: token];
}

- (void) testExpiredDocumentPurgedOnDifferentDBInstance {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Store doc on default DB
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.db getDocumentExpirationWithID: doc.id]);
    
    // Create otherDB instance with same name
    CBLDatabase* otherDB = [self openDBNamed: self.db.name error: nil];
    Assert(otherDB != self.db);
    
    // Setup document change notification on otherDB
    __weak CBLDatabase *weakOtherDB = otherDB;
    id token = [otherDB addDocumentChangeListenerWithID: doc.id
                                               listener: ^(CBLDocumentChange *change)
    {
        AssertEqualObjects(change.documentID, doc.id);
        if ([weakOtherDB documentWithID: change.documentID] == nil) {
            [expectation fulfill];
        }
    }];
    
    // Set expiry on db instance
    NSDate* expiryDate = [[NSDate date] dateByAddingTimeInterval: 1];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    AssertNotNil([self.db documentWithID: doc.id]);
    AssertNotNil([otherDB documentWithID: doc.id]);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: 5 handler: nil];
    
    AssertNil([self.db documentWithID: doc.id]);
    AssertNil([otherDB documentWithID: doc.id]);
    
    // Remove listener
    [otherDB removeChangeListenerWithToken: token];
    
    // Close otherDB
    Assert([otherDB close: nil]);
}

- (void) testOverrideExpirationWithFartherDate {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.db getDocumentExpirationWithID: doc.id]);
    
    // Setup document change notification
    __block NSTimeInterval purgeTime;
    id token = [self.db addDocumentChangeListenerWithID: doc.id
                                               listener: ^(CBLDocumentChange *change)
    {
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.database documentWithID: change.documentID] == nil) {
            purgeTime = [[NSDate date] timeIntervalSince1970];
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSTimeInterval begin = [[NSDate date] timeIntervalSince1970];
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSince1970: begin + 1.0];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Override
    Assert([self.db setDocumentExpirationWithID: doc.id
                                     expiration: [expiryDate dateByAddingTimeInterval: 1.0] error: &err]);
    AssertNil(err);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    
    // Validate
    Assert(purgeTime - begin >= 2.0);
    
    // Remove listener
    [self.db removeChangeListenerWithToken: token];
}

- (void) testOverrideExpirationWithCloserDate {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.db getDocumentExpirationWithID: doc.id]);
    
    // Setup document change notification
    __block NSTimeInterval purgeTime;
    id token = [self.db addDocumentChangeListenerWithID: doc.id listener: ^(CBLDocumentChange *change) {
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.database documentWithID: change.documentID] == nil) {
            [expectation fulfill];
            purgeTime = [[NSDate date] timeIntervalSince1970];
        }
    }];
    
    // Set expiry
    NSTimeInterval begin = [[NSDate date] timeIntervalSince1970];
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSince1970: begin + 10.0];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Override
    Assert([self.db setDocumentExpirationWithID: doc.id
                                     expiration: [expiryDate dateByAddingTimeInterval: -9.0] error: &err]);
    AssertNil(err);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    
    // Validate
    Assert(purgeTime - begin < 3.0);
    
    // Remove listener
    [self.db removeChangeListenerWithToken: token];
}

- (void) testRemoveExpirationDate {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    
    // Set expiry
    NSError* err;
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Remove expiry
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: nil error: &err]);
    AssertNil(err);
    
    // validate
    __weak DocumentExpirationTest* weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       // should not be removed
                       AssertNotNil([weakSelf.db documentWithID: doc.id]);
                       [expectation fulfill];
                   });
    
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
}

- (void) testSetExpirationThenDeletionAfterwards {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    
    // Setup document change notification
    __block int count = 0;
    id token = [self.db addDocumentChangeListenerWithID: doc.id
                                               listener: ^(CBLDocumentChange *change)
    {
        count++;
        AssertEqualObjects(change.documentID, doc.id);
        AssertNil([change.database documentWithID: change.documentID]);
        if (count == 2) {
            CBLDocument* purgedDoc = [[CBLDocument alloc] initWithDatabase: change.database
                                                                documentID: doc.id
                                                            includeDeleted: YES
                                                                     error: nil];
            AssertNil(purgedDoc);
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Delete doc
    Assert([self.db deleteDocument: doc error: &err]);
    AssertNil(err);
    AssertNil([self.db documentWithID: doc.id]);
    
    CBLDocument* deletedDoc = [[CBLDocument alloc] initWithDatabase: self.db
                                                         documentID: doc.id
                                                     includeDeleted: TRUE
                                                              error: &err];
    AssertNotNil(deletedDoc);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    AssertEqual(count, 2);
    
    // Remove listener
    [self.db removeChangeListenerWithToken: token];
}

- (void) testSetExpirationOnDeletedDocument {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    
    // Setup document change notification
    __block int count = 0;
    id token = [self.db addDocumentChangeListenerWithID: doc.id listener: ^(CBLDocumentChange *change) {
        count++;
        AssertEqualObjects(change.documentID, doc.id);
        AssertNil([change.database documentWithID: change.documentID]);
        if (count == 2) {
            CBLDocument* purgedDoc = [[CBLDocument alloc] initWithDatabase: change.database
                                                                documentID: doc.id
                                                            includeDeleted: YES
                                                                     error: nil];
            AssertNil(purgedDoc);
            [expectation fulfill];
        }
    }];
    
    // Delete doc
    NSError* err;
    Assert([self.db deleteDocument: doc error: &err]);
    AssertNil(err);
    AssertNil([self.db documentWithID: doc.id]);
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    AssertEqual(count, 2);
    
    // Remove listener
    [self.db removeChangeListenerWithToken: token];
}

- (void) testPurgeImmediately {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.db getDocumentExpirationWithID: doc.id]);
    
    // Setup document change notification
    __block NSDate* purgeTime;
    id token = [self.db addDocumentChangeListenerWithID: doc.id
                                               listener: ^(CBLDocumentChange *change)
    {
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.database documentWithID: change.documentID] == nil) {
            purgeTime = [NSDate date];
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSDate* begin = [NSDate date];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: begin error: &err]);
    AssertNil(err);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    
    /*
     Validate. Delay inside the KeyStore::now() is in seconds, without milliseconds part.
     Depending on the current milliseconds, we cannot gurantee, this will get purged exactly within
     a second but in ~1 second.
     */
    NSTimeInterval delta = [purgeTime timeIntervalSinceDate: begin];
    Assert(delta < 2);
    
    // Remove listener
    [self.db removeChangeListenerWithToken: token];
}

@end
