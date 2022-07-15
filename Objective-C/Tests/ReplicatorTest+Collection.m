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

#pragma clang diagnostic pop

@end
