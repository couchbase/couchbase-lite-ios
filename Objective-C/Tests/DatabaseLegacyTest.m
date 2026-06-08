//
//  DatabaseLegacyTest.m
//  CouchbaseLite
//
//  Copyright (c) 2026 Couchbase, Inc All rights reserved.
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

/**
 Minimal smoke tests for the deprecated CBLDatabase APIs. The goal is only to touch each
 restored deprecated entry point and confirm its basic functionality (delegation to the
 default collection), NOT to re-cover the full behavior that the collection tests already do.
 */
@interface DatabaseLegacyTest : CBLTestCase

@end

@implementation DatabaseLegacyTest

// The whole file exercises deprecated APIs on purpose:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#pragma mark - Count / Get

- (void) testCount {
    NSError* error;
    Assert([self.db saveDocument: [self createDocument: @"doc1"] error: &error], @"Save failed: %@", error);
    Assert([self.db saveDocument: [self createDocument: @"doc2"] error: &error], @"Save failed: %@", error);
    AssertEqual(self.db.count, 2u);
}

- (void) testDocumentWithIDAndSubscript {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setString: @"value" forKey: @"key"];
    NSError* error;
    Assert([self.db saveDocument: doc error: &error], @"Save failed: %@", error);

    CBLDocument* saved = [self.db documentWithID: @"doc1"];
    AssertNotNil(saved);
    AssertEqualObjects([saved stringForKey: @"key"], @"value");
    AssertNil([self.db documentWithID: @"missing"]);

    // Subscript returns a document fragment:
    Assert(self.db[@"doc1"].exists);
    AssertFalse(self.db[@"missing"].exists);
}

#pragma mark - Save / Delete / Purge

- (void) testSaveVariants {
    NSError* error;

    // saveDocument:error:
    Assert([self.db saveDocument: [self createDocument: @"doc1"] error: &error], @"Save failed: %@", error);

    // saveDocument:concurrencyControl:error:
    Assert([self.db saveDocument: [self createDocument: @"doc2"]
              concurrencyControl: kCBLConcurrencyControlLastWriteWins
                           error: &error], @"Save failed: %@", error);

    // saveDocument:conflictHandler:error: (no conflict for a new doc, handler not invoked)
    Assert([self.db saveDocument: [self createDocument: @"doc3"]
                 conflictHandler: ^BOOL(CBLMutableDocument* cur, CBLDocument* old) { return YES; }
                           error: &error], @"Save failed: %@", error);

    AssertEqual(self.db.count, 3u);
}

- (void) testDeleteVariants {
    NSError* error;
    Assert([self.db saveDocument: [self createDocument: @"doc1"] error: &error], @"Save failed: %@", error);
    Assert([self.db saveDocument: [self createDocument: @"doc2"] error: &error], @"Save failed: %@", error);

    // deleteDocument:error:
    Assert([self.db deleteDocument: [self.db documentWithID: @"doc1"] error: &error], @"Delete failed: %@", error);

    // deleteDocument:concurrencyControl:error:
    Assert([self.db deleteDocument: [self.db documentWithID: @"doc2"]
                concurrencyControl: kCBLConcurrencyControlLastWriteWins
                             error: &error], @"Delete failed: %@", error);

    AssertEqual(self.db.count, 0u);
}

- (void) testPurge {
    NSError* error;

    // purgeDocument:error:
    Assert([self.db saveDocument: [self createDocument: @"doc1"] error: &error], @"Save failed: %@", error);
    Assert([self.db purgeDocument: [self.db documentWithID: @"doc1"] error: &error], @"Purge failed: %@", error);
    AssertNil([self.db documentWithID: @"doc1"]);

    // purgeDocumentWithID:error:
    Assert([self.db saveDocument: [self createDocument: @"doc2"] error: &error], @"Save failed: %@", error);
    Assert([self.db purgeDocumentWithID: @"doc2" error: &error], @"Purge failed: %@", error);
    AssertNil([self.db documentWithID: @"doc2"]);
}

#pragma mark - Document Expiration

- (void) testDocumentExpiration {
    NSError* error;
    Assert([self.db saveDocument: [self createDocument: @"doc1"] error: &error], @"Save failed: %@", error);

    NSDate* expiry = [NSDate dateWithTimeIntervalSinceNow: 120];
    Assert([self.db setDocumentExpirationWithID: @"doc1" expiration: expiry error: &error],
           @"Set expiration failed: %@", error);

    NSDate* got = [self.db getDocumentExpirationWithID: @"doc1"];
    AssertNotNil(got);
    Assert(fabs(got.timeIntervalSinceReferenceDate - expiry.timeIntervalSinceReferenceDate) < 1.0);

    // Reset expiration with a nil date:
    Assert([self.db setDocumentExpirationWithID: @"doc1" expiration: nil error: &error],
           @"Reset expiration failed: %@", error);
    AssertNil([self.db getDocumentExpirationWithID: @"doc1"]);
}

#pragma mark - Change Listeners

- (void) testDatabaseChangeListener {
    NSError* error;

    // addChangeListener:  (+ CBLDatabaseChange) and removeChangeListenerWithToken:
    XCTestExpectation* x1 = [self expectationWithDescription: @"db change"];
    id<CBLListenerToken> token1 = [self.db addChangeListener: ^(CBLDatabaseChange* change) {
        Assert([change.documentIDs containsObject: @"doc1"]);
        AssertEqualObjects(change.database.name, self.db.name);
        [x1 fulfill];
    }];
    Assert([self.db saveDocument: [self createDocument: @"doc1"] error: &error], @"Save failed: %@", error);
    [self waitForExpectationsWithTimeout: kExpTimeout handler: NULL];
    [self.db removeChangeListenerWithToken: token1];

    // addChangeListenerWithQueue:listener:  and token-based removal
    XCTestExpectation* x2 = [self expectationWithDescription: @"db change on queue"];
    id<CBLListenerToken> token2 = [self.db addChangeListenerWithQueue: dispatch_get_main_queue()
                                                             listener: ^(CBLDatabaseChange* change) {
        Assert([change.documentIDs containsObject: @"doc2"]);
        [x2 fulfill];
    }];
    Assert([self.db saveDocument: [self createDocument: @"doc2"] error: &error], @"Save failed: %@", error);
    [self waitForExpectationsWithTimeout: kExpTimeout handler: NULL];
    [token2 remove];
}

- (void) testDocumentChangeListener {
    NSError* error;
    Assert([self.db saveDocument: [self createDocument: @"doc1"] error: &error], @"Save failed: %@", error);

    // addDocumentChangeListenerWithID:listener:  (+ deprecated CBLDocumentChange.database)
    XCTestExpectation* x1 = [self expectationWithDescription: @"doc change"];
    id<CBLListenerToken> token1 = [self.db addDocumentChangeListenerWithID: @"doc1"
                                                                  listener: ^(CBLDocumentChange* change) {
        AssertEqualObjects(change.documentID, @"doc1");
        AssertEqualObjects(change.database.name, self.db.name);
        [x1 fulfill];
    }];
    CBLMutableDocument* update1 = [[self.db documentWithID: @"doc1"] toMutable];
    [update1 setString: @"v1" forKey: @"k"];
    Assert([self.db saveDocument: update1 error: &error], @"Save failed: %@", error);
    [self waitForExpectationsWithTimeout: kExpTimeout handler: NULL];
    [token1 remove];

    // addDocumentChangeListenerWithID:queue:listener:
    XCTestExpectation* x2 = [self expectationWithDescription: @"doc change on queue"];
    id<CBLListenerToken> token2 = [self.db addDocumentChangeListenerWithID: @"doc1"
                                                                     queue: dispatch_get_main_queue()
                                                                  listener: ^(CBLDocumentChange* change) {
        AssertEqualObjects(change.documentID, @"doc1");
        [x2 fulfill];
    }];
    CBLMutableDocument* update2 = [[self.db documentWithID: @"doc1"] toMutable];
    [update2 setString: @"v2" forKey: @"k"];
    Assert([self.db saveDocument: update2 error: &error], @"Save failed: %@", error);
    [self waitForExpectationsWithTimeout: kExpTimeout handler: NULL];
    [token2 remove];
}

#pragma mark - Index

- (void) testIndexes {
    NSError* error;

    // createIndex:withName: (CBLValueIndex)
    CBLValueIndex* index = [CBLIndexBuilder valueIndexWithItems: @[[CBLValueIndexItem property: @"name"]]];
    Assert([self.db createIndex: index withName: @"nameIndex" error: &error], @"Create index failed: %@", error);
    Assert([self.db.indexes containsObject: @"nameIndex"]);

    // createIndexWithConfig:name: (CBLValueIndexConfiguration)
    CBLValueIndexConfiguration* config = [[CBLValueIndexConfiguration alloc] initWithExpression: @[@"age"]];
    Assert([self.db createIndexWithConfig: config name: @"ageIndex" error: &error], @"Create index failed: %@", error);
    Assert([self.db.indexes containsObject: @"ageIndex"]);
    AssertEqual(self.db.indexes.count, 2u);

    // deleteIndexForName:
    Assert([self.db deleteIndexForName: @"nameIndex" error: &error], @"Delete index failed: %@", error);
    AssertFalse([self.db.indexes containsObject: @"nameIndex"]);
    AssertEqual(self.db.indexes.count, 1u);
}

#pragma clang diagnostic pop

@end
