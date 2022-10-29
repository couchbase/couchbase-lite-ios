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

#ifdef COUCHBASE_ENTERPRISE
@interface ReplicatorTest_Collection : ReplicatorTest

@end

@implementation ReplicatorTest_Collection {
    CBLDatabaseEndpoint* _target;
    CBLReplicatorConfiguration* _config;
}

- (void)setUp {
    [super setUp];
    
    _target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    _config = [[CBLReplicatorConfiguration alloc] initWithTarget: _target];
}

- (void)tearDown {
    _target = nil;
    _config = nil;
    
    [super tearDown];
}

#pragma mark - Replicator Configuration

- (void) testCreateReplicatorWithNoCollections {
    [self expectException: NSInvalidArgumentException in:^{
        CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: _config];
        NSLog(@"%@", r);
    }];
 
    [self expectException: NSInvalidArgumentException in:^{
        [_config addCollections: @[] config: nil];
    }];
}

// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (void) testAddCollectionsToDatabaseInitiatedConfig {
    [self createDocNumbered: nil start: 0 num: 5];
    
    _config = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                            target: _target];
    
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    [self createDocNumbered: col1a start: 10 num: 7];
    
    [_config addCollections: @[col1a] config: nil];
    
    AssertEqual(self.db.count, 5);
    AssertEqual(col1a.count, 7);
    AssertEqual(self.otherDB.count, 0);
    AssertEqual(col2a.count, 0);
    
    [self run: _config errorCode: 0 errorDomain: nil];
    
    // make sure it sync all docs
    AssertEqual(self.db.count, 5);
    AssertEqual(col1a.count, 7);
    AssertEqual(self.otherDB.count, 5);
    AssertEqual(col2a.count, 7);
}

- (void) testOuterFiltersWithCollections {
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
    
    id filter1 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return YES; };
    id filter2 = ^BOOL(CBLDocument* d, CBLDocumentFlags f) { return NO; };
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    
    // set the outer filters without setting the default collection.
    [self expectException: NSInternalInconsistencyException in:^{
        config.conflictResolver = resolver;
    }];
    
    [self expectException: NSInternalInconsistencyException in:^{
        config.pushFilter = filter1;
    }];
    
    [self expectException: NSInternalInconsistencyException in:^{
        config.pullFilter = filter2;
    }];
    
    [self expectException: NSInternalInconsistencyException in:^{
        config.channels = @[@"channel1", @"channel2", @"channel3"];
    }];
    
    [self expectException: NSInternalInconsistencyException in:^{
        config.documentIDs = @[@"docID1", @"docID2"];
    }];
    
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    AssertNotNil(defaultCollection);
    
    // set the outer filters after adding default collection
    [config addCollection: defaultCollection config: nil];
    config.pushFilter = filter1;
    config.pullFilter = filter2;
    config.channels = @[@"channel1", @"channel2", @"channel3"];
    config.documentIDs = @[@"docID1", @"docID2"];
    config.conflictResolver = resolver;
    
    CBLCollectionConfiguration* colConfig = [config collectionConfig: defaultCollection];
    Assert(colConfig.pushFilter == filter1);
    Assert(colConfig.pullFilter == filter2);
    AssertEqualObjects(colConfig.channels, (@[@"channel1", @"channel2", @"channel3"]));
    AssertEqualObjects(colConfig.documentIDs, (@[@"docID1", @"docID2"]));
    Assert(colConfig.conflictResolver == resolver);
}

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

// exception causes memory leak!
// https://clang.llvm.org/docs/AutomaticReferenceCounting.html#exceptions
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

// exception causes memory leak!
// https://clang.llvm.org/docs/AutomaticReferenceCounting.html#exceptions
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
    mdoc = [[col1b documentWithID: @"doc2" error: &error] toMutable];
    [mdoc setString: @"update1b" forKey: @"update"];
    [col1b saveDocument: mdoc error: &error];
    mdoc = [[col2b documentWithID: @"doc2" error: &error] toMutable];
    [mdoc setString: @"update2b" forKey: @"update"];
    [col2b saveDocument: mdoc error: &error];
    
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    id token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docReplication) {
        // change with single document are the update revisions from colA & colB collections.
        if (docReplication.documents.count == 1) {
            CBLReplicatedDocument* doc = docReplication.documents[0];
            AssertEqualObjects(doc.id, [doc.collection isEqualToString: @"colA"] ?  @"doc1" : @"doc2");
            AssertEqual(doc.error.code, 0);
        } else if (docReplication.documents.count == 2) {
            // change with 2 docs, will be the conflict
            for (CBLReplicatedDocument* doc in docReplication.documents) {
                AssertEqualObjects(doc.id, [doc.collection isEqualToString: @"colA"] ?  @"doc1" : @"doc2");
                AssertEqual(doc.error.code, CBLErrorHTTPConflict);
            }
        } else {
            AssertFalse(true, @"Unexpected document change listener");
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
    [self createDocNumbered: col1a start: 0 num: 2];
    [self createDocNumbered: col1b start: 10 num: 3];
    AssertEqual(col1a.count, 2);
    AssertEqual(col1b.count, 3);
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

- (void) testCollectionDocumentReplicationEvents {
    CBLDocumentFlags flags = 0;
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
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePushAndPull
                                                     continuous: NO];
    CBLCollectionConfiguration* colConfig = [[CBLCollectionConfiguration alloc] init];
    [config addCollections: @[col1a, col1b] config: colConfig];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
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
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    
    // Create a document and push it to otherDB:
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLReplicatorConfiguration* pushConfig = [[CBLReplicatorConfiguration alloc] initWithTarget: _target];
    pushConfig.replicatorType = kCBLReplicatorTypePush;
    [pushConfig addCollection: defaultCollection config: nil];
    CBLCollectionConfiguration* colConfig = [pushConfig collectionConfig: defaultCollection];
    AssertNil(colConfig.conflictResolver);
    
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    // Now make different changes in db and otherDB:
    doc1 = [[self.db documentWithID: @"doc"] toMutable];
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[self.otherDB documentWithID: @"doc"] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([self.otherDB saveDocument: doc2 error: &error]);
    
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([self.otherDB saveDocument: doc2 error: &error]);
    
    // Pull from otherDB, creating a conflict to resolve:
    CBLReplicatorConfiguration* pullConfig = [[CBLReplicatorConfiguration alloc] initWithTarget: _target];
    pullConfig.replicatorType = kCBLReplicatorTypePull;
    [pullConfig addCollection: defaultCollection config: nil];
    colConfig = [pullConfig collectionConfig: defaultCollection];
    AssertNil(colConfig.conflictResolver);
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    
    // Most-Active Win:
    NSDictionary* expectedResult = @{@"species": @"Tiger",
                                     @"pattern": @"striped",
                                     @"color": @"black-yellow"};
    AssertEqualObjects(savedDoc.toDictionary, expectedResult);
    
    // Push to otherDB again to verify there is no replication conflict now,
    // and that otherDB ends up with the same resolved document:
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.otherDB.count, 1u);
    CBLDocument* otherSavedDoc = [self.otherDB documentWithID: @"doc"];
    AssertEqualObjects(otherSavedDoc.toDictionary, expectedResult);
}

- (void) testPullConflictNoBaseRevisionWithCollection {
    NSError* error;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    
    // Create the conflicting docs separately in each database. They have the same base revID
    // because the contents are identical, but because the db never pushed revision 1, it doesn't
    // think it needs to preserve its body; so when it pulls a conflict, there won't be a base
    // revision for the resolver.
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc2 setValue: @"Tiger" forKey: @"species"];
    Assert([self.otherDB saveDocument: doc2 error: &error]);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([self.otherDB saveDocument: doc2 error: &error]);
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([self.otherDB saveDocument: doc2 error: &error]);
    
    CBLReplicatorConfiguration* pullConfig = [[CBLReplicatorConfiguration alloc] initWithTarget: _target];
    pullConfig.replicatorType = kCBLReplicatorTypePull;
    [pullConfig addCollection: defaultCollection config: nil];
    CBLCollectionConfiguration* colConfig = [pullConfig collectionConfig: defaultCollection];
    AssertNil(colConfig.conflictResolver);
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertEqualObjects(savedDoc.toDictionary, (@{@"species": @"Tiger",
                                                 @"pattern": @"striped",
                                                 @"color": @"black-yellow"}));
}

- (void) testPullConflictDeleteWinsWithCollection {
    NSError* error;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    
    // Create a document and push it to otherDB:
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLReplicatorConfiguration* pushConfig = [[CBLReplicatorConfiguration alloc] initWithTarget: _target];
    pushConfig.replicatorType = kCBLReplicatorTypePush;
    [pushConfig addCollection: defaultCollection config: nil];
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    // Delete the document from db:
    Assert([self.db deleteDocument: doc1 error: &error]);
    AssertNil([self.db documentWithID: doc1.id]);
    
    // Update the document in otherDB:
    CBLMutableDocument* doc2 = [[self.otherDB documentWithID: doc1.id] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([self.otherDB saveDocument: doc2 error: &error]);
    
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([self.otherDB saveDocument: doc2 error: &error]);
    
    // Pull from otherDB, creating a conflict to resolve:
    CBLReplicatorConfiguration* pullConfig = [[CBLReplicatorConfiguration alloc] initWithTarget: _target];
    pullConfig.replicatorType = kCBLReplicatorTypePull;
    [pullConfig addCollection: defaultCollection config: nil];
    CBLCollectionConfiguration* colConfig = [pullConfig collectionConfig: defaultCollection];
    AssertNil(colConfig.conflictResolver);
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved as delete wins:
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: doc1.id]);
}

#pragma clang diagnostic pop

@end

#endif // COUCHBASE_ENTERPRISE
