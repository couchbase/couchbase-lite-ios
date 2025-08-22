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
    NSError* error;
    CBLDocument* doc = [self createDocument: nil];
    AssertEqual(self.defaultCollection.count, 0u);
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
}

- (void) testGetExpirationBeforeSettingExpiration {
    NSError* error;
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertEqual(self.defaultCollection.count, 1u);
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
}

- (void) testSetAndGetExpiration {
    NSError* error;
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 3.0];
    NSError* err;
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: expiryDate
                                                         error: &err]);
    AssertNil(err);
    
    // Validate result
    NSDate* expected = [self.defaultCollection getDocumentExpirationWithID: doc.id error: &error];
    AssertNotNil(expected);
    
    NSTimeInterval delta = [expiryDate timeIntervalSinceDate: expected];
    Assert(fabs(delta) <= 0.1);
}

- (void) testSetExpirationToNonExistingDocument {
    NSDate* expiry = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    [self expectError: CBLErrorDomain
                 code: CBLErrorNotFound
                   in: ^BOOL(NSError** err) {
                       return [self.defaultCollection setDocumentExpirationWithID: @"someNonExistingDocumentID"
                                                                       expiration: expiry
                                                                            error: err];
                   }];
}

- (void) testPurgeDocumentAfterSettingExpiry {
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    NSError* err;
    CBLMutableDocument* doc = [self generateDocumentWithID: nil];
    AssertEqual(self.defaultCollection.count, 1u);
    
    NSDate* expiryDateToPurge = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: expiryDateToPurge
                                                         error: &err]);
    
    // purge doc
    Assert([self.defaultCollection purgeDocument: doc error: &err]);
    AssertNil(err);
    
    // shouldn't crash due to timer fired
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       [expectation fulfill];
                   });
    
    // Wait for result, it shouldn't crash due to already purged doc
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
}

- (void) testDocumentPurgedAfterExpiration {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
    AssertEqual(self.defaultCollection.count, 1u);
    
    // Setup document change notification
    id token = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                              listener: ^(CBLDocumentChange *change)
    {
        NSError* err;
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.collection documentWithID: change.documentID error: &err] == nil) {
            [expectation fulfill];
        }
    }];

    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id expiration: expiryDate error: &error]);
    AssertNil(error);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
    
    // Remove listener
    [token remove];
}

- (void) testDocumentNotShowUpInQueryAfterExpiration {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
    
    // Setup document change notification
    __weak DocumentExpirationTest* weakSelf = self;
    id token = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                              listener: ^(CBLDocumentChange *change)
    {
        NSError* err;
        DocumentExpirationTest* strongSelf = weakSelf;
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.collection documentWithID: change.documentID error: &err] == nil) {
            [strongSelf verifyQueryResultCount: 0 deletedCount: 0];
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id expiration: expiryDate error: &error]);
    AssertNil(error);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
    
    // Remove listener
    [token remove];
}

- (void) verifyQueryResultCount: (NSUInteger)count deletedCount: (NSUInteger)deletedCount {
    NSError* error;
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource collection: self.defaultCollection]];
    AssertNotNil(q);
    NSEnumerator* rs = [q execute: &error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], count);
    
    q = [CBLQueryBuilder select: @[kDOCID]
                           from: [CBLQueryDataSource collection: self.defaultCollection]
                          where: [CBLQueryMeta isDeleted]];
    AssertNotNil(q);
    rs = [q execute: &error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], deletedCount);
}

- (void) testDocumentNotPurgedBeforeExpiration {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
    
    id token = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                              listener: ^(CBLDocumentChange *change)
    {
        NSError* err;
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.collection documentWithID: change.documentID error: &err] == nil) {
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSTimeInterval begin = [[NSDate date] timeIntervalSince1970];
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSince1970: begin + 2.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id expiration: expiryDate error: &error]);
    AssertNil(error);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
    
    // Remove listener
    [token remove];
}

- (void) testSetExpirationAndThenCloseDatabase {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id expiration: expiryDate error: &error]);
    AssertNil(error);
    
    // Close database
    [self closeDatabase: self.db];
    
    // Validate it is not crashing due to the expiry timer!!
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       [expectation fulfill];
                   });
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
}

- (void) testExpiredDocumentPurgedAfterReopenDatabase {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id expiration: expiryDate error: &error]);
    AssertNil(error);
    AssertNotNil([self.defaultCollection documentWithID: doc.id error: &error]);
    
    // Reopen database
    [self reopenDB];
    
    // Setup document change notification
    id token = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                              listener: ^(CBLDocumentChange *change)
    {
        NSError* err;
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.collection documentWithID: change.documentID error: &err] == nil) {
            [expectation fulfill];
        }
    }];
    
    AssertNotNil([self.defaultCollection documentWithID: doc.id error: &error]);
    AssertNil(error);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
    
    // Remove listener
    [token remove];
}

- (void) testExpiredDocumentPurgedOnDifferentDBInstance {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Store doc on default DB
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
    
    // Create otherDB instance with same name
    CBLDatabase* otherDB = [self openDBNamed: self.db.name error: nil];
    CBLCollection* otherDBDefaultCollection = [otherDB defaultCollection: &error];
    Assert(otherDB != self.db);
    
    // Setup document change notification on otherDB
    __weak CBLCollection* weakOtherDBDefaultCollection = otherDBDefaultCollection;
    id token = [otherDBDefaultCollection addDocumentChangeListenerWithID: doc.id
                                                                listener: ^(CBLDocumentChange *change)
    {
        NSError* err;
        AssertEqualObjects(change.documentID, doc.id);
        if ([weakOtherDBDefaultCollection documentWithID: change.documentID error: &err] == nil) {
            [expectation fulfill];
        }
    }];
    
    // Set expiry on db instance
    NSDate* expiryDate = [[NSDate date] dateByAddingTimeInterval: 1];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id expiration: expiryDate error: &error]);
    AssertNil(error);
    AssertNotNil([self.defaultCollection documentWithID: doc.id error: &error]);
    AssertNotNil([otherDBDefaultCollection documentWithID: doc.id error: &error]);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
    
    AssertNil([self.defaultCollection documentWithID: doc.id error: &error]);
    AssertNil([otherDBDefaultCollection documentWithID: doc.id error: &error]);
    
    // Remove listener
    [token remove];
    
    // Close otherDB
    otherDBDefaultCollection = nil;
    Assert([otherDB close: nil]);
}

- (void) testOverrideExpirationWithFartherDate {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
    
    // Setup document change notification
    __block NSTimeInterval purgeTime;
    id token = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                              listener: ^(CBLDocumentChange *change)
    {
        NSError* err;
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.collection documentWithID: change.documentID error: &err] == nil) {
            purgeTime = [[NSDate date] timeIntervalSince1970];
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSTimeInterval begin = [[NSDate date] timeIntervalSince1970];
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSince1970: begin + 1.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: expiryDate
                                                         error: &error]);
    AssertNil(error);
    
    // Override
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: [expiryDate dateByAddingTimeInterval: 1.0]
                                                         error: &error]);
    AssertNil(error);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
    
    // Validate
    Assert(purgeTime - begin >= 2.0);
    
    // Remove listener
    [token remove];
}

- (void) testOverrideExpirationWithCloserDate {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
    
    // Setup document change notification
    __block NSTimeInterval purgeTime;
    id token = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                              listener: ^(CBLDocumentChange *change)
    {
        NSError* err;
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.collection documentWithID: change.documentID error: &err] == nil) {
            [expectation fulfill];
            purgeTime = [[NSDate date] timeIntervalSince1970];
        }
    }];
    
    // Set expiry
    NSTimeInterval begin = [[NSDate date] timeIntervalSince1970];
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSince1970: begin + 10.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: expiryDate
                                                         error: &error]);
    AssertNil(error);
    
    // Override
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: [expiryDate dateByAddingTimeInterval: -9.0]
                                                         error: &error]);
    AssertNil(error);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
    
    // Validate
    Assert(purgeTime - begin < 3.0);
    
    // Remove listener
    [token remove];
}

- (void) testRemoveExpirationDate {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: expiryDate
                                                         error: &error]);
    AssertNil(error);
    
    // Remove expiry
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: nil
                                                         error: &error]);
    AssertNil(error);
    
    // validate
    __weak DocumentExpirationTest* weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       NSError* err;
                       // should not be removed
                       AssertNotNil([weakSelf.defaultCollection documentWithID: doc.id error: &err]);
                       [expectation fulfill];
                   });
    
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
}

- (void) testSetExpirationThenDeletionAfterwards {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    
    // Setup document change notification
    __block int count = 0;
    id token = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                              listener: ^(CBLDocumentChange *change)
    {
        NSError* err;
        count++;
        AssertEqualObjects(change.documentID, doc.id);
        AssertNil([change.collection documentWithID: change.documentID error: &err]);
        if (count == 2) {
            CBLDocument* purgedDoc = [[CBLDocument alloc] initWithCollection: self.defaultCollection
                                                                  documentID: doc.id
                                                              includeDeleted: YES
                                                                       error: nil];
            AssertNil(purgedDoc);
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: expiryDate
                                                         error: &error]);
    AssertNil(error);
    
    // Delete doc
    Assert([self.defaultCollection deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertNil([self.defaultCollection documentWithID: doc.id error: &error]);
    
    CBLDocument* deletedDoc = [[CBLDocument alloc] initWithCollection: self.defaultCollection
                                                           documentID: doc.id
                                                       includeDeleted: TRUE
                                                                error: &error];
    AssertNotNil(deletedDoc);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
    AssertEqual(count, 2);
    
    // Remove listener
    [token remove];
}

- (void) testSetExpirationOnDeletedDocument {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    
    // Setup document change notification
    __block int count = 0;
    id token = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                              listener: ^(CBLDocumentChange *change)
    {
        NSError* err;
        count++;
        AssertEqualObjects(change.documentID, doc.id);
        AssertNil([change.collection documentWithID: change.documentID error: &err]);
        if (count == 2) {
            CBLDocument* purgedDoc = [[CBLDocument alloc] initWithCollection: self.defaultCollection
                                                                  documentID: doc.id
                                                              includeDeleted: YES
                                                                       error: nil];
            AssertNil(purgedDoc);
            [expectation fulfill];
        }
    }];
    
    // Delete doc
    Assert([self.defaultCollection deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertNil([self.defaultCollection documentWithID: doc.id error: &error]);
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: expiryDate
                                                         error: &error]);
    AssertNil(error);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
    AssertEqual(count, 2);
    
    // Remove listener
    [token remove];
}

- (void) testPurgeImmediately {
    NSError* error;
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    
    // Create doc
    CBLDocument* doc = [self generateDocumentWithID: nil];
    AssertNil([self.defaultCollection getDocumentExpirationWithID: doc.id error: &error]);
    
    // Setup document change notification
    __block NSDate* purgeTime;
    id token = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                              listener: ^(CBLDocumentChange *change)
    {
        NSError* err;
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.collection documentWithID: change.documentID error: &err] == nil) {
            purgeTime = [NSDate date];
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSDate* begin = [NSDate date];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                    expiration: begin
                                                         error: &error]);
    AssertNil(error);
    
    // Wait for result
    [self waitForExpectationsWithTimeout: kExpTimeout handler: nil];
    
    /*
     Validate. Delay inside the KeyStore::now() is in seconds, without milliseconds part.
     Depending on the current milliseconds, we cannot gurantee, this will get purged exactly within
     a second but in ~1 second.
     */
    NSTimeInterval delta = [purgeTime timeIntervalSinceDate: begin];
    Assert(delta < 2);
    
    // Remove listener
    [token remove];
}

@end
