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

#pragma clang diagnostic pop

@end
