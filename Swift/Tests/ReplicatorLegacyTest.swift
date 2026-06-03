//
//  ReplicatorLegacyTest.swift
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

import XCTest
import CouchbaseLiteSwift

/// A no-op conflict resolver for exercising the deprecated `conflictResolver` property.
class ReplicatorLegacyConflictResolver: ConflictResolverProtocol {
    func resolve(conflict: Conflict) -> Document? { return conflict.localDocument }
}

/// Minimal smoke tests for the deprecated Replicator / ReplicatorConfiguration / CollectionConfiguration
/// and P2P listener configuration APIs — touch each deprecated entry point plus one sanity
/// end-to-end replication, without re-covering the full replicator suites. EE-only (DatabaseEndpoint).
///
/// The class is marked deprecated so calls to the deprecated APIs below don't emit warnings.
@available(*, deprecated)
class ReplicatorLegacyTest: ReplicatorTest {

    // MARK: - End-to-end replication using the legacy API

    func testReplicationWithLegacyConfig() throws {
        let doc = createDocument("doc1")
        doc.setString("value", forKey: "key")
        try defaultCollection!.save(document: doc)

        // Configure with the deprecated init + addCollection, then actually replicate:
        let target = DatabaseEndpoint(database: otherDB!)
        var config = ReplicatorConfiguration(target: target)
        config.addCollection(defaultCollection!)
        config.replicatorType = .push

        run(config: config, expectedError: nil)

        // The doc should have been pushed to the other database's default collection:
        XCTAssertEqual(otherDB_defaultCollection!.count, 1)
        let saved = try otherDB_defaultCollection!.document(id: "doc1")
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.string(forKey: "key"), "value")
    }

    // MARK: - ReplicatorConfiguration construction

    func testInitWithDatabaseTarget() throws {
        let target = DatabaseEndpoint(database: otherDB!)
        var config = ReplicatorConfiguration(database: db, target: target)
        XCTAssertTrue(config.database === db)
        XCTAssertEqual(config.collections.count, 1)
        XCTAssertNotNil(config.collectionConfig(defaultCollection!))

        config.removeCollection(defaultCollection!)
        XCTAssertNil(config.collectionConfig(defaultCollection!))
        XCTAssertEqual(config.collections.count, 0)
    }

    // MARK: - Deprecated default-collection properties

    func testDeprecatedDefaultCollectionProperties() throws {
        let target = DatabaseEndpoint(database: otherDB!)
        var config = ReplicatorConfiguration(database: db, target: target)

        // Each deprecated property delegates to the default collection's config; verify both the
        // round-trip and that it actually wired through to collectionConfig(defaultCollection).
        config.channels = ["channelA"]
        XCTAssertEqual(config.channels, ["channelA"])
        XCTAssertEqual(config.collectionConfig(defaultCollection!)?.channels, ["channelA"])

        config.documentIDs = ["doc1"]
        XCTAssertEqual(config.documentIDs, ["doc1"])
        XCTAssertEqual(config.collectionConfig(defaultCollection!)?.documentIDs, ["doc1"])

        config.pushFilter = { (_, _) in return true }
        XCTAssertNotNil(config.pushFilter)
        XCTAssertNotNil(config.collectionConfig(defaultCollection!)?.pushFilter)

        config.pullFilter = { (_, _) in return true }
        XCTAssertNotNil(config.pullFilter)
        XCTAssertNotNil(config.collectionConfig(defaultCollection!)?.pullFilter)

        config.conflictResolver = ReplicatorLegacyConflictResolver()
        XCTAssertNotNil(config.conflictResolver)
        XCTAssertNotNil(config.collectionConfig(defaultCollection!)?.conflictResolver)
    }

    // MARK: - CollectionConfiguration deprecated init

    func testCollectionConfigurationDeprecatedInit() throws {
        var cc = CollectionConfiguration()
        XCTAssertNil(cc.collection)
        cc.channels = ["channelA"]
        XCTAssertEqual(cc.channels, ["channelA"])

        // Usable with the deprecated addCollection(_:config:):
        let target = DatabaseEndpoint(database: otherDB!)
        var config = ReplicatorConfiguration(target: target)
        config.addCollection(defaultCollection!, config: cc)
        XCTAssertEqual(config.collectionConfig(defaultCollection!)?.channels, ["channelA"])
    }

    // MARK: - Pending documents

    func testPendingDocumentIDs() throws {
        try defaultCollection!.save(document: createDocument("doc1"))
        try defaultCollection!.save(document: createDocument("doc2"))

        let target = DatabaseEndpoint(database: otherDB!)
        var config = ReplicatorConfiguration(database: db, target: target)
        config.replicatorType = .push

        // Pending documents are computed locally; no need to start the replicator.
        let replicator = Replicator(config: config)
        let pending = try replicator.pendingDocumentIds()
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.contains("doc1"))
        XCTAssertTrue(try replicator.isDocumentPending("doc1"))
    }

    // MARK: - P2P Listener configurations

    func testURLEndpointListenerConfigInitWithDatabase() throws {
        let config = URLEndpointListenerConfiguration(database: db)
        XCTAssertTrue(config.database === db)
        XCTAssertEqual(config.collections.count, 1)
    }

    func testMessageEndpointListenerConfigInitWithDatabase() throws {
        let config = MessageEndpointListenerConfiguration(database: db, protocolType: .messageStream)
        XCTAssertTrue(config.database === db)
        XCTAssertEqual(config.collections.count, 1)
        XCTAssertEqual(config.protocolType, .messageStream)
    }
}
