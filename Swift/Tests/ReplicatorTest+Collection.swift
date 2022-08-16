//
//  ReplicatorTest+Collection.swift
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

import XCTest
import CouchbaseLiteSwift

class ReplicatorTest_Collection: ReplicatorTest {
    override func setUpWithError() throws {
        try super.setUpWithError()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }
    
    // MARK: 8.13 Replicator Configuration
    
    func testCreateConfigWithDatabase() throws {
        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        
        let config = ReplicatorConfiguration(database: self.db, target: target)
        XCTAssertEqual(config.collections.count, 1)
        
        
        guard let col = try self.db.defaultCollection() else {
            XCTFail("Default collection is missing!")
            return
        }
        
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
        
        XCTAssertEqual(config.database.path, self.db.path)
    }
    
    func collectionConfig(_ config: ReplicatorConfiguration, col: Collection) -> CollectionConfiguration {
        guard let colConfig = config.collectionConfig(col) else {
            fatalError("Collection config is missing!")
        }
        
        return colConfig
    }
    
    func defaultCollection() throws -> Collection {
        guard let col = try self.db.defaultCollection() else {
            fatalError("Default collection is missing!")
        }
        
        return col
    }
    
    func testConfigWithDatabaseAndConflictResolver() throws {
        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        
        var config = ReplicatorConfiguration(database: self.db, target: target)
        
        let conflictResolver = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.remoteDocument
        })
        config.conflictResolver = conflictResolver
        XCTAssertNotNil(conflictResolver)
        
        var colConfig = collectionConfig(config, col: try defaultCollection())
        XCTAssert(conflictResolver === (config.conflictResolver as! TestConflictResolver))
        XCTAssert(conflictResolver === (colConfig.conflictResolver as! TestConflictResolver))
        
        // Update replicator.conflictResolver
        let conflictResolver2 = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.localDocument
        })
        XCTAssert(conflictResolver !== conflictResolver2)
        config.conflictResolver = conflictResolver2
        
        colConfig = collectionConfig(config, col: try defaultCollection())
        XCTAssert(conflictResolver2 === (config.conflictResolver as! TestConflictResolver))
        XCTAssert(conflictResolver2 === (colConfig.conflictResolver as! TestConflictResolver))
        
        // Update collectionConfig.conflictResolver
        let conflictResolver3 = TestConflictResolver({ (con: Conflict) -> Document? in
            return nil
        })
        XCTAssert(conflictResolver2 !== conflictResolver3)
        colConfig = collectionConfig(config, col: try defaultCollection())
        colConfig.conflictResolver = conflictResolver3
        config.addCollection(try defaultCollection(), config: colConfig)
        
        XCTAssert(conflictResolver3 === (config.conflictResolver as! TestConflictResolver))
        XCTAssert(conflictResolver3 === (colConfig.conflictResolver as! TestConflictResolver))
    }
    
    func testConfigWithDatabaseAndFilters() throws {
        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        
        var config = ReplicatorConfiguration(database: self.db, target: target)
        let filter1 = { (doc: Document, flags: DocumentFlags) in return true }
        let filter2 = { (doc: Document, flags: DocumentFlags) in return true }
        config.pushFilter = filter1
        config.pullFilter = nil
        config.channels = ["c1", "c2", "c3"]
        config.documentIDs = ["d1", "d2", "d3"]
        
        var colConfig = collectionConfig(config, col: try defaultCollection())
        XCTAssertEqual(colConfig.channels, ["c1", "c2", "c3"])
        XCTAssertEqual(colConfig.documentIDs, ["d1", "d2", "d3"])
        XCTAssertNotNil(colConfig.pushFilter)
        XCTAssertNil(colConfig.pullFilter)
        
        // Update replicator.filters
        config.pushFilter = nil
        config.pullFilter = filter2
        config.channels = ["c1"]
        config.documentIDs = ["d1"]
        
        colConfig = collectionConfig(config, col: try defaultCollection())
        XCTAssertEqual(colConfig.channels, ["c1"])
        XCTAssertEqual(colConfig.documentIDs, ["d1"])
        XCTAssertNil(colConfig.pushFilter)
        XCTAssertNotNil(colConfig.pullFilter)
        
        // Update collectionConfig.filters
        colConfig = collectionConfig(config, col: try defaultCollection())
        colConfig.pushFilter = filter1
        colConfig.pullFilter = filter2
        colConfig.channels = ["c1", "c2"]
        colConfig.documentIDs = ["d1", "d2"]
        config.addCollection(try defaultCollection(), config: colConfig)
        
        XCTAssertEqual(colConfig.channels, ["c1", "c2"])
        XCTAssertEqual(colConfig.documentIDs, ["d1", "d2"])
        XCTAssertNotNil(colConfig.pushFilter)
        XCTAssertNotNil(colConfig.pullFilter)
    }
    
    // Note: testCreateConfigWithEndpointOnly:  can't test due to fatalError
    
    func testAddCollectionsWithoutCollectionConfig() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
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
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
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
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
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
        
        // validate the config1 for NULL values
        var config1 = collectionConfig(config, col: col1a)
        XCTAssertNil(config1.conflictResolver)
        XCTAssertNil(config1.channels)
        XCTAssertNil(config1.documentIDs)
        XCTAssertNil(config1.pushFilter)
        XCTAssertNil(config1.pullFilter)
        
        // vlaidate the config2 for valid values
        var config2 = collectionConfig(config, col: col1b)
        XCTAssertNotNil(config2.pushFilter)
        XCTAssertNotNil(config2.pullFilter)
        XCTAssertEqual(config2.channels, ["channel1", "channel2", "channel3"])
        XCTAssertEqual(config2.documentIDs, ["doc1", "doc2", "doc3"])
        XCTAssert((config2.conflictResolver as! TestConflictResolver) === conflictResolver)
        
        // Update in reverse
        config.addCollection(col1a, config: colConfig)
        config.addCollection(col1b)
        
        // validate the config1 for valid values
        config1 = collectionConfig(config, col: col1a)
        XCTAssertNotNil(config1.pushFilter)
        XCTAssertNotNil(config1.pullFilter)
        XCTAssertEqual(config1.channels, ["channel1", "channel2", "channel3"])
        XCTAssertEqual(config1.documentIDs, ["doc1", "doc2", "doc3"])
        XCTAssert((config1.conflictResolver as! TestConflictResolver) === conflictResolver)
        
        // vlaidate the config2 for NULL
        config2 = collectionConfig(config, col: col1b)
        XCTAssertNil(config2.conflictResolver)
        XCTAssertNil(config2.channels)
        XCTAssertNil(config2.documentIDs)
        XCTAssertNil(config2.pushFilter)
        XCTAssertNil(config2.pullFilter)
    }
    
    func testRemoveCollection() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
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
        config.addCollection(col1b, config: colConfig)
        
        config.addCollection(col1a, config: colConfig)
        config.addCollection(col1b, config: colConfig)
        
        XCTAssertEqual(config.collections.count, 2)
        XCTAssert(config.collections.contains(where: { $0.name == "colA" && $0.scope.name == "scopeA" }))
        XCTAssert(config.collections.contains(where: { $0.name == "colB" && $0.scope.name == "scopeA" }))
        
        // validate the config1 for valid values
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
    }
    
    // exception causiung the memory leak
    // TODO: https://issues.couchbase.com/browse/CBL-3576
    func _testAddCollectionsFromDifferentDatabaseInstances() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        
        let db2 = try openDB(name: databaseName)
        let col1b = try db2.createCollection(name: "colB", scope: "scopeA")
        
        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        var config = ReplicatorConfiguration(target: target)
        
        expectExcepion(exception: .invalidArgumentException) {
            config.addCollections([col1a, col1b])
        }
        
        XCTAssertEqual(config.collections.count, 0)
        
        config.addCollection(col1a)
        
        XCTAssertEqual(config.collections.count, 1)
        XCTAssert(config.collections.contains(where: { $0.name == "colA" && $0.scope.name == "scopeA" }))
        
        expectExcepion(exception: .invalidArgumentException) {
            config.addCollection(col1b)
        }
    }
    
    // memory leak with NSException
    // TODO: https://issues.couchbase.com/browse/CBL-3576
    func _testAddDeletedCollections() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        
        let db2 = try openDB(name: databaseName)
        let col1b = try db2.createCollection(name: "colB", scope: "scopeA")
        
        try db2.deleteCollection(name: "colB", scope: "scopeA")
        
        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        var config = ReplicatorConfiguration(target: target)
        
        expectExcepion(exception: .invalidArgumentException) {
            config.addCollections([col1a, col1b])
        }
        
        XCTAssertEqual(config.collections.count, 0)
        
        config.addCollection(col1a)
        
        XCTAssertEqual(config.collections.count, 1)
        XCTAssert(config.collections.contains(where: { $0.name == "colA" && $0.scope.name == "scopeA" }))
        
        expectExcepion(exception: .invalidArgumentException) {
            config.addCollection(col1b)
        }
    }
    
#if COUCHBASE_ENTERPRISE
    
    // MARK: 8.14 Replicator
    
    func testCollectionSingleShotPushReplication() throws {
        try testCollectionPushReplication(continous: false)
    }
    
    func testCollectionContinuousPushReplication() throws {
        try testCollectionPushReplication(continous: true)
    }
    
    func testCollectionPushReplication(continous: Bool) throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        let col2b = try oDB.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 5)
        try createDocNumbered(col1b, start: 10, num: 3)
        XCTAssertEqual(col1a.count, 5)
        XCTAssertEqual(col1b.count, 3)
        XCTAssertEqual(col2a.count, 0)
        XCTAssertEqual(col2b.count, 0)
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .push, continuous: continous)
        config.addCollections([col1a, col1b])
        
        run(config: config, expectedError: nil)
        XCTAssertEqual(col1a.count, 5)
        XCTAssertEqual(col1b.count, 3)
        XCTAssertEqual(col2a.count, 5)
        XCTAssertEqual(col2b.count, 3)
    }
    
    func testCollectionSingleShotPullReplication() throws {
        try testCollectionPullReplication(continous: false)
    }
    
    func testCollectionContinuousPullReplication() throws {
        try testCollectionPullReplication(continous: true)
    }
    
    func testCollectionPullReplication(continous: Bool) throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        let col2b = try oDB.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col2a, start: 0, num: 10)
        try createDocNumbered(col2b, start: 10, num: 10)
        XCTAssertEqual(col1a.count, 0)
        XCTAssertEqual(col1b.count, 0)
        XCTAssertEqual(col2a.count, 10)
        XCTAssertEqual(col2b.count, 10)
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .pull, continuous: continous)
        config.addCollections([col1a, col1b])
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col1a.count, 10)
        XCTAssertEqual(col1b.count, 10)
        XCTAssertEqual(col2a.count, 10)
        XCTAssertEqual(col2b.count, 10)
    }
    
    func testCollectionSingleShotPushPullReplication() throws {
        try testCollectionPushPullReplication(continous: false)
    }
    
    func testCollectionContinuousPushPullReplication() throws {
        try testCollectionPushPullReplication(continous: true)
    }
    
    func testCollectionPushPullReplication(continous: Bool) throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        let col2b = try oDB.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 2)
        try createDocNumbered(col2a, start: 10, num: 5)
        
        try createDocNumbered(col1b, start: 5, num: 3)
        try createDocNumbered(col2b, start: 15, num: 8)
        
        XCTAssertEqual(col1a.count, 2)
        XCTAssertEqual(col2a.count, 5)
        
        XCTAssertEqual(col1b.count, 3)
        XCTAssertEqual(col2b.count, 8)
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .pushAndPull, continuous: continous)
        config.addCollections([col1a, col1b])
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col1a.count, 7)
        XCTAssertEqual(col2a.count, 7)
        XCTAssertEqual(col1b.count, 11)
        XCTAssertEqual(col2b.count, 11)
    }
    
    func testCollectionResetReplication() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        
        try createDocNumbered(col2a, start: 0, num: 5)
        XCTAssertEqual(col1a.count, 0)
        XCTAssertEqual(col2a.count, 5)
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .pull, continuous: false)
        config.addCollections([col1a])
        run(config: config, expectedError: nil)
        XCTAssertEqual(col1a.count, 5)
        XCTAssertEqual(col2a.count, 5)
        
        // Purge all documents from the colA of the database A.
        for i in 0..<5 {
            try col1a.purge(id: "doc\(i)")
        }
        run(config: config, expectedError: nil)
        XCTAssertEqual(col1a.count, 0)
        XCTAssertEqual(col2a.count, 5)
        
        run(config: config, reset: true, expectedError: nil)
        XCTAssertEqual(col1a.count, 5)
        XCTAssertEqual(col2a.count, 5)
    }
    
    func testCollectionDefaultConflictResolver() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        
        let doc1 = try createDocument("doc1")
        try col1a.save(document: doc1)
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .pushAndPull, continuous: false)
        config.addCollections([col1a])
        run(config: config, expectedError: nil)
        
        let mdoc1 = try col1a.document(id: "doc1")!.toMutable()
        mdoc1.setString("update1", forKey: "update")
        try col1a.save(document: mdoc1)
        
        var mdoc2 = try col2a.document(id: "doc1")!.toMutable()
        mdoc2.setString("update2.1", forKey: "update")
        try col2a.save(document: mdoc2)
        
        mdoc2 = try col2a.document(id: "doc1")!.toMutable()
        mdoc2.setString("update2.2", forKey: "update")
        try col2a.save(document: mdoc2)
        
        run(config: config, expectedError: nil)
        
        let doc = try col1a.document(id: "doc1")
        XCTAssertEqual(doc!.string(forKey: "update"), "update2.2")
    }
    
    func testCollectionConflictResolver() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        let col2b = try oDB.createCollection(name: "colB", scope: "scopeA")
        
        // Create a document with id "doc1" in colA and colB of the database A.
        let doc1a = try createDocument("doc1")
        doc1a.setString("update0", forKey: "update")
        try col1a.save(document: doc1a)
        
        let doc1b = try createDocument("doc1")
        doc1b.setString("update0", forKey: "update")
        try col1b.save(document: doc1b)
        
        let conflictResolver1 = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.localDocument
        })
        let conflictResolver2 = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.remoteDocument
        })
        
        var colConfig1 = CollectionConfiguration()
        colConfig1.conflictResolver = conflictResolver1
        
        var colConfig2 = CollectionConfiguration()
        colConfig2.conflictResolver = conflictResolver2
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .pushAndPull, continuous: false)
        config.addCollection(col1a, config: colConfig1)
        config.addCollection(col1b, config: colConfig2)
        run(config: config, expectedError: nil)
        
        // Update "doc1" in colA and colB of database A.
        let mdoc1a = try col1a.document(id: "doc1")!.toMutable()
        mdoc1a.setString("update1a", forKey: "update")
        try col1a.save(document: mdoc1a)
        
        var mdoc2a = try col2a.document(id: "doc1")!.toMutable()
        mdoc2a.setString("update2a", forKey: "update")
        try col2a.save(document: mdoc2a)
        
        // Update "doc1" in colA and colB of database B.
        let mdoc1b = try col1b.document(id: "doc1")!.toMutable()
        mdoc1b.setString("update1b", forKey: "update")
        try col1b.save(document: mdoc1b)
        
        var mdoc2b = try col2b.document(id: "doc1")!.toMutable()
        mdoc2b.setString("update2b", forKey: "update")
        try col2b.save(document: mdoc2b)
        
        run(config: config, expectedError: nil)
        
        // verify the results
        var docA = try col1a.document(id: "doc1")
        XCTAssertEqual(docA!.string(forKey: "update"), "update1a")
        docA = try col2a.document(id: "doc1")
        XCTAssertEqual(docA!.string(forKey: "update"), "update2a")
        
        var docB = try col1b.document(id: "doc1")
        XCTAssertEqual(docB!.string(forKey: "update"), "update2b")
        docB = try col2b.document(id: "doc1")
        XCTAssertEqual(docB!.string(forKey: "update"), "update2b")
    }
    
    func testCollectionPushFilter() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        let col2b = try oDB.createCollection(name: "colB", scope: "scopeA")
        
        // Create some documents in colA and colB of the database A.
        try createDocNumbered(col1a, start: 0, num: 10)
        try createDocNumbered(col1b, start: 10, num: 10)
        
        var colConfig = CollectionConfiguration()
        colConfig.pushFilter = { (doc: Document, flags: DocumentFlags) in
            if doc.collection!.name == "colA" {
                return doc.int(forKey: "number1") < 5
            } else {
                return doc.int(forKey: "number1") >= 15
            }
        }
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .push, continuous: false)
        config.addCollections([col1a, col1b], config: colConfig)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col1a.count, 10)
        XCTAssertEqual(col1b.count, 10)
        XCTAssertEqual(col2a.count, 5)
        XCTAssertEqual(col2b.count, 5)
    }
    
    func testCollectionPullFilter() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        let col2b = try oDB.createCollection(name: "colB", scope: "scopeA")
        
        // Create some documents in colA and colB of the database A.
        try createDocNumbered(col2a, start: 0, num: 10)
        try createDocNumbered(col2b, start: 10, num: 10)
        
        var colConfig = CollectionConfiguration()
        colConfig.pullFilter = { (doc: Document, flags: DocumentFlags) in
            if doc.collection!.name == "colA" {
                return doc.int(forKey: "number1") < 5
            } else {
                return doc.int(forKey: "number1") >= 15
            }
        }
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .pull, continuous: false)
        config.addCollections([col1a, col1b], config: colConfig)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col1a.count, 5)
        XCTAssertEqual(col1b.count, 5)
        XCTAssertEqual(col2a.count, 10)
        XCTAssertEqual(col2b.count, 10)
    }
    
    func testCollectionDocumentIDsPushFilter() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        let col2b = try oDB.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 5)
        try createDocNumbered(col1b, start: 10, num: 5)
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .push, continuous: false)
        
        var colConfig1 = CollectionConfiguration()
        colConfig1.documentIDs = ["doc1", "doc2"]
        
        var colConfig2 = CollectionConfiguration()
        colConfig2.documentIDs = ["doc10", "doc11", "doc13"]
        
        config.addCollection(col1a, config: colConfig1)
        config.addCollection(col1b, config: colConfig2)
        
        run(config: config, expectedError: nil)
        XCTAssertEqual(col1a.count, 5)
        XCTAssertEqual(col1b.count, 5)
        XCTAssertEqual(col2a.count, 2)
        XCTAssertEqual(col2b.count, 3)
    }
    
    func testCollectionDocumentIDsPullFilter() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        let col2b = try oDB.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col2a, start: 0, num: 5)
        try createDocNumbered(col2b, start: 10, num: 5)
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .pull, continuous: false)
        
        var colConfig1 = CollectionConfiguration()
        colConfig1.documentIDs = ["doc1", "doc2"]
        
        var colConfig2 = CollectionConfiguration()
        colConfig2.documentIDs = ["doc10", "doc11", "doc13"]
        
        config.addCollection(col1a, config: colConfig1)
        config.addCollection(col1b, config: colConfig2)
        
        run(config: config, expectedError: nil)
        XCTAssertEqual(col1a.count, 2)
        XCTAssertEqual(col1b.count, 3)
        XCTAssertEqual(col2a.count, 5)
        XCTAssertEqual(col2b.count, 5)
    }
    
    func testCollectionGetPendingDocumentIDs() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try oDB.createCollection(name: "colA", scope: "scopeA")
        let col2b = try oDB.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 10)
        try createDocNumbered(col1b, start: 10, num: 5)
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .push, continuous: false)
        config.addCollections([col1a, col1b])
        let r = Replicator(config: config)
        
        var docIds1a = try r.pendingDocumentIds(collection: col1a)
        var docIds1b = try r.pendingDocumentIds(collection: col1b)
        XCTAssertEqual(docIds1a.count, 10)
        XCTAssertEqual(docIds1b.count, 5)
        
        run(replicator: r, expectedError: nil)
        
        docIds1a = try r.pendingDocumentIds(collection: col1a)
        docIds1b = try r.pendingDocumentIds(collection: col1b)
        XCTAssertEqual(docIds1a.count, 0)
        XCTAssertEqual(docIds1b.count, 0)
        
        let mdoc1a = try col1a.document(id: "doc1")!.toMutable()
        mdoc1a.setString("update1", forKey: "update")
        try col1a.save(document: mdoc1a)
        
        docIds1a = try r.pendingDocumentIds(collection: col1a)
        XCTAssertEqual(docIds1a.count, 1)
        XCTAssert(docIds1a.contains(where: { $0 == "doc1" }))
        
        let mdoc1b = try col1b.document(id: "doc12")!.toMutable()
        mdoc1b.setString("update2", forKey: "update")
        try col1b.save(document: mdoc1b)
        
        docIds1b = try r.pendingDocumentIds(collection: col1b)
        XCTAssertEqual(docIds1b.count, 1)
        XCTAssert(docIds1b.contains(where: { $0 == "doc12" }))
    }
    
    func testCollectionIsDocumentPending() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let _ = try oDB.createCollection(name: "colA", scope: "scopeA")
        let _ = try oDB.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 10)
        try createDocNumbered(col1b, start: 10, num: 5)
        
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .push, continuous: false)
        config.addCollections([col1a, col1b])
        let r = Replicator(config: config)
        
        // make sure all docs are pending
        for i in 0..<10 {
            XCTAssert(try r.isDocumentPending("doc\(i)", collection: col1a))
        }
        for i in 10..<15 {
            XCTAssert(try r.isDocumentPending("doc\(i)", collection: col1b))
        }
        
        run(replicator: r, expectedError: nil)
        
        // make sure, no document is pending
        for i in 0..<10 {
            XCTAssertFalse(try r.isDocumentPending("doc\(i)", collection: col1a))
        }
        for i in 10..<15 {
            XCTAssertFalse(try r.isDocumentPending("doc\(i)", collection: col1b))
        }
        
        // Update a document in colA.
        let mdoc1a = try col1a.document(id: "doc1")!.toMutable()
        mdoc1a.setString("update1", forKey: "update")
        try col1a.save(document: mdoc1a)
        
        XCTAssert(try r.isDocumentPending("doc1", collection: col1a))
        
        // Delete a document in colB.
        let mdoc1b = try col1b.document(id: "doc12")!.toMutable()
        try col1b.delete(document: mdoc1b)
        
        XCTAssert(try r.isDocumentPending("doc12", collection: col1b))
    }
    
#endif
    
}
