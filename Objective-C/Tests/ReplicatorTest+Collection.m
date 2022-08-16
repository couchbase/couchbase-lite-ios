//
//  ReplicatorTest+Collection
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

@interface ReplicatorTest_Collection : ReplicatorTest

@end

@implementation ReplicatorTest_Collection

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - Replicator Configuration

// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (void) testCreateConfigWithDatabase {
    NSURL* url = [NSURL URLWithString: @"wss://foo"];
    CBLURLEndpoint* endpoint = [[CBLURLEndpoint alloc] initWithURL: url];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                       target: endpoint];
    
    AssertEqual(config.collections.count, 1);
    NSError* error = nil;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    AssertNotNil(defaultCollection);
    AssertEqualObjects(config.collections[0], defaultCollection);
    CBLCollectionConfiguration* colConfig = [config collectionConfig: defaultCollection];
    AssertNotNil(colConfig);
    
    // TODO: colConfig.collection == defaultCollection
    
    AssertNil(colConfig.conflictResolver);
    AssertNil(colConfig.channels);
    AssertNil(colConfig.pushFilter);
    AssertNil(colConfig.pullFilter);
    AssertNil(colConfig.documentIDs);
    
    Assert(config.database == self.db);
}

- (void) testConfigWithDatabaseAndConflictResolver {
    NSURL* url = [NSURL URLWithString: @"wss://foo"];
    CBLURLEndpoint* endpoint = [[CBLURLEndpoint alloc] initWithURL: url];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                       target: endpoint];
    
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    config.conflictResolver = resolver;
    
    NSError* error = nil;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    AssertNotNil(defaultCollection);
    CBLCollectionConfiguration* colConfig = [config collectionConfig: defaultCollection];
    AssertNotNil(colConfig);
    
    Assert(config.conflictResolver == resolver);
    Assert(colConfig.conflictResolver == resolver);
    
    // Update replicator.conflictResolver
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    config.conflictResolver = resolver;
    
    Assert(config.conflictResolver == resolver);
    Assert(colConfig.conflictResolver == resolver);
    
    // Update collectionConfig.conflictResolver
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return nil;
    }];
    colConfig.conflictResolver = resolver;
    colConfig = [config collectionConfig: defaultCollection];
    Assert(colConfig.conflictResolver == resolver);
    
    [config addCollection: defaultCollection config: colConfig];
    Assert(config.conflictResolver == resolver);
}

- (void) testConfigWithDatabaseAndFilters {
    NSURL* url = [NSURL URLWithString: @"wss://foo"];
    CBLURLEndpoint* endpoint = [[CBLURLEndpoint alloc] initWithURL: url];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                       target: endpoint];
    id filter1 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    id filter2 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    config.pushFilter = filter1;
    config.pullFilter = filter2;
    config.channels = @[@"channel1", @"channel2", @"channel3"];
    config.documentIDs = @[@"docID1", @"docID2"];
    
    NSError* error = nil;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    AssertNotNil(defaultCollection);
    CBLCollectionConfiguration* colConfig = [config collectionConfig: defaultCollection];
    
    Assert(colConfig.pushFilter == filter1);
    Assert(colConfig.pullFilter == filter2);
    AssertEqualObjects(colConfig.channels, (@[@"channel1", @"channel2", @"channel3"]));
    AssertEqualObjects(colConfig.documentIDs, (@[@"docID1", @"docID2"]));
    
    // Update replicator.filters
    config.pushFilter = filter2;
    config.pullFilter = filter1;
    config.channels = @[@"channel1"];
    config.documentIDs = @[@"docID1"];
    colConfig = [config collectionConfig: defaultCollection];
    
    Assert(colConfig.pushFilter == filter2);
    Assert(colConfig.pullFilter == filter1);
    AssertEqualObjects(colConfig.channels, (@[@"channel1"]));
    AssertEqualObjects(colConfig.documentIDs, (@[@"docID1"]));
    
    // Update collectionConfig.filters
    colConfig.pushFilter = filter1;
    colConfig.pullFilter = filter2;
    colConfig.channels = @[@"channel1", @"channel2"];
    colConfig.documentIDs = @[@"doc1", @"doc2"];
    
    colConfig = [config collectionConfig: defaultCollection];
    Assert(colConfig.pushFilter == filter1);
    Assert(colConfig.pullFilter == filter2);
    AssertEqualObjects(colConfig.channels, (@[@"channel1", @"channel2"]));
    AssertEqualObjects(colConfig.documentIDs, (@[@"doc1", @"doc2"]));
    
    [config addCollection: defaultCollection config: colConfig];
    Assert(config.pushFilter == filter1);
    Assert(config.pullFilter == filter2);
    AssertEqualObjects(config.channels, (@[@"channel1", @"channel2"]));
    AssertEqualObjects(config.documentIDs, (@[@"doc1", @"doc2"]));
}

- (void) testCreateConfigWithEndpointOnly {
    NSURL* url = [NSURL URLWithString: @"wss://foo"];
    CBLURLEndpoint* endpoint = [[CBLURLEndpoint alloc] initWithURL: url];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithTarget: endpoint];
    AssertEqual(config.collections.count, 0);
    
    [self expectException: NSInternalInconsistencyException in:^{
        NSLog(@"%@", config.database);
    }];
}

- (void) testAddCollectionsWithoutCollectionConfig {
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
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithTarget: endpoint];
    [config addCollections: @[col1a, col1b] config: nil];
    
    AssertEqual(config.collections.count, 2);
    Assert([(@[@"colA", @"colB"]) containsObject: config.collections[0].name]);
    Assert([(@[@"colA", @"colB"]) containsObject: config.collections[1].name]);
    Assert([config.collections[0].scope.name isEqualToString: @"scopeA"]);
    Assert([config.collections[1].scope.name isEqualToString: @"scopeA"]);
    
    CBLCollectionConfiguration* config1 = [config collectionConfig: col1a];
    CBLCollectionConfiguration* config2 = [config collectionConfig: col1b];
    Assert(config1 != config2);
    
    AssertNil(config1.conflictResolver);
    AssertNil(config1.channels);
    AssertNil(config1.pushFilter);
    AssertNil(config1.pullFilter);
    AssertNil(config1.documentIDs);
    AssertNil(config2.conflictResolver);
    AssertNil(config2.channels);
    AssertNil(config2.pushFilter);
    AssertNil(config2.pullFilter);
    AssertNil(config2.documentIDs);
}

- (void) testAddCollectionsWithCollectionConfig {
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
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithTarget: endpoint];
    
    
    CBLCollectionConfiguration* colconfig = [[CBLCollectionConfiguration alloc] init];
    
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    colconfig.conflictResolver = resolver;
    id filter1 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    id filter2 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    colconfig.pushFilter = filter1;
    colconfig.pullFilter = filter2;
    colconfig.channels = @[@"channel1", @"channel2", @"channel3"];
    colconfig.documentIDs = @[@"docID1", @"docID2"];
    
    [config addCollections: @[col1a, col1b] config: colconfig];
    
    AssertEqual(config.collections.count, 2);
    Assert([(@[@"colA", @"colB"]) containsObject: config.collections[0].name]);
    Assert([(@[@"colA", @"colB"]) containsObject: config.collections[1].name]);
    Assert([config.collections[0].scope.name isEqualToString: @"scopeA"]);
    Assert([config.collections[1].scope.name isEqualToString: @"scopeA"]);
    
    CBLCollectionConfiguration* config1 = [config collectionConfig: col1a];
    CBLCollectionConfiguration* config2 = [config collectionConfig: col1b];
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

- (void) testAddUpdateCollection {
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
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithTarget: endpoint];
    
    // add collection 1 with empty config
    [config addCollection: col1a config: nil];
    
    // Create and add Collection config for collection 2.
    CBLCollectionConfiguration* colconfig = [[CBLCollectionConfiguration alloc] init];
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    colconfig.conflictResolver = resolver;
    id filter1 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    id filter2 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    colconfig.pushFilter = filter1;
    colconfig.pullFilter = filter2;
    colconfig.channels = @[@"channel1", @"channel2", @"channel3"];
    colconfig.documentIDs = @[@"docID1", @"docID2"];
    [config addCollection: col1b config: colconfig];
    
    AssertEqual(config.collections.count, 2);
    Assert([(@[@"colA", @"colB"]) containsObject: config.collections[0].name]);
    Assert([(@[@"colA", @"colB"]) containsObject: config.collections[1].name]);
    Assert([config.collections[0].scope.name isEqualToString: @"scopeA"]);
    Assert([config.collections[1].scope.name isEqualToString: @"scopeA"]);
    
    // validate the config1 for NULL values
    CBLCollectionConfiguration* config1 = [config collectionConfig: col1a];
    AssertNil(config1.conflictResolver);
    AssertNil(config1.channels);
    AssertNil(config1.pushFilter);
    AssertNil(config1.pullFilter);
    AssertNil(config1.documentIDs);
    
    // vlaidate the config2 for valid values
    CBLCollectionConfiguration* config2 = [config collectionConfig: col1b];
    Assert(config2.pushFilter == filter1);
    Assert(config2.pullFilter == filter2);
    AssertEqualObjects(config2.channels, (@[@"channel1", @"channel2", @"channel3"]));
    AssertEqualObjects(config2.documentIDs, (@[@"docID1", @"docID2"]));
    Assert(config2.conflictResolver == resolver);
    
    // Update in reverse
    [config addCollection: col1a config: colconfig];
    [config addCollection: col1b config: nil];
    
    // validate the config1 for valid values
    config1 = [config collectionConfig: col1a];
    Assert(config1.pushFilter == filter1);
    Assert(config1.pullFilter == filter2);
    AssertEqualObjects(config1.channels, (@[@"channel1", @"channel2", @"channel3"]));
    AssertEqualObjects(config1.documentIDs, (@[@"docID1", @"docID2"]));
    Assert(config1.conflictResolver == resolver);
    
    // vlaidate the config2 for NULL
    config2 = [config collectionConfig: col1b];
    AssertNil(config2.conflictResolver);
    AssertNil(config2.channels);
    AssertNil(config2.pushFilter);
    AssertNil(config2.pullFilter);
    AssertNil(config2.documentIDs);
}

- (void) testRemoveCollection {
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
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithTarget: endpoint];
    
    // Create and add Collection config for both collections.
    CBLCollectionConfiguration* colconfig = [[CBLCollectionConfiguration alloc] init];
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    colconfig.conflictResolver = resolver;
    id filter1 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    id filter2 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    colconfig.pushFilter = filter1;
    colconfig.pullFilter = filter2;
    colconfig.channels = @[@"channel1", @"channel2", @"channel3"];
    colconfig.documentIDs = @[@"docID1", @"docID2"];
    
    [config addCollection: col1a config: colconfig];
    [config addCollection: col1b config: colconfig];
    
    AssertEqual(config.collections.count, 2);
    Assert([(@[@"colA", @"colB"]) containsObject: config.collections[0].name]);
    Assert([(@[@"colA", @"colB"]) containsObject: config.collections[1].name]);
    Assert([config.collections[0].scope.name isEqualToString: @"scopeA"]);
    Assert([config.collections[1].scope.name isEqualToString: @"scopeA"]);
    
    CBLCollectionConfiguration* config1 = [config collectionConfig: col1a];
    Assert(config1.pushFilter == filter1);
    Assert(config1.pullFilter == filter2);
    AssertEqualObjects(config1.channels, (@[@"channel1", @"channel2", @"channel3"]));
    AssertEqualObjects(config1.documentIDs, (@[@"docID1", @"docID2"]));
    Assert(config1.conflictResolver == resolver);
    
    CBLCollectionConfiguration* config2 = [config collectionConfig: col1b];
    Assert(config2.pushFilter == filter1);
    Assert(config2.pullFilter == filter2);
    AssertEqualObjects(config2.channels, (@[@"channel1", @"channel2", @"channel3"]));
    AssertEqualObjects(config2.documentIDs, (@[@"docID1", @"docID2"]));
    Assert(config2.conflictResolver == resolver);
    
    [config removeCollection: col1b];
    
    AssertEqual(config.collections.count, 1);
    Assert([config.collections[0].name isEqualToString: @"colA"]);
    Assert([config.collections[0].scope.name isEqualToString: @"scopeA"]);
    
    AssertNil([config collectionConfig: col1b]);
}

// exception causiung the memory leak!
// TODO: https://issues.couchbase.com/browse/CBL-3576
- (void) _testAddCollectionsFromDifferentDatabaseInstances {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLDatabase* db2 = [self openDBNamed: kDatabaseName error: &error];
    CBLCollection* col1b = [db2 createCollectionWithName: @"colB"
                                                   scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    NSURL* url = [NSURL URLWithString: @"wss://foo"];
    CBLURLEndpoint* endpoint = [[CBLURLEndpoint alloc] initWithURL: url];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithTarget: endpoint];
    
    [self expectException: NSInvalidArgumentException in:^{
        [config addCollections: @[col1a, col1b] config: nil];
    }];
    
    AssertEqual(config.collections.count, 0);

    [config addCollection: col1a config: nil];
    AssertEqual(config.collections.count, 1);
    Assert([config.collections[0].name isEqualToString: @"colA"]);
    Assert([config.collections[0].scope.name isEqualToString: @"scopeA"]);

    [self expectException: NSInvalidArgumentException in:^{
        [config addCollection: col1b config: nil];
    }];
}

// memory leak with NSException
// TODO: https://issues.couchbase.com/browse/CBL-3576
- (void) _testAddDeletedCollections {
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLDatabase* db2 = [self openDBNamed: kDatabaseName error: &error];
    CBLCollection* col1b = [db2 createCollectionWithName: @"colB"
                                                   scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    Assert([db2 deleteCollectionWithName: @"colB" scope: @"scopeA" error: &error]);
    AssertNil(error);
    
    NSURL* url = [NSURL URLWithString: @"wss://foo"];
    CBLURLEndpoint* endpoint = [[CBLURLEndpoint alloc] initWithURL: url];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithTarget: endpoint];
    
    [self expectException: NSInvalidArgumentException in:^{
        [config addCollections: @[col1a, col1b] config: nil];
    }];
    
    [config addCollection: col1a config: nil];
    AssertEqual(config.collections.count, 1);
    Assert([config.collections[0].name isEqualToString: @"colA"]);
    Assert([config.collections[0].scope.name isEqualToString: @"scopeA"]);
    
    [self expectException: NSInvalidArgumentException in:^{
        [config addCollection: col1b config: nil];
    }];
}

#pragma mark - 8.14 Replicator

#ifdef COUCHBASE_ENTERPRISE

- (void) testCollectionSingleShotPushReplication {
    [self testCollectionPushReplication: NO];
}

- (void) testCollectionContinuousPushReplication {
    [self testCollectionPushReplication: YES];
}

- (void) testCollectionPushReplication: (BOOL)continous {
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
    
    [self createDocNumbered: col1a start: 0 num: 10];
    [self createDocNumbered: col1b start: 10 num: 10];
    AssertEqual(col2a.count, 0);
    AssertEqual(col2b.count, 0);
    AssertEqual(col1a.count, 10);
    AssertEqual(col1b.count, 10);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: continous];
    [config addCollections: @[col1a, col1b] config: nil];
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(col2a.count, 10);
    AssertEqual(col2b.count, 10);
    AssertEqual(col1a.count, 10);
    AssertEqual(col1b.count, 10);
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
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePull
                                                     continuous: continous];
    [config addCollections: @[col1a, col1b] config: nil];
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(col2a.count, totalDocs);
    AssertEqual(col2b.count, totalDocs);
    AssertEqual(col1a.count, totalDocs);
    AssertEqual(col1b.count, totalDocs);
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
    
    [self createDocNumbered: col1a start: 0 num: 2];
    [self createDocNumbered: col2a start: 10 num: 5];
    
    [self createDocNumbered: col1b start: 5 num: 3];
    [self createDocNumbered: col2b start: 15 num: 8];
    
    AssertEqual(col1a.count, 2);
    AssertEqual(col2a.count, 5);
    
    AssertEqual(col1b.count, 3);
    AssertEqual(col2b.count, 8);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePushAndPull
                                                     continuous: continous];
    [config addCollections: @[col1a, col1b] config: nil];
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(col1a.count, 7);
    AssertEqual(col2a.count, 7);
    AssertEqual(col1b.count, 11);
    AssertEqual(col2b.count, 11);
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
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePull
                                                     continuous: NO];
    [config addCollection: col1a config: nil];
    
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
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePushAndPull
                                                     continuous: NO];
    [config addCollection: col1a config: nil];
    
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
    
    [self run: config errorCode: 0 errorDomain: nil];
    
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
    doc1 = [CBLMutableDocument documentWithID: @"doc1"];
    [col1b saveDocument: doc1 error: &error];
    
    TestConflictResolver *resolver1, *resolver2;
    resolver1 = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    resolver2 = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    
    CBLCollectionConfiguration* colConfig1 = [[CBLCollectionConfiguration alloc] init];
    colConfig1.conflictResolver = resolver1;
    
    CBLCollectionConfiguration* colConfig2 = [[CBLCollectionConfiguration alloc] init];
    colConfig2.conflictResolver = resolver2;
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePushAndPull
                                                     continuous: NO];
    [config addCollection: col1a config: colConfig1];
    [config addCollection: col1b config: colConfig2];
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Update "doc1" in colA and colB of database A.
    CBLMutableDocument* mdoc = [[col1a documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update1a" forKey: @"update"];
    [col1a saveDocument: mdoc error: &error];
    mdoc = [[col2a documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update2a" forKey: @"update"];
    [col2a saveDocument: mdoc error: &error];
    
    // Update "doc1" in colA and colB of database B.
    mdoc = [[col1b documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update1b" forKey: @"update"];
    [col1b saveDocument: mdoc error: &error];
    mdoc = [[col2b documentWithID: @"doc1" error: &error] toMutable];
    [mdoc setString: @"update2b" forKey: @"update"];
    [col2b saveDocument: mdoc error: &error];
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    CBLDocument* doc = [col1a documentWithID: @"doc1" error: &error];
    AssertEqualObjects([doc stringForKey: @"update"], @"update1a");
    doc = [col2a documentWithID: @"doc1" error: &error];
    AssertEqualObjects([doc stringForKey: @"update"], @"update2a");
    
    doc = [col1b documentWithID: @"doc1" error: &error];
    AssertEqualObjects([doc stringForKey: @"update"], @"update2b");
    doc = [col2b documentWithID: @"doc1" error: &error];
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
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    
    CBLCollectionConfiguration* colConfig = [[CBLCollectionConfiguration alloc] init];
    colConfig.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        if ([document.collection.name isEqualToString: @"colA"])
            return [document integerForKey: @"number1"] < 5;
        else
            return [document integerForKey: @"number1"] >= 15;
    };
    
    [config addCollections: @[col1a, col1b] config: colConfig];
    
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
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePull
                                                     continuous: NO];
    
    CBLCollectionConfiguration* colConfig = [[CBLCollectionConfiguration alloc] init];
    colConfig.pullFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        if ([document.collection.name isEqualToString: @"colA"])
            return [document integerForKey: @"number1"] < 5;
        else
            return [document integerForKey: @"number1"] >= 15;
    };
    
    [config addCollections: @[col1a, col1b] config: colConfig];
    
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
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    
    CBLCollectionConfiguration* colConfig1 = [[CBLCollectionConfiguration alloc] init];
    colConfig1.documentIDs = @[@"doc1", @"doc2"];
    
    CBLCollectionConfiguration* colConfig2 = [[CBLCollectionConfiguration alloc] init];
    colConfig2.documentIDs = @[@"doc10", @"doc11", @"doc13"];
    
    [config addCollection: col1a config: colConfig1];
    [config addCollection: col1b config: colConfig2];
    
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
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePull
                                                     continuous: NO];
    
    CBLCollectionConfiguration* colConfig1 = [[CBLCollectionConfiguration alloc] init];
    colConfig1.documentIDs = @[@"doc1", @"doc2"];
    
    CBLCollectionConfiguration* colConfig2 = [[CBLCollectionConfiguration alloc] init];
    colConfig2.documentIDs = @[@"doc11", @"doc13", @"doc14"];
    
    [config addCollection: col1a config: colConfig1];
    [config addCollection: col1b config: colConfig2];
    
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
    [self createDocNumbered: col1a start: 0 num: 10];
    [self createDocNumbered: col1b start: 10 num: 5];
    AssertEqual(col1a.count, 10);
    AssertEqual(col1b.count, 5);
    AssertEqual(col2a.count, 0);
    AssertEqual(col2b.count, 0);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    [config addCollections: @[col1a, col1b] config: nil];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    NSSet* docIds1a = [r pendingDocumentIDsForCollection: col1a error: &error];
    AssertNil(error);
    NSSet* docIds1b = [r pendingDocumentIDsForCollection: col1b error: &error];
    AssertNil(error);
    AssertEqual(docIds1a.count, 10);
    AssertEqual(docIds1b.count, 5);
    
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(col1a.count, 10);
    AssertEqual(col1b.count, 5);
    AssertEqual(col2a.count, 10);
    AssertEqual(col2b.count, 5);
    
    docIds1a = [r pendingDocumentIDsForCollection: col1a error: &error];
    AssertNil(error);
    docIds1b = [r pendingDocumentIDsForCollection: col1b error: &error];
    AssertNil(error);
    AssertEqual(docIds1a.count, 0);
    AssertEqual(docIds1b.count, 0);
    
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
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    [config addCollections: @[col1a, col1b] config: nil];
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

#endif // COUCHBASE_ENTERPRISE

#pragma clang diagnostic pop

@end
