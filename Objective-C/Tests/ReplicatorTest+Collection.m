//
//  ReplicatorTest+Collection
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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

#import "ReplicatorTest.h"
#import "CBLReplicator+Internal.h"

@interface ReplicatorTest_Collection : ReplicatorTest

@end

@implementation ReplicatorTest_Collection {
    CBLDatabaseEndpoint* _target;
    CBLReplicatorConfiguration* _config;
}

- (void)setUp {
    [super setUp];
    
    _target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
}

- (void)tearDown {
    _target = nil;
    _config = nil;
    
    [super tearDown];
}

#pragma mark - Replicator Configuration

- (void) testCreateReplicatorWithNoCollections {
    [self expectException: NSInvalidArgumentException in:^{
        (void)[[CBLReplicatorConfiguration alloc] initWithCollections:@[] target: self->_target];
    }];
}

- (void) testCreateConfigWithCollection {
    NSError* error;
    NSURL* url = [NSURL URLWithString: @"wss://foo"];
    CBLURLEndpoint* endpoint = [[CBLURLEndpoint alloc] initWithURL: url];
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    
    CBLCollectionConfiguration* colConfig = [[CBLCollectionConfiguration alloc] initWithCollection: col1a];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithCollections: @[colConfig]
                                                                                          target: endpoint];
    
    AssertEqual(config.collectionConfigs.count, 1);
    AssertEqualObjects(config.collectionConfigs[0].collection, col1a);
    CBLCollectionConfiguration* colConfig2 = config.collectionConfigs.firstObject;
    AssertNotNil(colConfig2);
    
    // only value match
    AssertEqualObjects(colConfig2.collection.fullName, col1a.fullName);
    AssertNil(colConfig2.conflictResolver);
    AssertNil(colConfig2.channels);
    AssertNil(colConfig2.pushFilter);
    AssertNil(colConfig2.pullFilter);
    AssertNil(colConfig2.documentIDs);
}

- (void) testFromCollectionsWithCollectionConfig {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    NSURL* url = [NSURL URLWithString: @"wss://foo"];
    CBLURLEndpoint* endpoint = [[CBLURLEndpoint alloc] initWithURL: url];
    
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    id filter1 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    id filter2 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    
    NSArray<CBLCollectionConfiguration*>* colConfigs = [CBLCollectionConfiguration fromCollections: @[col1a, col1b] config:^(CBLCollectionConfiguration* config) {
        config.conflictResolver = resolver;
        config.pushFilter = filter1;
        config.pullFilter = filter2;
        config.channels = @[@"channel1", @"channel2", @"channel3"];
        config.documentIDs = @[@"docID1", @"docID2"];
    }];
    
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithCollections: colConfigs
                                                                                          target: endpoint];
    
    AssertEqual(config.collectionConfigs.count, 2);
    Assert([(@[@"colA", @"colB"]) containsObject: config.collectionConfigs[0].collection.name]);
    Assert([(@[@"colA", @"colB"]) containsObject: config.collectionConfigs[1].collection.name]);
    Assert([config.collectionConfigs[0].collection.scope.name isEqualToString: @"scopeA"]);
    Assert([config.collectionConfigs[1].collection.scope.name isEqualToString: @"scopeA"]);
    
    CBLCollectionConfiguration* config1 = config.collectionConfigs[0];
    CBLCollectionConfiguration* config2 = config.collectionConfigs[1];
    Assert(config1 != config2);
    
    Assert(config1.pushFilter == filter1);
    Assert(config1.pullFilter == filter2);
    AssertEqualObjects(config1.channels, (@[@"channel1", @"channel2", @"channel3"]));
    AssertEqualObjects(config1.documentIDs, (@[@"docID1", @"docID2"]));
    Assert(config1.conflictResolver == resolver);
    
    Assert(config2.pushFilter == filter1);
    Assert(config2.pullFilter == filter2);
    AssertEqualObjects(config2.channels, (@[@"channel1", @"channel2", @"channel3"]));
    AssertEqualObjects(config2.documentIDs, (@[@"docID1", @"docID2"]));
    Assert(config2.conflictResolver == resolver);
}

// exception causes memory leak!
// https://clang.llvm.org/docs/AutomaticReferenceCounting.html#exceptions
- (void) _testCollectionsFromDifferentDatabaseInstances {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLDatabase* db2 = [self openDBNamed: self.db.name error: &error];
    CBLCollection* col1b = [db2 createCollectionWithName: @"colB"
                                                   scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    NSURL* url = [NSURL URLWithString: @"wss://foo"];
    CBLURLEndpoint* endpoint = [[CBLURLEndpoint alloc] initWithURL: url];
    NSArray<CBLCollectionConfiguration*>* colConfigs = [CBLCollectionConfiguration fromCollections: @[col1a, col1b]];
    
    [self expectException: NSInvalidArgumentException in:^{
        (void) [[CBLReplicatorConfiguration alloc] initWithCollections: colConfigs target: endpoint];
    }];
}

#pragma mark - 8.14 Replicator

- (void) testCollectionSingleShotPushReplication {
    [self testCollectionPushReplication: NO];
}

- (void) testCollectionContinuousPushReplication {
    [self testCollectionPushReplication: YES];
}

- (void) testCollectionPushReplication: (BOOL)continous {
    NSUInteger totalDocs = 10;
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    [self createDocNumbered: col1a start: 0 num: totalDocs];
    [self createDocNumbered: col1b start: 10 num: totalDocs];
    AssertEqual(col1a.count, totalDocs);
    AssertEqual(col1b.count, totalDocs);
    AssertEqual(col2a.count, 0);
    AssertEqual(col2b.count, 0);
    
    // we have additional logic for default collection
    [self createDocNumbered: self.defaultCollection start: 20 num: totalDocs];
    AssertEqual(self.defaultCollection.count, totalDocs);
    AssertEqual(self.otherDBDefaultCollection.count, 0);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithCollections: @[col1a, col1b, self.defaultCollection]
                                                              target: target
                                                                type: kCBLReplicatorTypePush
                                                          continuous: continous];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(col2a.count, totalDocs);
    AssertEqual(col2b.count, totalDocs);
    AssertEqual(col1a.count, totalDocs);
    AssertEqual(col1b.count, totalDocs);
    AssertEqual(self.defaultCollection.count, totalDocs);
    AssertEqual(self.otherDBDefaultCollection.count, totalDocs);
}

- (void) testCollectionSingleShotPullReplication {
    [self testCollectionPullReplication: NO];
}

- (void) testCollectionContinuousPullReplication {
    [self testCollectionPullReplication: YES];
}

- (void) testCollectionPullReplication: (BOOL)continous {
    NSUInteger totalDocs = 10;
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    [self createDocNumbered: col2a start: 0 num: totalDocs];
    [self createDocNumbered: col2b start: 10 num: totalDocs];
    AssertEqual(col2a.count, totalDocs);
    AssertEqual(col2b.count, totalDocs);
    AssertEqual(col1a.count, 0);
    AssertEqual(col1b.count, 0);
    
    // we have additional logic for default collection
    [self createDocNumbered: self.otherDBDefaultCollection start: 20 num: totalDocs];
    AssertEqual(self.otherDBDefaultCollection.count, totalDocs);
    AssertEqual(self.defaultCollection.count, 0);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithCollections: @[col1a, col1b, self.defaultCollection]
                                                              target: target
                                                                type: kCBLReplicatorTypePull
                                                          continuous: continous];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(col2a.count, totalDocs);
    AssertEqual(col2b.count, totalDocs);
    AssertEqual(col1a.count, totalDocs);
    AssertEqual(col1b.count, totalDocs);
    
    AssertEqual(self.defaultCollection.count, totalDocs);
    AssertEqual(self.otherDBDefaultCollection.count, totalDocs);
}

- (void) testCollectionSingleShotPushPullReplication {
    [self testCollectionPushPullReplication: NO];
}

- (void) testCollectionContinuousPushPullReplication {
    [self testCollectionPushPullReplication: YES];
}

- (void) testCollectionPushPullReplication: (BOOL)continous {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    [self createDocNumbered: col1a start: 0 num: 5];
    [self createDocNumbered: col2a start: 5 num: 5];
    
    [self createDocNumbered: col1b start: 20 num: 3];
    [self createDocNumbered: col2b start: 23 num: 3];
    
    AssertEqual(col1a.count, 5);
    AssertEqual(col2a.count, 5);
    
    AssertEqual(col1b.count, 3);
    AssertEqual(col2b.count, 3);
    
    // we have additional logic for default collection
    [self createDocNumbered: self.defaultCollection start: 30 num: 1];
    [self createDocNumbered: self.otherDBDefaultCollection start: 31 num: 1];
    AssertEqual(self.defaultCollection.count, 1);
    AssertEqual(self.otherDBDefaultCollection.count, 1);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithCollections: @[col1a, col1b, self.defaultCollection]
                                                              target: target
                                                                type: kCBLReplicatorTypePushAndPull
                                                          continuous: continous];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(col1a.count, 10);
    AssertEqual(col2a.count, 10);
    
    AssertEqual(col1b.count, 6);
    AssertEqual(col2b.count, 6);
    
    AssertEqual(self.defaultCollection.count, 2);
    AssertEqual(self.otherDBDefaultCollection.count, 2);
}

- (void) testCollectionResetReplication {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    [self createDocNumbered: col2a start: 0 num: 10];
    AssertEqual(col2a.count, 10);
    AssertEqual(col1a.count, 0);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithCollections: @[col1a]
                                                              target: target
                                                                type: kCBLReplicatorTypePull
                                                          continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(col2a.count, 10);
    AssertEqual(col1a.count, 10);
    
    // Purge all documents from the colA of the database A.
    for (NSInteger i = 0; i < 10; i++) {
        NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)i];
        [col1a purgeDocumentWithID: docID error: &error];
    }
    
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(col1a.count, 0);
    AssertEqual(col2a.count, 10);
    
    [self run: config reset: YES errorCode: 0 errorDomain: nil];
    AssertEqual(col2a.count, 10);
    AssertEqual(col1a.count, 10);
}

- (void) testCollectionDefaultConflictResolver {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLMutableDocument* doc1 = [CBLMutableDocument documentWithID: @"doc1"];
    [col1a saveDocument: doc1 error: &error];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithCollections: @[col1a]
                                                              target: target
                                                                type: kCBLReplicatorTypePushAndPull
                                                          continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    CBLMutableDocument* mdoc = [[col1a documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update1" forKey: @"update"];
    [col1a saveDocument: mdoc error: &error];
    
    mdoc = [[col2a documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update1" forKey: @"update"];
    [col2a saveDocument: mdoc error: &error];
    
    mdoc = [[col2a documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update2" forKey: @"update"];
    [col2a saveDocument: mdoc error: &error];
    
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    __block int count = 0;
    id token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docReplication) {
        count += 1;
        
        AssertEqual(docReplication.documents.count, 1);
        CBLReplicatedDocument* doc = docReplication.documents[0];
        AssertEqual(doc.error.code, count == 1 ? 0 : CBLErrorHTTPConflict);
    }];
    [self runWithReplicator: r errorCode: 0 errorDomain: nil];
    [token remove];
    
    CBLDocument* doc = [col1a documentWithID: @"doc1" error: &error];
    AssertEqualObjects([doc stringForKey: @"update"], @"update2");
}

- (void) testCollectionConflictResolver {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    // Create a document with id "doc1" in colA and colB of the database A.
    CBLMutableDocument* doc1 = [CBLMutableDocument documentWithID: @"doc1"];
    [col1a saveDocument: doc1 error: &error];
    CBLMutableDocument* doc2 = [CBLMutableDocument documentWithID: @"doc2"];
    [col1b saveDocument: doc2 error: &error];
    
    TestConflictResolver *resolver1, *resolver2;
    resolver1 = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    resolver2 = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    
    CBLCollectionConfiguration* colConfig1 = [[CBLCollectionConfiguration alloc] initWithCollection: col1a];
    colConfig1.conflictResolver = resolver1;
    
    CBLCollectionConfiguration* colConfig2 = [[CBLCollectionConfiguration alloc] initWithCollection: col1b];
    colConfig2.conflictResolver = resolver2;
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithCollectionConfigs: @[colConfig1, colConfig2]
                                                                    target: target
                                                                      type: kCBLReplicatorTypePushAndPull
                                                                continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Update "doc1" in colA and colB of database A.
    CBLMutableDocument* mdoc = [[col1a documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update1a" forKey: @"update"];
    [col1a saveDocument: mdoc error: &error];
    mdoc = [[col2a documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update2a" forKey: @"update"];
    [col2a saveDocument: mdoc error: &error];
    
    // Update "doc1" in colA and colB of database B.
    mdoc = [[col1b documentWithID: @"doc2" error: &error] toMutable];
    [mdoc setString: @"update1b" forKey: @"update"];
    [col1b saveDocument: mdoc error: &error];
    mdoc = [[col2b documentWithID: @"doc2" error: &error] toMutable];
    [mdoc setString: @"update2b" forKey: @"update"];
    [col2b saveDocument: mdoc error: &error];
    
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    id token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docReplication) {
        if (!docReplication.isPush) {
            // Pull will resolve the conflicts:
            CBLReplicatedDocument* doc = docReplication.documents[0];
            AssertEqualObjects(doc.id, [doc.collection isEqualToString: @"colA"] ?  @"doc1" : @"doc2");
            AssertEqual(doc.error.code, 0);
        } else {
            // Push will have conflict errors:
            for (CBLReplicatedDocument* doc in docReplication.documents) {
                AssertEqualObjects(doc.id, [doc.collection isEqualToString: @"colA"] ?  @"doc1" : @"doc2");
                AssertEqual(doc.error.code, CBLErrorHTTPConflict);
            }
        }
    }];
    [self runWithReplicator: r errorCode: 0 errorDomain: nil];
    [token remove];
    
    CBLDocument* doc = [col1a documentWithID: @"doc1" error: &error];
    AssertEqualObjects([doc stringForKey: @"update"], @"update1a");
    doc = [col2a documentWithID: @"doc1" error: &error];
    AssertEqualObjects([doc stringForKey: @"update"], @"update2a");
    
    doc = [col1b documentWithID: @"doc2" error: &error];
    AssertEqualObjects([doc stringForKey: @"update"], @"update2b");
    doc = [col2b documentWithID: @"doc2" error: &error];
    AssertEqualObjects([doc stringForKey: @"update"], @"update2b");
}

- (void) testCollectionPushFilter {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    // Create some documents in colA and colB of the database A.
    [self createDocNumbered: col1a start: 0 num: 10];
    [self createDocNumbered: col1b start: 10 num: 10];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    
    CBLReplicationFilter filter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        if ([document.collection.name isEqualToString: @"colA"])
            return [document integerForKey: @"number1"] < 5;
        else
            return [document integerForKey: @"number1"] >= 15;
    };
    
    CBLCollectionConfiguration* config1 = [[CBLCollectionConfiguration alloc] initWithCollection: col1a];
    config1.pushFilter = filter;
    
    CBLCollectionConfiguration* config2 = [[CBLCollectionConfiguration alloc] initWithCollection: col1b];
    config2.pushFilter = filter;
    
    CBLReplicatorConfiguration* config = [self configWithCollectionConfigs: @[config1, config2]
                                                                    target: target
                                                                      type: kCBLReplicatorTypePush
                                                                continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(col1a.count, 10);
    AssertEqual(col1b.count, 10);
    AssertEqual(col2a.count, 5);
    AssertEqual(col2b.count, 5);
}

- (void) testCollectionPullFilter {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    // Create some documents in colA and colB of the database A.
    [self createDocNumbered: col2a start: 0 num: 10];
    [self createDocNumbered: col2b start: 10 num: 10];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    
    CBLReplicationFilter filter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        if ([document.collection.name isEqualToString: @"colA"])
            return [document integerForKey: @"number1"] < 5;
        else
            return [document integerForKey: @"number1"] >= 15;
    };
    
    CBLCollectionConfiguration* config1 = [[CBLCollectionConfiguration alloc] initWithCollection: col1a];
    config1.pullFilter = filter;
    
    CBLCollectionConfiguration* config2 = [[CBLCollectionConfiguration alloc] initWithCollection: col1b];
    config2.pullFilter = filter;
    
    CBLReplicatorConfiguration* config = [self configWithCollectionConfigs: @[config1, config2]
                                                                    target: target
                                                                      type: kCBLReplicatorTypePull
                                                                continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(col1a.count, 5);
    AssertEqual(col1b.count, 5);
    AssertEqual(col2a.count, 10);
    AssertEqual(col2b.count, 10);
}

- (void) testCollectionDocumentIDsPushFilter {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    // Create some documents in colA and colB of the database A.
    [self createDocNumbered: col1a start: 0 num: 5];
    [self createDocNumbered: col1b start: 10 num: 5];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];

    CBLCollectionConfiguration* config1 = [[CBLCollectionConfiguration alloc] initWithCollection: col1a];
    config1.documentIDs = @[@"doc1", @"doc2"];
    
    CBLCollectionConfiguration* config2 = [[CBLCollectionConfiguration alloc] initWithCollection: col1b];
    config2.documentIDs = @[@"doc10", @"doc11", @"doc13"];
    
    CBLReplicatorConfiguration* config = [self configWithCollectionConfigs: @[config1, config2]
                                                                    target: target
                                                                      type: kCBLReplicatorTypePush
                                                                continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(col1a.count, 5);
    AssertEqual(col1b.count, 5);
    
    AssertEqual(col2a.count, 2);
    AssertEqual(col2b.count, 3);
}

- (void) testCollectionDocumentIDsPullFilter {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    // Create some documents in colA and colB of the database A.
    [self createDocNumbered: col2a start: 0 num: 5];
    [self createDocNumbered: col2b start: 10 num: 5];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    
    CBLCollectionConfiguration* config1 = [[CBLCollectionConfiguration alloc] initWithCollection: col1a];
    config1.documentIDs = @[@"doc1", @"doc2"];
    
    CBLCollectionConfiguration* config2 = [[CBLCollectionConfiguration alloc] initWithCollection: col1b];
    config2.documentIDs = @[@"doc11", @"doc13", @"doc14"];
    
    CBLReplicatorConfiguration* config = [self configWithCollectionConfigs: @[config1, config2]
                                                                    target: target
                                                                      type: kCBLReplicatorTypePull
                                                                continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(col1a.count, 2); // only 2 docs sync
    AssertEqual(col1b.count, 3); // only 3 docs sync
    
    AssertEqual(col2a.count, 5);
    AssertEqual(col2b.count, 5);
}

- (void) testCollectionGetPendingDocumentIDs {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    // Create some documents in colA and colB of the database A.
    [self createDocNumbered: col1a start: 0 num: 2];
    [self createDocNumbered: col1b start: 10 num: 3];
    AssertEqual(col1a.count, 2);
    AssertEqual(col1b.count, 3);
    AssertEqual(col2a.count, 0);
    AssertEqual(col2b.count, 0);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithCollections: @[col1a, col1b]
                                                              target: target
                                                                type: kCBLReplicatorTypePush
                                                          continuous: NO];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    NSSet* docIds1a = [r pendingDocumentIDsForCollection: col1a error: &error];
    AssertNil(error);
    NSSet* docIds1b = [r pendingDocumentIDsForCollection: col1b error: &error];
    AssertNil(error);
    
    Assert([docIds1a containsObject: @"doc0"]);
    Assert([docIds1a containsObject: @"doc1"]);

    Assert([docIds1b containsObject: @"doc10"]);
    Assert([docIds1b containsObject: @"doc11"]);
    Assert([docIds1b containsObject: @"doc12"]);
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    // make sure all docs are synced
    AssertEqual(col1a.count, 2);
    AssertEqual(col1b.count, 3);
    AssertEqual(col2a.count, 2);
    AssertEqual(col2b.count, 3);
    
    // no docs are pending to sync
    docIds1a = [r pendingDocumentIDsForCollection: col1a error: &error];
    AssertNil(error);
    docIds1b = [r pendingDocumentIDsForCollection: col1b error: &error];
    AssertNil(error);
    AssertEqual(docIds1a.count, 0);
    AssertEqual(docIds1b.count, 0);
    
    // update again
    CBLMutableDocument* mdoc = [[col1a documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update1a" forKey: @"update"];
    [col1a saveDocument: mdoc error: &error];
    
    docIds1a = [r pendingDocumentIDsForCollection: col1a error: &error];
    AssertNil(error);
    AssertEqual(docIds1a.count, 1);
    Assert([docIds1a containsObject: @"doc1"]);
    
    CBLDocument* doc = [col1b documentWithID: @"doc12" error: &error];
    [col1b deleteDocument: doc error: &error];
    AssertNil(error);
    docIds1b = [r pendingDocumentIDsForCollection: col1b error: &error];
    AssertNil(error);
    AssertEqual(docIds1b.count, 1);
    Assert([docIds1b containsObject: @"doc12"]);
}

- (void) testCollectionIsDocumentPending {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    // Create some documents in colA and colB of the database A.
    [self createDocNumbered: col1a start: 0 num: 10];
    [self createDocNumbered: col1b start: 10 num: 5];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    
    CBLReplicatorConfiguration* config = [self configWithCollections: @[col1a, col1b]
                                                              target: target
                                                                type: kCBLReplicatorTypePush
                                                          continuous: NO];
    
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    for (NSUInteger i = 0; i < 10; i++) {
        NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)i];
        Assert([r isDocumentPending: docID collection: col1a error: &error]);
        AssertNil(error);
    }
    
    for (NSUInteger i = 10; i < 15; i++) {
        NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)i];
        Assert([r isDocumentPending: docID collection: col1b error: &error]);
        AssertNil(error);
    }
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    for (NSUInteger i = 0; i < 10; i++) {
        NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)i];
        AssertFalse([r isDocumentPending: docID collection: col1a error: &error]);
        AssertNil(error);
    }
    
    for (NSUInteger i = 10; i < 15; i++) {
        NSString* docID = [NSString stringWithFormat: @"doc%ld", (long)i];
        AssertFalse([r isDocumentPending: docID collection: col1b error: &error]);
        AssertNil(error);
    }
    
    // Update a document in colA.
    CBLMutableDocument* mdoc = [[col1a documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update1a" forKey: @"update"];
    [col1a saveDocument: mdoc error: &error];
    
    Assert([r isDocumentPending: @"doc1" collection: col1a error: &error]);
    AssertNil(error);
    
    // Delete a document in colB.
    CBLDocument* doc = [col1b documentWithID: @"doc12" error: &error];
    [col1b deleteDocument: doc error: &error];
    AssertNil(error);
    
    Assert([r isDocumentPending: @"doc12" collection: col1b error: &error]);
    AssertNil(error);
}

- (void) testCollectionDocumentReplicationEvents {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    [self createDocNumbered: col1a start: 0 num: 4];
    [self createDocNumbered: col1b start: 5 num: 5];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    
    CBLReplicatorConfiguration* config = [self configWithCollections: @[col1a, col1b]
                                                              target: target
                                                                type: kCBLReplicatorTypePushAndPull
                                                          continuous: NO];
    
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    __block CBLDocumentFlags flags = 0;
    __block int docsCount = 0;
    __block NSMutableArray* docs = [[NSMutableArray alloc] init];
    id token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docReplication) {
        docsCount += docReplication.documents.count;
        for (CBLReplicatedDocument* doc in docReplication.documents) {
            [docs addObject: doc.id];
            Assert((doc.flags & flags) == flags);
            AssertNil(doc.error);
        }
    }];
    
    [self runWithReplicator: r errorCode: 0 errorDomain: nil];
    AssertEqual(col1a.count, 4);
    AssertEqual(col2a.count, 4);
    AssertEqual(col1b.count, 5);
    AssertEqual(col2b.count, 5);
    
    AssertEqual(docsCount, 9);
    NSArray* sortedDocs = [docs sortedArrayUsingSelector: @selector(compare:)];
    AssertEqualObjects(sortedDocs, (@[@"doc0", @"doc1", @"doc2", @"doc3", @"doc5", @"doc6", @"doc7", @"doc8", @"doc9"]));

    // colA & colB - db1
    Assert([col1a deleteDocument: [col1a documentWithID: @"doc0" error: &error]
                           error: &error]);
    Assert([col1b deleteDocument: [col1b documentWithID: @"doc6" error: &error]
                           error: &error]);

    // colA & colB - db2
    Assert([col2a deleteDocument: [col2a documentWithID: @"doc1" error: &error]
                           error: &error]);
    Assert([col2b deleteDocument: [col2b documentWithID: @"doc7" error: &error]
                           error: &error]);

    docsCount = 0;
    flags = kCBLDocumentFlagsDeleted;
    [docs removeAllObjects];
    [self runWithReplicator: r errorCode: 0 errorDomain: nil];

    AssertEqual(docsCount, 4);
    sortedDocs = [docs sortedArrayUsingSelector: @selector(compare:)];
    AssertEqualObjects(sortedDocs, (@[@"doc0", @"doc1", @"doc6", @"doc7"]));
    AssertEqual(col1a.count, 2);
    AssertEqual(col2a.count, 2);
    AssertEqual(col1b.count, 3);
    AssertEqual(col2b.count, 3);

    [token remove];
}

- (void) testPullConflictWithCollection {
    NSError* error = nil;
    
    // Create a document and push it to otherDB:
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLReplicatorConfiguration* pushConfig = [self configWithCollections: @[self.defaultCollection]
                                                                  target: _target
                                                                    type: kCBLReplicatorTypePush
                                                              continuous: NO];
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    // Now make different changes in db and otherDB:
    doc1 = [[self.defaultCollection documentWithID: @"doc" error: &error] toMutable];
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[self.otherDBDefaultCollection documentWithID: @"doc" error: &error] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    
    // Pull from otherDB, creating a conflict to resolve:
    CBLReplicatorConfiguration* pullConfig = [self configWithCollections: @[self.defaultCollection]
                                                                  target: _target
                                                                    type: kCBLReplicatorTypePull
                                                              continuous: NO];
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.defaultCollection.count, 1u);
    CBLDocument* savedDoc = [self.defaultCollection documentWithID: @"doc" error: &error];
    
    // Most-Active Win:
    NSDictionary* expectedResult = @{@"species": @"Tiger",
                                     @"pattern": @"striped",
                                     @"color": @"black-yellow"};
    AssertEqualObjects(savedDoc.toDictionary, expectedResult);
    
    // Push to otherDB again to verify there is no replication conflict now,
    // and that otherDB ends up with the same resolved document:
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.otherDBDefaultCollection.count, 1u);
    CBLDocument* otherSavedDoc = [self.otherDBDefaultCollection documentWithID: @"doc" error: &error];
    AssertEqualObjects(otherSavedDoc.toDictionary, expectedResult);
}

- (void) testPullConflictNoBaseRevisionWithCollection {
    NSError* error;
    // Create the conflicting docs separately in each database. They have the same base revID
    // because the contents are identical, but because the db never pushed revision 1, it doesn't
    // think it needs to preserve its body; so when it pulls a conflict, there won't be a base
    // revision for the resolver.
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc2 setValue: @"Tiger" forKey: @"species"];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    
    CBLReplicatorConfiguration* pullConfig = [self configWithCollections: @[self.defaultCollection]
                                                                  target: _target
                                                                    type: kCBLReplicatorTypePull
                                                              continuous: NO];
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.defaultCollection.count, 1u);
    CBLDocument* savedDoc = [self.defaultCollection documentWithID: @"doc" error: &error];
    AssertEqualObjects(savedDoc.toDictionary, (@{@"species": @"Tiger",
                                                 @"pattern": @"striped",
                                                 @"color": @"black-yellow"}));
}

- (void) testPullConflictDeleteWinsWithCollection {
    NSError* error;
    
    // Create a document and push it to otherDB:
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLReplicatorConfiguration* pushConfig = [self configWithCollections: @[self.defaultCollection]
                                                                  target: _target
                                                                    type: kCBLReplicatorTypePush
                                                              continuous: NO];
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    // Delete the document from db:
    Assert([self.defaultCollection deleteDocument: doc1 error: &error]);
    AssertNil([self.defaultCollection documentWithID: doc1.id error: &error]);
    
    // Update the document in otherDB:
    CBLMutableDocument* doc2 = [[self.otherDBDefaultCollection documentWithID: doc1.id error: &error] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    
    // Pull from otherDB, creating a conflict to resolve:
    CBLReplicatorConfiguration* pullConfig = [self configWithCollections: @[self.defaultCollection]
                                                                  target: _target
                                                                    type: kCBLReplicatorTypePull
                                                              continuous: NO];
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved as delete wins:
    AssertEqual(self.defaultCollection.count, 0u);
    AssertNil([self.defaultCollection documentWithID: doc1.id error: &error]);
}

@end
