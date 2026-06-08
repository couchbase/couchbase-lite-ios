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

    // MARK: - Replicator.removeChangeListener(withToken:)

    func testRemoveReplicatorChangeListenerWithToken() throws {
        let target = DatabaseEndpoint(database: otherDB!)
        var config = ReplicatorConfiguration(target: target)
        config.addCollection(defaultCollection!)
        config.replicatorType = .push

        let repl = Replicator(config: config)
        let token = repl.addChangeListener { (change) in }

        // Remove using the deprecated API; should not crash.
        repl.removeChangeListener(withToken: token)
    }

    // MARK: - MessageEndpointListener.removeChangeListener(token:)

    func testRemoveMessageEndpointListenerChangeListener() throws {
        let config = MessageEndpointListenerConfiguration(collections: [defaultCollection!], protocolType: .messageStream)
        let listener = MessageEndpointListener(config: config)
        let token = listener.addChangeListener { (change) in }

        // Remove using the deprecated API; should not crash.
        listener.removeChangeListener(token: token)
    }

    // MARK: - ReplicatorConfiguration collection management (deprecated, ported from 3.3)

    private func collectionConfig(_ config: ReplicatorConfiguration, col: Collection) -> CollectionConfiguration {
        guard let colConfig = config.collectionConfig(col) else {
            fatalError("Collection config is missing!")
        }

        return colConfig
    }

    func testCreateConfigWithDatabase() throws {
        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)

        let config = ReplicatorConfiguration(database: db, target: target)
        XCTAssertEqual(config.collections.count, 1)

        let col = try db.defaultCollection()
        XCTAssertEqual(col, config.collections[0])
        XCTAssertEqual(col.name, config.collections[0].name)
        XCTAssertEqual(col.scope.name, config.collections[0].scope.name)

        guard let colConfig = config.collectionConfig(col) else {
            XCTFail("Missing default collection")
            return
        }

        XCTAssertNil(colConfig.documentIDs)
        XCTAssertNil(colConfig.channels)
        XCTAssertNil(colConfig.conflictResolver)
        XCTAssertNil(colConfig.pushFilter)
        XCTAssertNil(colConfig.pullFilter)

        XCTAssertEqual(config.database.path, db.path)
    }

    func testConfigWithDatabaseAndConflictResolver() throws {
        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        var config = ReplicatorConfiguration(database: db, target: target)

        let conflictResolver = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.remoteDocument
        })
        config.conflictResolver = conflictResolver
        XCTAssertNotNil(conflictResolver)

        var colConfig = collectionConfig(config, col: defaultCollection!)
        XCTAssert(conflictResolver === (config.conflictResolver as! TestConflictResolver))
        XCTAssert(conflictResolver === (colConfig.conflictResolver as! TestConflictResolver))

        // Update replicator.conflictResolver
        let conflictResolver2 = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.localDocument
        })
        XCTAssert(conflictResolver !== conflictResolver2)
        config.conflictResolver = conflictResolver2

        colConfig = collectionConfig(config, col: defaultCollection!)
        XCTAssert(conflictResolver2 === (config.conflictResolver as! TestConflictResolver))
        XCTAssert(conflictResolver2 === (colConfig.conflictResolver as! TestConflictResolver))

        // Update collectionConfig.conflictResolver
        let conflictResolver3 = TestConflictResolver({ (con: Conflict) -> Document? in
            return nil
        })
        XCTAssert(conflictResolver2 !== conflictResolver3)
        colConfig = collectionConfig(config, col: defaultCollection!)
        colConfig.conflictResolver = conflictResolver3
        config.addCollection(defaultCollection!, config: colConfig)

        XCTAssert(conflictResolver3 === (config.conflictResolver as! TestConflictResolver))
        XCTAssert(conflictResolver3 === (colConfig.conflictResolver as! TestConflictResolver))
    }

    func testConfigWithDatabaseAndFilters() throws {
        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)

        var config = ReplicatorConfiguration(database: db, target: target)
        let filter1 = { (doc: Document, flags: DocumentFlags) in return true }
        let filter2 = { (doc: Document, flags: DocumentFlags) in return true }
        config.pushFilter = filter1
        config.pullFilter = nil
        config.channels = ["c1", "c2", "c3"]
        config.documentIDs = ["d1", "d2", "d3"]

        var colConfig = collectionConfig(config, col: defaultCollection!)
        XCTAssertEqual(colConfig.channels, ["c1", "c2", "c3"])
        XCTAssertEqual(colConfig.documentIDs, ["d1", "d2", "d3"])
        XCTAssertNotNil(colConfig.pushFilter)
        XCTAssertNil(colConfig.pullFilter)

        // Update replicator.filters
        config.pushFilter = nil
        config.pullFilter = filter2
        config.channels = ["c1"]
        config.documentIDs = ["d1"]

        colConfig = collectionConfig(config, col: defaultCollection!)
        XCTAssertEqual(colConfig.channels, ["c1"])
        XCTAssertEqual(colConfig.documentIDs, ["d1"])
        XCTAssertNil(colConfig.pushFilter)
        XCTAssertNotNil(colConfig.pullFilter)

        // Update collectionConfig.filters
        colConfig = collectionConfig(config, col: defaultCollection!)
        colConfig.pushFilter = filter1
        colConfig.pullFilter = filter2
        colConfig.channels = ["c1", "c2"]
        colConfig.documentIDs = ["d1", "d2"]
        config.addCollection(defaultCollection!, config: colConfig)

        XCTAssertEqual(colConfig.channels, ["c1", "c2"])
        XCTAssertEqual(colConfig.documentIDs, ["d1", "d2"])
        XCTAssertNotNil(colConfig.pushFilter)
        XCTAssertNotNil(colConfig.pullFilter)
    }

    func testAddCollectionsWithoutCollectionConfig() throws {
        let col1a = try db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try db.createCollection(name: "colB", scope: "scopeA")

        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        var config = ReplicatorConfiguration(target: target)
        config.addCollections([col1a, col1b])

        XCTAssertEqual(config.collections.count, 2)
        XCTAssert(config.collections.contains(where: { $0.name == "colA" && $0.scope.name == "scopeA" }))
        XCTAssert(config.collections.contains(where: { $0.name == "colB" && $0.scope.name == "scopeA" }))

        let config1 = collectionConfig(config, col: col1a)
        let config2 = collectionConfig(config, col: col1b)

        XCTAssertNil(config1.conflictResolver)
        XCTAssertNil(config1.channels)
        XCTAssertNil(config1.documentIDs)
        XCTAssertNil(config1.pushFilter)
        XCTAssertNil(config1.pullFilter)

        XCTAssertNil(config2.conflictResolver)
        XCTAssertNil(config2.channels)
        XCTAssertNil(config2.documentIDs)
        XCTAssertNil(config2.pushFilter)
        XCTAssertNil(config2.pullFilter)
    }

    func testAddCollectionsWithCollectionConfig() throws {
        let col1a = try db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try db.createCollection(name: "colB", scope: "scopeA")

        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        var config = ReplicatorConfiguration(target: target)

        var colConfig = CollectionConfiguration()
        let conflictResolver = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.remoteDocument
        })
        let filter1 = { (doc: Document, flags: DocumentFlags) in return true }
        let filter2 = { (doc: Document, flags: DocumentFlags) in return true }
        colConfig.conflictResolver = conflictResolver
        colConfig.pushFilter = filter1
        colConfig.pullFilter = filter2
        colConfig.channels = ["channel1", "channel2", "channel3"]
        colConfig.documentIDs = ["doc1", "doc2", "doc3"]

        config.addCollections([col1a, col1b], config: colConfig)

        XCTAssertEqual(config.collections.count, 2)
        XCTAssert(config.collections.contains(where: { $0.name == "colA" && $0.scope.name == "scopeA" }))
        XCTAssert(config.collections.contains(where: { $0.name == "colB" && $0.scope.name == "scopeA" }))

        let config1 = collectionConfig(config, col: col1a)
        let config2 = collectionConfig(config, col: col1b)

        XCTAssertNotNil(config1.pushFilter)
        XCTAssertNotNil(config1.pullFilter)
        XCTAssertEqual(config1.channels, ["channel1", "channel2", "channel3"])
        XCTAssertEqual(config1.documentIDs, ["doc1", "doc2", "doc3"])
        XCTAssert((config1.conflictResolver as! TestConflictResolver) === conflictResolver)

        XCTAssertNotNil(config2.pushFilter)
        XCTAssertNotNil(config2.pullFilter)
        XCTAssertEqual(config2.channels, ["channel1", "channel2", "channel3"])
        XCTAssertEqual(config2.documentIDs, ["doc1", "doc2", "doc3"])
        XCTAssert((config2.conflictResolver as! TestConflictResolver) === conflictResolver)
    }

    func testAddUpdateCollection() throws {
        let col1a = try db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try db.createCollection(name: "colB", scope: "scopeA")

        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        var config = ReplicatorConfiguration(target: target)

        // add collection 1 with empty config
        config.addCollection(col1a)

        // Create and add Collection config for collection 2
        var colConfig = CollectionConfiguration()
        let conflictResolver = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.remoteDocument
        })
        let filter1 = { (doc: Document, flags: DocumentFlags) in return true }
        let filter2 = { (doc: Document, flags: DocumentFlags) in return true }
        colConfig.conflictResolver = conflictResolver
        colConfig.pushFilter = filter1
        colConfig.pullFilter = filter2
        colConfig.channels = ["channel1", "channel2", "channel3"]
        colConfig.documentIDs = ["doc1", "doc2", "doc3"]
        config.addCollection(col1b, config: colConfig)

        XCTAssertEqual(config.collections.count, 2)
        XCTAssert(config.collections.contains(where: { $0.name == "colA" && $0.scope.name == "scopeA" }))
        XCTAssert(config.collections.contains(where: { $0.name == "colB" && $0.scope.name == "scopeA" }))

        // validate config1 for nil values
        var config1 = collectionConfig(config, col: col1a)
        XCTAssertNil(config1.conflictResolver)
        XCTAssertNil(config1.channels)
        XCTAssertNil(config1.documentIDs)
        XCTAssertNil(config1.pushFilter)
        XCTAssertNil(config1.pullFilter)

        // validate config2 for valid values
        var config2 = collectionConfig(config, col: col1b)
        XCTAssertNotNil(config2.pushFilter)
        XCTAssertNotNil(config2.pullFilter)
        XCTAssertEqual(config2.channels, ["channel1", "channel2", "channel3"])
        XCTAssertEqual(config2.documentIDs, ["doc1", "doc2", "doc3"])
        XCTAssert((config2.conflictResolver as! TestConflictResolver) === conflictResolver)

        // Update in reverse
        config.addCollection(col1a, config: colConfig)
        config.addCollection(col1b)

        // validate config1 for valid values
        config1 = collectionConfig(config, col: col1a)
        XCTAssertNotNil(config1.pushFilter)
        XCTAssertNotNil(config1.pullFilter)
        XCTAssertEqual(config1.channels, ["channel1", "channel2", "channel3"])
        XCTAssertEqual(config1.documentIDs, ["doc1", "doc2", "doc3"])
        XCTAssert((config1.conflictResolver as! TestConflictResolver) === conflictResolver)

        // validate config2 for nil
        config2 = collectionConfig(config, col: col1b)
        XCTAssertNil(config2.conflictResolver)
        XCTAssertNil(config2.channels)
        XCTAssertNil(config2.documentIDs)
        XCTAssertNil(config2.pushFilter)
        XCTAssertNil(config2.pullFilter)
    }

    func testRemoveCollection() throws {
        let col1a = try db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try db.createCollection(name: "colB", scope: "scopeA")

        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        var config = ReplicatorConfiguration(target: target)

        // Create and add Collection config for both collections.
        var colConfig = CollectionConfiguration()
        let conflictResolver = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.remoteDocument
        })
        let filter1 = { (doc: Document, flags: DocumentFlags) in return true }
        let filter2 = { (doc: Document, flags: DocumentFlags) in return true }
        colConfig.conflictResolver = conflictResolver
        colConfig.pushFilter = filter1
        colConfig.pullFilter = filter2
        colConfig.channels = ["channel1", "channel2", "channel3"]
        colConfig.documentIDs = ["doc1", "doc2", "doc3"]

        config.addCollection(col1a, config: colConfig)
        config.addCollection(col1b, config: colConfig)

        XCTAssertEqual(config.collections.count, 2)
        XCTAssert(config.collections.contains(where: { $0.name == "colA" && $0.scope.name == "scopeA" }))
        XCTAssert(config.collections.contains(where: { $0.name == "colB" && $0.scope.name == "scopeA" }))

        // validate config1 for valid values
        let config1 = collectionConfig(config, col: col1a)
        XCTAssertNotNil(config1.pushFilter)
        XCTAssertNotNil(config1.pullFilter)
        XCTAssertEqual(config1.channels, ["channel1", "channel2", "channel3"])
        XCTAssertEqual(config1.documentIDs, ["doc1", "doc2", "doc3"])
        XCTAssert((config1.conflictResolver as! TestConflictResolver) === conflictResolver)

        let config2 = collectionConfig(config, col: col1b)
        XCTAssertNotNil(config2.pushFilter)
        XCTAssertNotNil(config2.pullFilter)
        XCTAssertEqual(config2.channels, ["channel1", "channel2", "channel3"])
        XCTAssertEqual(config2.documentIDs, ["doc1", "doc2", "doc3"])
        XCTAssert((config2.conflictResolver as! TestConflictResolver) === conflictResolver)

        config.removeCollection(col1b)

        XCTAssertEqual(config.collections.count, 1)
        XCTAssert(config.collections.contains(where: { $0.name == "colA" && $0.scope.name == "scopeA" }))

        XCTAssertNil(config.collectionConfig(col1b))

        // remove a non-existing collection
        config.removeCollection(col1b)
        XCTAssertEqual(config.collections.count, 1)
        XCTAssert(config.collections.contains(where: { $0.name == "colA" && $0.scope.name == "scopeA" }))
    }
}
