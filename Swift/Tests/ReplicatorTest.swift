//
//  ReplicatorTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

class ReplicatorTest: CBLTestCase {
    var oDB: Database!
    var repl: Replicator!
    
    override func setUp() {
        super.setUp()
        try! openOtherDB()
        oDB = otherDB!
    }
    
    override func tearDown() {
        try! oDB.close()
        oDB = nil
        repl = nil
        super.tearDown()
    }
    
    func config(target: Endpoint, type: ReplicatorType, continuous: Bool) -> ReplicatorConfiguration {
        let config = ReplicatorConfiguration(database: self.db, target: target)
        config.replicatorType = type
        config.continuous = continuous
        return config
    }
    
    func run(config: ReplicatorConfiguration, expectedError: Int?) {
        run(config: config, reset: false, expectedError: expectedError)
    }
    
    func run(config: ReplicatorConfiguration, reset: Bool, expectedError: Int?,
             onReplicatorReady: ((Replicator) -> Void)? = nil) {
        repl = Replicator(config: config)
        
        if reset {
            repl.resetCheckpoint()
        }
        
        if let ready = onReplicatorReady {
            ready(repl)
        }
        
        run(withReplicator: repl, expectedError: expectedError)
    }
    
    func run(withReplicator replicator: Replicator, expectedError: Int?) {
        let x = self.expectation(description: "change")
        
        let token = replicator.addChangeListener { (change) in
            let status = change.status
            if replicator.config.continuous && status.activity == .idle &&
                status.progress.completed == status.progress.total {
                replicator.stop()
            }
            
            if status.activity == .stopped {
                if let err = expectedError {
                    let error = status.error as NSError?
                    XCTAssertNotNil(error)
                    XCTAssertEqual(error!.code, err)
                }
                x.fulfill()
            }
        }
        
        replicator.start()
        wait(for: [x], timeout: 5.0)
        
        if replicator.status.activity != .stopped {
            replicator.stop()
        }
        replicator.removeChangeListener(withToken: token)
    }
}

class ReplicatorTest_Main: ReplicatorTest {

    #if COUCHBASE_ENTERPRISE
    
    func testEmptyPush() throws {
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
    }
    
    func testResetCheckpoint() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "pattern")
        try db.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("striped", forKey: "pattern")
        try db.saveDocument(doc2)
        
        // Push:
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
        
        // Pull:
        config = self.config(target: target, type: .pull, continuous: false)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(db.count, 2)
        
        var doc = db.document(withID: "doc1")!
        try db.purgeDocument(doc)
        
        doc = db.document(withID: "doc2")!
        try db.purgeDocument(doc)
        
        XCTAssertEqual(db.count, 0)
        
        // Pull again, shouldn't have any new changes:
        run(config: config, expectedError: nil)
        XCTAssertEqual(db.count, 0)
        
        // Reset and pull:
        run(config: config, reset: true, expectedError: nil)
        XCTAssertEqual(db.count, 2)
    }
    
    func testResetCheckpointContinuous() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "pattern")
        try db.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("striped", forKey: "pattern")
        try db.saveDocument(doc2)
        
        // Push:
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .push, continuous: true)
        run(config: config, expectedError: nil)
        
        // Pull:
        config = self.config(target: target, type: .pull, continuous: true)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(db.count, 2)
        
        var doc = db.document(withID: "doc1")!
        try db.purgeDocument(doc)
        
        doc = db.document(withID: "doc2")!
        try db.purgeDocument(doc)
        
        XCTAssertEqual(db.count, 0)
        
        // Pull again, shouldn't have any new changes:
        run(config: config, expectedError: nil)
        XCTAssertEqual(db.count, 0)
        
        // Reset and pull:
        run(config: config, reset: true, expectedError: nil)
        XCTAssertEqual(db.count, 2)
    }
    
    func testDocumentReplicationEvent() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "pattern")
        try db.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("Striped", forKey: "pattern")
        try db.saveDocument(doc2)
        
        // Push:
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .push, continuous: false)
        
        var replicator: Replicator!
        var token: ListenerToken!
        var docs: [ReplicatedDocument] = []
        self.run(config: config, reset: false, expectedError: nil) { (r) in
            replicator = r
            token = r.addDocumentReplicationListener({ (replication) in
                XCTAssert(replication.isPush)
                for doc in replication.documents {
                    docs.append(doc)
                }
            })
        }
        
        // Check if getting two document replication events:
        XCTAssertEqual(docs.count, 2)
        XCTAssertEqual(docs[0].id, "doc1")
        XCTAssertNil(docs[0].error)
        XCTAssertFalse(docs[0].flags.contains(.deleted))
        XCTAssertFalse(docs[0].flags.contains(.accessRemoved))
        
        XCTAssertEqual(docs[1].id, "doc2")
        XCTAssertNil(docs[1].error)
        XCTAssertFalse(docs[1].flags.contains(.deleted))
        XCTAssertFalse(docs[1].flags.contains(.accessRemoved))
        
        // Add another doc:
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("Tiger", forKey: "species")
        doc3.setString("Star", forKey: "pattern")
        try db.saveDocument(doc3)
        
        // Run the replicator again:
        self.run(withReplicator: replicator, expectedError: nil)
        
        // Check if getting a new document replication event:
        XCTAssertEqual(docs.count, 3)
        XCTAssertEqual(docs[2].id, "doc3")
        XCTAssertNil(docs[2].error)
        XCTAssertFalse(docs[2].flags.contains(.deleted))
        XCTAssertFalse(docs[2].flags.contains(.accessRemoved))
        
        // Add another doc:
        let doc4 = MutableDocument(id: "doc4")
        doc4.setString("Tiger", forKey: "species")
        doc4.setString("WhiteStriped", forKey: "pattern")
        try db.saveDocument(doc4)
        
        // Remove document replication listener:
        replicator.removeChangeListener(withToken: token)
        
        // Run the replicator again:
        self.run(withReplicator: replicator, expectedError: nil)
        
        // Should not getting a new document replication event:
        XCTAssertEqual(docs.count, 3)
    }
    
    func testDocumentReplicationEventWithPushConflict() throws {
        let doc1a = MutableDocument(id: "doc1")
        doc1a.setString("Tiger", forKey: "species")
        doc1a.setString("Star", forKey: "pattern")
        try db.saveDocument(doc1a)
        
        let doc1b = MutableDocument(id: "doc1")
        doc1b.setString("Tiger", forKey: "species")
        doc1b.setString("Striped", forKey: "pattern")
        try oDB.saveDocument(doc1b)
        
        // Push:
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .push, continuous: false)
        
        var replicator: Replicator!
        var token: ListenerToken!
        var docs: [ReplicatedDocument] = []
        self.run(config: config, reset: false, expectedError: nil) { (r) in
            replicator = r
            token = r.addDocumentReplicationListener({ (replication) in
                XCTAssert(replication.isPush)
                for doc in replication.documents {
                    docs.append(doc)
                }
            })
        }
        
        // Check:
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs[0].id, "doc1")
        XCTAssertNotNil(docs[0].error)
        let err = docs[0].error! as NSError
        XCTAssertEqual(err.domain, CBLErrorDomain)
        XCTAssertEqual(err.code, CBLErrorHTTPConflict)
        XCTAssertFalse(docs[0].flags.contains(.deleted))
        XCTAssertFalse(docs[0].flags.contains(.accessRemoved))
        
        // Remove document replication listener:
        replicator.removeChangeListener(withToken: token)
    }
    
    func testDocumentReplicationEventWithPullConflict() throws {
        let doc1a = MutableDocument(id: "doc1")
        doc1a.setString("Tiger", forKey: "species")
        doc1a.setString("Star", forKey: "pattern")
        try db.saveDocument(doc1a)
        
        let doc1b = MutableDocument(id: "doc1")
        doc1b.setString("Tiger", forKey: "species")
        doc1b.setString("Striped", forKey: "pattern")
        try oDB.saveDocument(doc1b)
        
        // Pull:
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .pull, continuous: false)
        
        var replicator: Replicator!
        var token: ListenerToken!
        var docs: [ReplicatedDocument] = []
        self.run(config: config, reset: false, expectedError: nil) { (r) in
            replicator = r
            token = r.addDocumentReplicationListener({ (replication) in
                XCTAssertFalse(replication.isPush)
                for doc in replication.documents {
                    docs.append(doc)
                }
            })
        }
        
        // Check:
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs[0].id, "doc1")
        XCTAssertNil(docs[0].error)
        XCTAssertFalse(docs[0].flags.contains(.deleted))
        XCTAssertFalse(docs[0].flags.contains(.accessRemoved))
        
        // Remove document replication listener:
        replicator.removeChangeListener(withToken: token)
    }
    
    func testDocumentReplicationEventWithDeletion() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Star", forKey: "pattern")
        try db.saveDocument(doc1)
        
        // Delete:
        try db.deleteDocument(doc1)
        
        // Push:
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .push, continuous: false)
        
        var replicator: Replicator!
        var token: ListenerToken!
        var docs: [ReplicatedDocument] = []
        self.run(config: config, reset: false, expectedError: nil) { (r) in
            replicator = r
            token = r.addDocumentReplicationListener({ (replication) in
                XCTAssert(replication.isPush)
                for doc in replication.documents {
                    docs.append(doc)
                }
            })
        }
        
        // Check:
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs[0].id, "doc1")
        XCTAssertNil(docs[0].error)
        XCTAssertTrue(docs[0].flags.contains(.deleted))
        XCTAssertFalse(docs[0].flags.contains(.accessRemoved))
        
        // Remove document replication listener:
        replicator.removeChangeListener(withToken: token)
    }
    
    func testSingleShotPushFilter() throws {
        try testPushFilter(false)
    }
    
    func testContinuousPushFilter() throws {
        try testPushFilter(true)
    }
    
    func testPushFilter(_ isContinuous: Bool) throws {
        // Create documents:
        let content = "I'm a tiger.".data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "pattern")
        doc1.setBlob(blob, forKey: "photo")
        try db.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("Striped", forKey: "pattern")
        doc2.setBlob(blob, forKey: "photo")
        try db.saveDocument(doc2)
        
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("Tiger", forKey: "species")
        doc3.setString("Star", forKey: "pattern")
        doc3.setBlob(blob, forKey: "photo")
        try db.saveDocument(doc3)
        try db.deleteDocument(doc3)
        
        // Create replicator with push filter:
        let docIds = NSMutableSet()
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .push, continuous: isContinuous)
        config.pushFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            let isDeleted = flags.contains(.deleted)
            XCTAssert(doc.id == "doc3" ? isDeleted : !isDeleted)
            if !isDeleted {
                // Check content:
                XCTAssertNotNil(doc.value(forKey: "pattern"))
                XCTAssertEqual(doc.string(forKey: "species")!, "Tiger")
                
                // Check blob:
                let photo = doc.blob(forKey: "photo")
                XCTAssertNotNil(photo)
                XCTAssertEqual(photo!.content, blob.content)
            } else {
                XCTAssert(doc.toDictionary() == [:])
            }
            
            // Gather document ID:
            docIds.add(doc.id)
            
            // Reject doc2:
            return doc.id == "doc2" ? false : true
        }
        
        // Run the replicator:
        run(config: config, expectedError: nil)
        
        // Check documents passed to the filter:
        XCTAssertEqual(docIds.count, 3)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("doc2"))
        XCTAssert(docIds.contains("doc3"))
        
        // Check replicated documents:
        XCTAssertNotNil(oDB.document(withID: "doc1"))
        XCTAssertNil(oDB.document(withID: "doc2"))
        XCTAssertNil(oDB.document(withID: "doc3"))
    }
    
    func testPullFilter() throws {
        // Add a document to db database so that it can pull the deleted docs from:
        let doc0 = MutableDocument(id: "doc0")
        doc0.setString("Cat", forKey: "species")
        try db.saveDocument(doc0)
        
        // Create documents:
        let content = "I'm a tiger.".data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "pattern")
        doc1.setBlob(blob, forKey: "photo")
        try self.oDB.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("Striped", forKey: "pattern")
        doc2.setBlob(blob, forKey: "photo")
        try self.oDB.saveDocument(doc2)
        
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("Tiger", forKey: "species")
        doc3.setString("Star", forKey: "pattern")
        doc3.setBlob(blob, forKey: "photo")
        try self.oDB.saveDocument(doc3)
        try self.oDB.deleteDocument(doc3)
        
        // Create replicator with pull filter:
        let docIds = NSMutableSet()
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .pull, continuous: false)
        config.pullFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            let isDeleted = flags.contains(.deleted)
            XCTAssert(doc.id == "doc3" ? isDeleted : !isDeleted)
            if !isDeleted {
                // Check content:
                XCTAssertNotNil(doc.value(forKey: "pattern"))
                XCTAssertEqual(doc.string(forKey: "species")!, "Tiger")
                
                // Check blob:
                let photo = doc.blob(forKey: "photo")
                XCTAssertNotNil(photo)
                
                // Note: Cannot access content because there is no actual blob file saved on disk.
                // XCTAssertEqual(photo!.content, blob.content)
            } else {
                XCTAssert(doc.toDictionary() == [:])
            }
            
            // Gather document ID:
            docIds.add(doc.id)
            
            // Reject doc2:
            return doc.id == "doc2" ? false : true
        }
        
        // Run the replicator:
        run(config: config, expectedError: nil)
        
        // Check documents passed to the filter:
        XCTAssertEqual(docIds.count, 3)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("doc2"))
        XCTAssert(docIds.contains("doc3"))
        
        // Check replicated documents:
        XCTAssertNotNil(db.document(withID: "doc1"))
        XCTAssertNil(db.document(withID: "doc2"))
        XCTAssertNil(db.document(withID: "doc3"))
    }
    
    func testPushAndForget() throws {
        let doc = MutableDocument(id: "doc1")
        doc.setString("Tiger", forKey: "species")
        doc.setString("Hobbes", forKey: "pattern")
        try db.saveDocument(doc)
        
        let promise = expectation(description: "document expiry expectation")
        let docChangeToken =
            db.addDocumentChangeListener(withID: doc.id) { [unowned self] (change) in
                XCTAssertEqual(doc.id, change.documentID)
                if self.db.document(withID: doc.id) == nil {
                    promise.fulfill()
                }
        }
        XCTAssertEqual(self.db.count, 1)
        XCTAssertEqual(oDB.count, 0)
        
        // Push:
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .push, continuous: false)
        var replicator: Replicator!
        var docReplicationToken: ListenerToken!
        self.run(config: config, reset: false, expectedError: nil) { [unowned self] (r) in
            replicator = r
            docReplicationToken = r.addDocumentReplicationListener({ [unowned self] (replication) in
                try! self.db.setDocumentExpiration(withID: doc.id, expiration: Date())
            })
        }
        
        waitForExpectations(timeout: 5.0)
        
        replicator.removeChangeListener(withToken: docReplicationToken)
        db.removeChangeListener(withToken: docChangeToken);
        
        XCTAssertEqual(self.db.count, 0)
        XCTAssertEqual(oDB.count, 1)
    }
    
    // MARK: Removed Doc with Filter
    
    func testPullRemovedDocWithFilterSingleShot() throws {
        try testPullRemovedDocWithFilter(false)
    }
    
    func testPullRemovedDocWithFilterContinuous() throws {
        try testPullRemovedDocWithFilter(true)
    }
    
    func testPullRemovedDocWithFilter(_ isContinuous: Bool) throws {
        // Create documents:
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("pass", forKey: "name")
        try oDB.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "pass")
        doc2.setString("pass", forKey: "name")
        try oDB.saveDocument(doc2)
        
        // Create replicator with push filter:
        let docIds = NSMutableSet()
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .pull, continuous: isContinuous)
        config.pullFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            
            let isAccessRemoved = flags.contains(.accessRemoved)
            if isAccessRemoved {
                docIds.add(doc.id)
                return doc.id == "pass"
            }
            return doc.string(forKey: "name") == "pass"
        }
        
        // Run the replicator:
        run(config: config, expectedError: nil)
        XCTAssertEqual(docIds.count, 0)
        
        XCTAssertNotNil(db.document(withID: "doc1"))
        XCTAssertNotNil(db.document(withID: "pass"))
        
        guard let doc1Mutable = oDB.document(withID: "doc1")?.toMutable() else {
            fatalError("Docs must exists")
        }
        doc1Mutable.setData(["_removed": true])
        try oDB.saveDocument(doc1Mutable)
        
        guard let doc2Mutable = oDB.document(withID: "pass")?.toMutable() else {
            fatalError("Docs must exists")
        }
        doc2Mutable.setData(["_removed": true])
        try oDB.saveDocument(doc2Mutable)
        
        run(config: config, expectedError: nil)
        
        // Check documents passed to the filter:
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("pass"))
        
        XCTAssertNotNil(db.document(withID: "doc1"))
        XCTAssertNil(db.document(withID: "pass"))
    }
    
    // MARK: Deleted Doc with Filter
    
    func testPushDeletedDocWithFilterSingleShot() throws {
        try testPushDeletedDocWithFilter(false)
    }
    
    func testPushDeletedDocWithFilterContinuous() throws {
        try testPushDeletedDocWithFilter(true)
    }
    
    func testPullDeletedDocWithFilterSingleShot() throws {
        try testPullDeletedDocWithFilter(false)
    }
    
    func testPullDeletedDocWithFilterContinuous() throws {
        try testPullDeletedDocWithFilter(true)
    }
    
    func testPushDeletedDocWithFilter(_ isContinuous: Bool) throws {
        // Create documents:
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("pass", forKey: "name")
        try db.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "pass")
        doc2.setString("pass", forKey: "name")
        try db.saveDocument(doc2)
        
        // Create replicator with push filter:
        let docIds = NSMutableSet()
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .push, continuous: isContinuous)
        config.pushFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            
            let isDeleted = flags.contains(.deleted)
            if isDeleted {
                docIds.add(doc.id)
                return doc.id == "pass"
            }
            return doc.string(forKey: "name") == "pass"
        }
        
        // Run the replicator:
        run(config: config, expectedError: nil)
        XCTAssertEqual(docIds.count, 0)
        
        XCTAssertNotNil(oDB.document(withID: "doc1"))
        XCTAssertNotNil(oDB.document(withID: "pass"))
        
        try db.deleteDocument(doc1)
        try db.deleteDocument(doc2)
        
        run(config: config, expectedError: nil)
        
        // Check documents passed to the filter:
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("pass"))
        
        XCTAssertNotNil(oDB.document(withID: "doc1"))
        XCTAssertNil(oDB.document(withID: "pass"))
    }
    
    func testPullDeletedDocWithFilter(_ isContinuous: Bool) throws {
        // Create documents:
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("pass", forKey: "name")
        try oDB.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "pass")
        doc2.setString("pass", forKey: "name")
        try oDB.saveDocument(doc2)
        
        // Create replicator with push filter:
        let docIds = NSMutableSet()
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .pull, continuous: isContinuous)
        config.pullFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            
            let isDeleted = flags.contains(.deleted)
            if isDeleted {
                docIds.add(doc.id)
                return doc.id == "pass"
            }
            return doc.string(forKey: "name") == "pass"
        }
        
        // Run the replicator:
        run(config: config, expectedError: nil)
        XCTAssertEqual(docIds.count, 0)
        
        XCTAssertNotNil(db.document(withID: "doc1"))
        XCTAssertNotNil(db.document(withID: "pass"))
        
        try oDB.deleteDocument(doc1)
        try oDB.deleteDocument(doc2)
        
        run(config: config, expectedError: nil)
        
        // Check documents passed to the filter:
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("pass"))
        
        XCTAssertNotNil(db.document(withID: "doc1"))
        XCTAssertNil(db.document(withID: "pass"))
    }
    
    // MARK: stop and restart replication with filter
    
    func testStopAndRestartPushReplicationWithFilter() throws {
        // Create documents:
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("pass", forKey: "name")
        try db.saveDocument(doc1)
        
        // Create replicator with pull filter:
        let docIds = NSMutableSet()
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .push, continuous: true)
        config.pushFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            docIds.add(doc.id)
            return doc.string(forKey: "name") == "pass"
        }
        
        // create a replicator
        repl = Replicator(config: config)
        run(withReplicator: repl, expectedError: nil)
        
        XCTAssertEqual(docIds.count, 1)
        XCTAssertEqual(oDB.count, 1)
        XCTAssertEqual(db.count, 1)
        
        // make some more changes
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("pass", forKey: "name")
        try db.saveDocument(doc2)
        
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("donotpass", forKey: "name")
        try db.saveDocument(doc3)
        
        // restart the same replicator
        docIds.removeAllObjects()
        run(withReplicator: repl, expectedError: nil)
        
        // should use the same replicator filter.
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc3"))
        XCTAssert(docIds.contains("doc2"))
        
        XCTAssertNotNil(oDB.document(withID: "doc1"))
        XCTAssertNotNil(oDB.document(withID: "doc2"))
        XCTAssertNil(oDB.document(withID: "doc3"))
        XCTAssertEqual(db.count, 3)
        XCTAssertEqual(oDB.count, 2)
    }
    
    func testStopAndRestartPullReplicationWithFilter() throws {
        // Create documents:
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("pass", forKey: "name")
        try oDB.saveDocument(doc1)
        
        // Create replicator with pull filter:
        let docIds = NSMutableSet()
        let target = DatabaseEndpoint(database: oDB)
        let config = self.config(target: target, type: .pull, continuous: true)
        config.pullFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            docIds.add(doc.id)
            return doc.string(forKey: "name") == "pass"
        }
        
        // create a replicator
        repl = Replicator(config: config)
        run(withReplicator: repl, expectedError: nil)
        
        XCTAssertEqual(docIds.count, 1)
        XCTAssertEqual(oDB.count, 1)
        XCTAssertEqual(db.count, 1)
        
        // make some more changes
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("pass", forKey: "name")
        try oDB.saveDocument(doc2)
        
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("donotpass", forKey: "name")
        try oDB.saveDocument(doc3)
        
        // restart the same replicator
        docIds.removeAllObjects()
        run(withReplicator: repl, expectedError: nil)
        
        // should use the same replicator filter.
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc3"))
        XCTAssert(docIds.contains("doc2"))
        
        XCTAssertNotNil(db.document(withID: "doc1"))
        XCTAssertNotNil(db.document(withID: "doc2"))
        XCTAssertNil(db.document(withID: "doc3"))
        XCTAssertEqual(oDB.count, 3)
        XCTAssertEqual(db.count, 2)
    }
    
    #endif
    
}
