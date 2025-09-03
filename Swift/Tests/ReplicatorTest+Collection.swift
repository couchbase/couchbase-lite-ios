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
@testable import CouchbaseLiteSwift

class ReplicatorTest_Collection: ReplicatorTest {
    override func setUpWithError() throws {
        try super.setUpWithError()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }
    
    // MARK: 8.13 Replicator Configuration
    
    func testCreateConfigWithCollection() throws {
        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        
        let config = self.config(collections: [col1a], target: target)
        
        XCTAssertEqual(config.collections.count, 1)
        XCTAssertEqual(col1a, config.collections[0].collection)
    
        let colConfig = config.collections.first
        XCTAssertNotNil(colConfig)
        
        XCTAssertEqual(colConfig!.collection.fullName, col1a.fullName)
        XCTAssertNil(colConfig!.documentIDs)
        XCTAssertNil(colConfig!.channels)
        XCTAssertNil(colConfig!.conflictResolver)
        XCTAssertNil(colConfig!.pushFilter)
        XCTAssertNil(colConfig!.pullFilter)
    }
    
    // fatal error! can't be unit tested.
    func _testCollectionsFromDifferentDatabaseInstances() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        
        let db2 = try openDB(name: databaseName)
        let col1b = try db2.createCollection(name: "colB", scope: "scopeA")
        
        let url = URL(string: "wss://foo")!
        let target = URLEndpoint(url: url)
        
        let colConfigs = CollectionConfiguration.fromCollections([col1a, col1b])
       
        
        expectException(exception: .invalidArgumentException) {
            let _ = ReplicatorConfiguration(collections: colConfigs, target: target)
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
        let totalDocs = 10
        
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: totalDocs)
        try createDocNumbered(col1b, start: 10, num: totalDocs)
        XCTAssertEqual(col1a.count, UInt64(totalDocs))
        XCTAssertEqual(col1b.count, UInt64(totalDocs))
        XCTAssertEqual(col2a.count, 0)
        XCTAssertEqual(col2b.count, 0)
        
        try createDocNumbered(defaultCollection!, start: 20, num: totalDocs)
        XCTAssertEqual(defaultCollection!.count, UInt64(totalDocs))
        XCTAssertEqual(otherDB_defaultCollection!.count, 0)
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [col1a, col1b, defaultCollection!], target: target, type: .push, continuous: continous)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col2a.count, UInt64(totalDocs))
        XCTAssertEqual(col2b.count, UInt64(totalDocs))
        XCTAssertEqual(col1a.count, UInt64(totalDocs))
        XCTAssertEqual(col1b.count, UInt64(totalDocs))
        XCTAssertEqual(defaultCollection!.count, UInt64(totalDocs))
        XCTAssertEqual(otherDB_defaultCollection!.count, UInt64(totalDocs))
    }
    
    func testCollectionSingleShotPullReplication() throws {
        try testCollectionPullReplication(continous: false)
    }
    
    func testCollectionContinuousPullReplication() throws {
        try testCollectionPullReplication(continous: true)
    }
    
    func testCollectionPullReplication(continous: Bool) throws {
        let totalDocs = 10
        
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col2a, start: 0, num: totalDocs)
        try createDocNumbered(col2b, start: 10, num: totalDocs)
        XCTAssertEqual(col2a.count, UInt64(totalDocs))
        XCTAssertEqual(col2b.count, UInt64(totalDocs))
        XCTAssertEqual(col1a.count, 0)
        XCTAssertEqual(col1b.count, 0)
        
        try createDocNumbered(otherDB_defaultCollection!, start: 20, num: totalDocs)
        XCTAssertEqual(otherDB_defaultCollection!.count, UInt64(totalDocs))
        XCTAssertEqual(defaultCollection!.count, 0)
        
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [col1a, col1b, defaultCollection!], target: target, type: .pull, continuous: continous)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col2a.count, UInt64(totalDocs))
        XCTAssertEqual(col2b.count, UInt64(totalDocs))
        XCTAssertEqual(col1a.count, UInt64(totalDocs))
        XCTAssertEqual(col1b.count, UInt64(totalDocs))
        XCTAssertEqual(defaultCollection!.count, UInt64(totalDocs))
        XCTAssertEqual(otherDB_defaultCollection!.count, UInt64(totalDocs))
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
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 2)
        try createDocNumbered(col2a, start: 10, num: 5)
        
        try createDocNumbered(col1b, start: 5, num: 3)
        try createDocNumbered(col2b, start: 15, num: 8)
        
        XCTAssertEqual(col1a.count, 2)
        XCTAssertEqual(col2a.count, 5)
        
        XCTAssertEqual(col1b.count, 3)
        XCTAssertEqual(col2b.count, 8)
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [col1a, col1b], target: target, type: .pushAndPull, continuous: continous)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col1a.count, 7)
        XCTAssertEqual(col2a.count, 7)
        XCTAssertEqual(col1b.count, 11)
        XCTAssertEqual(col2b.count, 11)
    }
    
    func testCollectionResetReplication() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        
        try createDocNumbered(col2a, start: 0, num: 5)
        XCTAssertEqual(col1a.count, 0)
        XCTAssertEqual(col2a.count, 5)
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [col1a], target: target, type: .pull, continuous: false)
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
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        
        let doc1 = createDocument("doc1")
        try col1a.save(document: doc1)
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [col1a], target: target, type: .pushAndPull, continuous: false)
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
        
        let r = Replicator(config: config)
        var count = 0
        r.addDocumentReplicationListener { docReplication in
            count = count + 1
            
            XCTAssertEqual(docReplication.documents.count, 1)
            let doc = docReplication.documents[0]
            if count == 1 {
                XCTAssertNil(doc.error)
            } else {
                XCTAssertEqual((doc.error as? NSError)?.code, CBLError.httpConflict)
            }
            
        }
        run(replicator: r, expectedError: nil)
        
        let doc = try col1a.document(id: "doc1")
        XCTAssertEqual(doc!.string(forKey: "update"), "update2.2")
    }
    
    func testCollectionConflictResolver() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        // Create a document with id "doc1" in colA and colB of the database A.
        let doc1a = createDocument("doc1")
        doc1a.setString("update0", forKey: "update")
        try col1a.save(document: doc1a)
        
        let doc1b = createDocument("doc2")
        doc1b.setString("update0", forKey: "update")
        try col1b.save(document: doc1b)
        
        let conflictResolver1 = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.localDocument
        })
        let conflictResolver2 = TestConflictResolver({ (con: Conflict) -> Document? in
            return con.remoteDocument
        })
        
        var colConfig1 = CollectionConfiguration(collection: col1a)
        colConfig1.conflictResolver = conflictResolver1
        
        var colConfig2 = CollectionConfiguration(collection: col1b)
        colConfig2.conflictResolver = conflictResolver2
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(configs: [colConfig1, colConfig2], target: target, type: .pushAndPull, continuous: false)
        run(config: config, expectedError: nil)
        
        // Update "doc1" in colA and colB of database A.
        let mdoc1a = try col1a.document(id: "doc1")!.toMutable()
        mdoc1a.setString("update1a", forKey: "update")
        try col1a.save(document: mdoc1a)
        
        let mdoc2a = try col2a.document(id: "doc1")!.toMutable()
        mdoc2a.setString("update2a", forKey: "update")
        try col2a.save(document: mdoc2a)
        
        // Update "doc1" in colA and colB of database B.
        let mdoc1b = try col1b.document(id: "doc2")!.toMutable()
        mdoc1b.setString("update1b", forKey: "update")
        try col1b.save(document: mdoc1b)
        
        let mdoc2b = try col2b.document(id: "doc2")!.toMutable()
        mdoc2b.setString("update2b", forKey: "update")
        try col2b.save(document: mdoc2b)
        
        let r = Replicator(config: config)
        r.addDocumentReplicationListener { docReplication in
            if !docReplication.isPush {
                // Pull will resolve the conflicts:
                let doc = docReplication.documents[0]
                XCTAssertEqual(doc.id, doc.collection == "colA" ? "doc1" : "doc2")
                XCTAssertNil(doc.error)
                
            } else {
                // Push will have conflict errors:
                for doc in docReplication.documents {
                    XCTAssertEqual(doc.id, doc.collection == "colA" ? "doc1" : "doc2")
                    XCTAssertEqual((doc.error as? NSError)?.code, CBLError.httpConflict)
                }
            }
        }
        run(replicator: r, expectedError: nil)
        
        // verify the results
        var docA = try col1a.document(id: "doc1")
        XCTAssertEqual(docA!.string(forKey: "update"), "update1a")
        docA = try col2a.document(id: "doc1")
        XCTAssertEqual(docA!.string(forKey: "update"), "update2a")
        
        var docB = try col1b.document(id: "doc2")
        XCTAssertEqual(docB!.string(forKey: "update"), "update2b")
        docB = try col2b.document(id: "doc2")
        XCTAssertEqual(docB!.string(forKey: "update"), "update2b")
    }
    
    func testCollectionPushFilter() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        // Create some documents in colA and colB of the database A.
        try createDocNumbered(col1a, start: 0, num: 10)
        try createDocNumbered(col1b, start: 10, num: 10)
        
        let filter: ReplicationFilter = { (doc: Document, flags: DocumentFlags) in
            if doc.collection!.name == "colA" {
                return doc.int(forKey: "number1") < 5
            } else {
                return doc.int(forKey: "number1") >= 15
            }
        }
        
        var config1 = CollectionConfiguration(collection: col1a)
        config1.pushFilter = filter
        
        var config2 = CollectionConfiguration(collection: col1b)
        config2.pushFilter = filter
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(configs: [config1, config2], target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col1a.count, 10)
        XCTAssertEqual(col1b.count, 10)
        XCTAssertEqual(col2a.count, 5)
        XCTAssertEqual(col2b.count, 5)
    }
    
    func testCollectionPullFilter() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        // Create some documents in colA and colB of the database A.
        try createDocNumbered(col2a, start: 0, num: 10)
        try createDocNumbered(col2b, start: 10, num: 10)
        
        let filter: ReplicationFilter = { (doc: Document, flags: DocumentFlags) in
            if doc.collection!.name == "colA" {
                return doc.int(forKey: "number1") < 5
            } else {
                return doc.int(forKey: "number1") >= 15
            }
        }
        
        var config1 = CollectionConfiguration(collection: col1a)
        config1.pullFilter = filter
        
        var config2 = CollectionConfiguration(collection: col1b)
        config2.pullFilter = filter
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(configs: [config1, config2], target: target, type: .pull, continuous: false)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col1a.count, 5)
        XCTAssertEqual(col1b.count, 5)
        XCTAssertEqual(col2a.count, 10)
        XCTAssertEqual(col2b.count, 10)
    }
    
    func testCollectionDocumentIDsPushFilter() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 5)
        try createDocNumbered(col1b, start: 10, num: 5)
        
        let target = DatabaseEndpoint(database: otherDB!)

        var config1 = CollectionConfiguration(collection: col1a)
        config1.documentIDs = ["doc1", "doc2"]
        
        var config2 = CollectionConfiguration(collection: col1b)
        config2.documentIDs = ["doc10", "doc11", "doc13"]
        
        let config = self.config(configs: [config1, config2], target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col1a.count, 5)
        XCTAssertEqual(col1b.count, 5)
        XCTAssertEqual(col2a.count, 2)
        XCTAssertEqual(col2b.count, 3)
    }
    
    func testCollectionDocumentIDsPullFilter() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col2a, start: 0, num: 5)
        try createDocNumbered(col2b, start: 10, num: 5)
        
        let target = DatabaseEndpoint(database: otherDB!)
        
        var config1 = CollectionConfiguration(collection: col1a)
        config1.documentIDs = ["doc1", "doc2"]
        
        var config2 = CollectionConfiguration(collection: col1b)
        config2.documentIDs = ["doc10", "doc11", "doc13"]
        
        let config = self.config(configs: [config1, config2], target: target, type: .pull, continuous: false)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(col1a.count, 2)
        XCTAssertEqual(col1b.count, 3)
        XCTAssertEqual(col2a.count, 5)
        XCTAssertEqual(col2b.count, 5)
    }
    
    func testCollectionGetPendingDocumentIDs() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        _ = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        _ = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 10)
        try createDocNumbered(col1b, start: 10, num: 5)
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [col1a, col1b], target: target, type: .push, continuous: false)
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
        
        let _ = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let _ = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 10)
        try createDocNumbered(col1b, start: 10, num: 5)
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [col1a, col1b], target: target, type: .push, continuous: false)
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
    
    func testCollectionDocumentReplicationEvents() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 4)
        try createDocNumbered(col1b, start: 5, num: 5)
        
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [col1a, col1b], target: target, type: .pushAndPull, continuous: false)
        let r = Replicator(config: config)
        var docCount = 0;
        var docs = [String]()
        let token = r.addDocumentReplicationListener { docReplication in
            docCount = docCount + docReplication.documents.count
            for doc in docReplication.documents {
                docs.append(doc.id)
            }
        }
        run(replicator: r, expectedError: nil)
        XCTAssertEqual(col1a.count, 4)
        XCTAssertEqual(col2a.count, 4)
        XCTAssertEqual(col1b.count, 5)
        XCTAssertEqual(col2b.count, 5)
        XCTAssertEqual(docCount, 9)
        XCTAssertEqual(docs.sorted(), ["doc0", "doc1", "doc2", "doc3", "doc5", "doc6", "doc7", "doc8", "doc9"])
        
        // colA & colB - db1
        guard
            let doc1 = try col1a.document(id: "doc0"),
            let doc2 = try col1b.document(id: "doc6")
        else {
            XCTFail("Doc either doesn't exist or can't delete")
            return
        }
        try col1a.delete(document: doc1)
        try col1b.delete(document: doc2)
        
        // colA & colB - db2
        guard
            let doc3 = try col2a.document(id: "doc1"),
            let doc4 = try col2b.document(id: "doc7")
            
        else {
            XCTFail("Doc either doesn't exist or can't delete")
            return
        }
        try col2a.delete(document: doc3)
        try col2b.delete(document: doc4)
        
        docCount = 0;
        docs.removeAll()
        run(replicator: r, expectedError: nil)
        XCTAssertEqual(col1a.count, 2)
        XCTAssertEqual(col2a.count, 2)
        XCTAssertEqual(col1b.count, 3)
        XCTAssertEqual(col2b.count, 3)
        XCTAssertEqual(docCount, 4)
        XCTAssertEqual(docs.sorted(), ["doc0", "doc1", "doc6", "doc7"])
        
        token.remove()
    }
    
#endif
    
}
