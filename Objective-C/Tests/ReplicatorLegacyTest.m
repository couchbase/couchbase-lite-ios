//
//  ReplicatorLegacyTest.m
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

#import "ReplicatorTest.h"

/**
 Minimal smoke tests for the deprecated Replicator / ReplicatorConfiguration / CollectionConfiguration
 and P2P listener configuration APIs. The goal is only to touch each deprecated entry point and
 confirm its basic functionality (delegation to the collection-based API + an end-to-end replication),
 NOT to re-cover the full replicator test suites.

 EE-only: uses CBLDatabaseEndpoint for a local database-to-database setup.
 */

/// A no-op conflict resolver for exercising the deprecated `conflictResolver` property.
@interface ReplicatorLegacyConflictResolver : NSObject <CBLConflictResolver>
@end

@implementation ReplicatorLegacyConflictResolver
- (CBLDocument*) resolve: (CBLConflict*)conflict { return conflict.localDocument; }
@end

@interface ReplicatorLegacyTest : ReplicatorTest
@end

@implementation ReplicatorLegacyTest

// The whole file exercises deprecated APIs on purpose:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#pragma mark - End-to-end replication using the legacy API

- (void) testReplicationWithLegacyConfig {
    NSError* error;
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setString: @"value" forKey: @"key"];
    Assert([self.defaultCollection saveDocument: doc error: &error], @"Save failed: %@", error);

    // Configure with the deprecated init + addCollection, then actually replicate:
    id<CBLEndpoint> target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithTarget: target];
    [config addCollection: self.defaultCollection config: nil];
    config.replicatorType = kCBLReplicatorTypePush;

    [self run: config errorCode: 0 errorDomain: nil];

    // The doc should have been pushed to the other database's default collection:
    AssertEqual(self.otherDBDefaultCollection.count, 1u);
    CBLDocument* saved = [self.otherDBDefaultCollection documentWithID: @"doc1" error: &error];
    AssertNotNil(saved);
    AssertEqualObjects([saved stringForKey: @"key"], @"value");
}

#pragma mark - ReplicatorConfiguration construction

- (void) testInitWithDatabaseTarget {
    id<CBLEndpoint> target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                       target: target];
    AssertEqual(config.database, self.db);
    AssertEqual(config.collections.count, 1u);
    AssertNotNil([config collectionConfig: self.defaultCollection]);

    // removeCollection:
    [config removeCollection: self.defaultCollection];
    AssertNil([config collectionConfig: self.defaultCollection]);
    AssertEqual(config.collections.count, 0u);
}

#pragma mark - Deprecated default-collection properties

- (void) testDeprecatedDefaultCollectionProperties {
    id<CBLEndpoint> target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                       target: target];

    // Each deprecated property delegates to the default collection's config; verify both the
    // round-trip and that it actually wired through to collectionConfig(defaultCollection).
    config.channels = @[@"channelA"];
    AssertEqualObjects(config.channels, (@[@"channelA"]));
    AssertEqualObjects([config collectionConfig: self.defaultCollection].channels, (@[@"channelA"]));

    config.documentIDs = @[@"doc1"];
    AssertEqualObjects(config.documentIDs, (@[@"doc1"]));
    AssertEqualObjects([config collectionConfig: self.defaultCollection].documentIDs, (@[@"doc1"]));

    config.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) { return YES; };
    AssertNotNil(config.pushFilter);
    AssertNotNil([config collectionConfig: self.defaultCollection].pushFilter);

    config.pullFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) { return YES; };
    AssertNotNil(config.pullFilter);
    AssertNotNil([config collectionConfig: self.defaultCollection].pullFilter);

    ReplicatorLegacyConflictResolver* resolver = [ReplicatorLegacyConflictResolver new];
    config.conflictResolver = resolver;
    AssertEqual(config.conflictResolver, resolver);
    AssertEqual([config collectionConfig: self.defaultCollection].conflictResolver, resolver);
}

#pragma mark - CollectionConfiguration deprecated init

- (void) testCollectionConfigurationDeprecatedInit {
    CBLCollectionConfiguration* cc = [[CBLCollectionConfiguration alloc] init];
    AssertNil(cc.collection);
    cc.channels = @[@"channelA"];
    AssertEqualObjects(cc.channels, (@[@"channelA"]));

    // Usable with the deprecated addCollection:config::
    id<CBLEndpoint> target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithTarget: target];
    [config addCollection: self.defaultCollection config: cc];
    AssertEqualObjects([config collectionConfig: self.defaultCollection].channels, (@[@"channelA"]));
}

#pragma mark - Pending documents

- (void) testPendingDocumentIDs {
    NSError* error;
    Assert([self.defaultCollection saveDocument: [self createDocument: @"doc1"] error: &error], @"%@", error);
    Assert([self.defaultCollection saveDocument: [self createDocument: @"doc2"] error: &error], @"%@", error);

    id<CBLEndpoint> target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                       target: target];
    config.replicatorType = kCBLReplicatorTypePush;

    // Pending documents are computed locally; no need to start the replicator.
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: config];
    NSSet<NSString*>* pending = [replicator pendingDocumentIDs: &error];
    AssertNotNil(pending, @"%@", error);
    AssertEqual(pending.count, 2u);
    Assert([pending containsObject: @"doc1"]);
    Assert([replicator isDocumentPending: @"doc1" error: &error]);
}

#pragma mark - P2P Listener configurations

- (void) testURLEndpointListenerConfigInitWithDatabase {
    CBLURLEndpointListenerConfiguration* config =
        [[CBLURLEndpointListenerConfiguration alloc] initWithDatabase: self.db];
    AssertEqual(config.database, self.db);
    AssertEqual(config.collections.count, 1u);
}

- (void) testMessageEndpointListenerConfigInitWithDatabase {
    CBLMessageEndpointListenerConfiguration* config =
        [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase: self.db
                                                            protocolType: kCBLProtocolTypeMessageStream];
    AssertEqual(config.database, self.db);
    AssertEqual(config.collections.count, 1u);
    AssertEqual(config.protocolType, kCBLProtocolTypeMessageStream);
}

// MARK: - CBLReplicator -removeChangeListenerWithToken:

- (void) testRemoveReplicatorChangeListenerWithToken {
    id<CBLEndpoint> target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithTarget: target];
    [config addCollection: self.defaultCollection config: nil];
    config.replicatorType = kCBLReplicatorTypePush;

    CBLReplicator* repl = [[CBLReplicator alloc] initWithConfig: config];
    id<CBLListenerToken> token = [repl addChangeListener: ^(CBLReplicatorChange* change) { }];
    AssertNotNil(token);

    // Remove using the deprecated API; should not crash.
    [repl removeChangeListenerWithToken: token];
}

// MARK: - CBLMessageEndpointListener -removeChangeListenerWithToken:

- (void) testRemoveMessageEndpointListenerChangeListenerWithToken {
    CBLMessageEndpointListenerConfiguration* config =
        [[CBLMessageEndpointListenerConfiguration alloc] initWithCollections: @[self.defaultCollection]
                                                                protocolType: kCBLProtocolTypeMessageStream];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig: config];
    id<CBLListenerToken> token = [listener addChangeListener: ^(CBLMessageEndpointListenerChange* change) { }];
    AssertNotNil(token);

    // Remove using the deprecated API; should not crash.
    [listener removeChangeListenerWithToken: token];
}

#pragma clang diagnostic pop

@end
