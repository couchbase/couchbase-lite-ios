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
    var timeout: TimeInterval!
    
    // connect to an unknown-db on same machine, for the connection refused transient error.
    let kConnRefusedTarget: URLEndpoint = URLEndpoint(url: URL(string: "ws://localhost:4984/unknown-db-wXBl5n3fed")!)
    
    override func setUp() {
        super.setUp()
        try! openOtherDB()
        oDB = otherDB!
        timeout = 10 // At least 10 to cover single-shot replicator's retry logic
    }
    
    override func tearDown() {
        try! oDB.close()
        oDB = nil
        repl = nil
        super.tearDown()
    }
    
    func config(target: Endpoint, type: ReplicatorType = .pushAndPull, continuous: Bool = false,
                auth: Authenticator? = nil, serverCert: SecCertificate? = nil,
                maxAttempts: UInt? = 0) -> ReplicatorConfiguration {
        var config = ReplicatorConfiguration(database: self.db, target: target)
        config.replicatorType = type
        config.continuous = continuous
        config.authenticator = auth
        config.pinnedServerCertificate = serverCert
        if let maxAttempts = maxAttempts {
            config.maxAttempts = maxAttempts
        }
        return config
    }

    #if COUCHBASE_ENTERPRISE
    func config(target: Endpoint, type: ReplicatorType = .pushAndPull,
                continuous: Bool = false, auth: Authenticator? = nil,
                acceptSelfSignedOnly: Bool = false,
                serverCert: SecCertificate? = nil, maxAttempts: UInt? = 0) -> ReplicatorConfiguration {
        var config = self.config(target: target, type: type, continuous: continuous, auth: auth,
                            serverCert: serverCert, maxAttempts: maxAttempts)
        config.acceptOnlySelfSignedServerCertificate = acceptSelfSignedOnly
        return config
    }
    #endif
    
    func run(config: ReplicatorConfiguration, expectedError: Int?) {
        run(config: config, reset: false, expectedError: expectedError)
    }
    
    func run(config: ReplicatorConfiguration, reset: Bool, expectedError: Int?,
             onReplicatorReady: ((Replicator) -> Void)? = nil) {
        repl = Replicator(config: config)
        
        if let ready = onReplicatorReady {
            ready(repl)
        }
        
        run(replicator: repl, reset: reset, expectedError: expectedError)
    }
    
    func run(target: Endpoint, type: ReplicatorType = .pushAndPull,
             continuous: Bool = false, auth: Authenticator? = nil,
             serverCert: SecCertificate? = nil,
             expectedError: Int? = nil) {
        let config = self.config(target: target, type: type, continuous: continuous,
                                 auth: auth, serverCert: serverCert)
        run(config: config, reset: false, expectedError: expectedError)
    }
    
    #if COUCHBASE_ENTERPRISE
    func run(target: Endpoint, type: ReplicatorType = .pushAndPull,
             continuous: Bool = false, auth: Authenticator? = nil,
             acceptSelfSignedOnly: Bool = false,
             serverCert: SecCertificate? = nil,
             maxAttempts: UInt? = 0,
             expectedError: Int? = nil) {
        let config = self.config(target: target, type: type, continuous: continuous, auth: auth,
                                 acceptSelfSignedOnly: acceptSelfSignedOnly, serverCert: serverCert,
                                 maxAttempts: maxAttempts)
        run(config: config, reset: false, expectedError: expectedError)
    }
    #endif
    
    func run(replicator: Replicator, expectedError: Int?) {
        run(replicator: replicator, reset: false, expectedError: expectedError);
    }
    
    func run(replicator: Replicator, reset: Bool, expectedError: Int?) {
        let x = self.expectation(description: "change")
        
        let token = replicator.addChangeListener { (change) in
            let status = change.status
            if replicator.config.continuous && status.activity == .idle &&
                status.progress.completed == status.progress.total {
                replicator.stop()
            }
            
            if status.activity == .stopped {
                let error = status.error as NSError?
                if let err = expectedError {
                    XCTAssertNotNil(error)
                    if let e = error {
                        XCTAssertEqual(e.code, err)
                    }
                } else {
                    XCTAssertNil(error)
                }
                x.fulfill()
            }
        }
        
        if (reset) {
            replicator.start(reset: reset)
        } else {
            replicator.start()
        }
        
        wait(for: [x], timeout: timeout)
        
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
    
    func testStartWithCheckpoint() throws {
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
    
    func testStartWithResetCheckpointContinuous() throws {
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
        self.run(replicator: replicator, expectedError: nil)
        
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
        self.run(replicator: replicator, expectedError: nil)
        
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
        var config = self.config(target: target, type: .push, continuous: isContinuous)
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
        var config = self.config(target: target, type: .pull, continuous: false)
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
        var config = self.config(target: target, type: .pull, continuous: isContinuous)
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
        var config = self.config(target: target, type: .push, continuous: isContinuous)
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
        var config = self.config(target: target, type: .pull, continuous: isContinuous)
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
    
    // https://issues.couchbase.com/browse/CBL-1061
    func _testStopAndRestartPushReplicationWithFilter() throws {
        // Create documents:
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("pass", forKey: "name")
        try db.saveDocument(doc1)
        
        // Create replicator with pull filter:
        let docIds = NSMutableSet()
        let target = DatabaseEndpoint(database: oDB)
        var config = self.config(target: target, type: .push, continuous: true)
        config.pushFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            docIds.add(doc.id)
            return doc.string(forKey: "name") == "pass"
        }
        
        // create a replicator
        repl = Replicator(config: config)
        run(replicator: repl, expectedError: nil)
        
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
        run(replicator: repl, expectedError: nil)
        
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
        var config = self.config(target: target, type: .pull, continuous: true)
        config.pullFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            docIds.add(doc.id)
            return doc.string(forKey: "name") == "pass"
        }
        
        // create a replicator
        repl = Replicator(config: config)
        run(replicator: repl, expectedError: nil)
        
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
        run(replicator: repl, expectedError: nil)
        
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
    
    func testHeartbeatWithInvalidValue() {
        let target = URLEndpoint(url: URL(string: "ws://foo.couchbase.com/db")!)
        func expectExceptionFor(_ val: TimeInterval) throws {
            do {
                try CBLTestHelper.catchException {
                    var config = self.config(target: target, type: .pushAndPull, continuous: true)
                    config.heartbeat = val
                }
            } catch {
                XCTAssertEqual((error as NSError).domain,
                               NSExceptionName.invalidArgumentException.rawValue)
                throw error
            }
        }
        
        XCTAssertThrowsError(try expectExceptionFor(-1))
    }
    
    func testCustomHeartbeat() {
        let target = URLEndpoint(url: URL(string: "ws://foo.couchbase.com/db")!)
        var config = self.config(target: target, type: .pushAndPull, continuous: true)
        config.heartbeat = 60
        repl = Replicator(config: config)
        
        XCTAssertEqual(repl.config.heartbeat, 60)
        XCTAssertEqual(config.heartbeat, 60)
        repl = nil
    }
    
    // MARK: MaxAttempt Logic
    
    func testMaxAttemptCount() {
        // single shot
        var config: ReplicatorConfiguration = self.config(target: kConnRefusedTarget, type: .pushAndPull, continuous: false)
        XCTAssertEqual(config.maxAttempts, 0)
        
        // continous
        config = self.config(target: kConnRefusedTarget, type: .pushAndPull, continuous: true, maxAttempts: nil)
        XCTAssertEqual(config.maxAttempts, 0)
    }
    
    func testCustomMaxAttemptCount() {
        // single shot
        var config: ReplicatorConfiguration = self.config(target: kConnRefusedTarget, type: .pushAndPull, continuous: false)
        config.maxAttempts = 22
        XCTAssertEqual(config.maxAttempts, 22)
        
        // continous
        config = self.config(target: kConnRefusedTarget, type: .pushAndPull, continuous: true)
        config.maxAttempts = 11
        XCTAssertEqual(config.maxAttempts, 11)
    }
    
    func testMaxAttempt(attempt: UInt, count: Int, continuous: Bool) {
        let x = self.expectation(description: "repl finish")
        var config: ReplicatorConfiguration = self.config(target: kConnRefusedTarget,
                                                          type: .pushAndPull,
                                                          continuous: continuous)
        var offlineCount = 0
        config.maxAttempts = attempt
        
        repl = Replicator(config: config)
        repl.addChangeListener { (change) in
            if change.status.activity == .offline {
                offlineCount += 1
            } else if change.status.activity == .stopped {
                x.fulfill()
            }
        }
        
        repl.start()
        wait(for: [x], timeout:  pow(2, Double(count + 1)) + 10.0)
        XCTAssertEqual(count, offlineCount)
    }
    
    func testMaxAttempt() {
        // replicator with no retry; only initial request
        testMaxAttempt(attempt: 1, count: 0, continuous: false)
        testMaxAttempt(attempt: 1, count: 0, continuous: true)
        
        // replicator with one retry; initial + one retry(offline)
        testMaxAttempt(attempt: 2, count: 1, continuous: false)
        testMaxAttempt(attempt: 2, count: 1, continuous: true)
    }
    
    // disbale the test, since this test will take 13mints
    func _testMaxAttemptForSingleShot() {
        testMaxAttempt(attempt: 0, count: 9, continuous: false)
    }
    
    // MARK: Max Retry Wait Time
    
    func testMaxAttemptWaitTime() {
        // single shot
        var config: ReplicatorConfiguration = self.config(target: kConnRefusedTarget, type: .pushAndPull, continuous: false)
        XCTAssertEqual(config.maxAttemptWaitTime, 0)
        
        // continous
        config = self.config(target: kConnRefusedTarget, type: .pushAndPull, continuous: true)
        XCTAssertEqual(config.maxAttemptWaitTime, 0)
        
        repl = Replicator(config: config)
        XCTAssertEqual(repl.config.maxAttemptWaitTime, 0)
    }
    
    func testCustomMaxAttemptWaitTime() {
        // single shot
        var config: ReplicatorConfiguration = self.config(target: self.kConnRefusedTarget, type: .pushAndPull, continuous: false)
        config.maxAttemptWaitTime = 444
        XCTAssertEqual(config.maxAttemptWaitTime, 444)
        
        // continous
        config = self.config(target: kConnRefusedTarget, type: .pushAndPull, continuous: true)
        config.maxAttemptWaitTime = 555
        XCTAssertEqual(config.maxAttemptWaitTime, 555)
    }
    
    func testInvalidMaxAttemptWaitTime() {
        func expectException(_ val: TimeInterval) throws {
            do {
                try CBLTestHelper.catchException {
                    var config: ReplicatorConfiguration = self.config(target: self.kConnRefusedTarget, type: .pushAndPull, continuous: false)
                    config.maxAttemptWaitTime = val
                }
            } catch {
                XCTAssertEqual((error as NSError).domain,
                               NSExceptionName.invalidArgumentException.rawValue)
                throw error
            }
        }
        
        XCTAssertThrowsError(try expectException(-1))
    }
    
    func testMaxAttemptWaitTimeOfReplicator() {
        timeout = 12 // already it takes 8 secs of retry, hence 12secs timeout. 
        let x = self.expectation(description: "repl finish")
        var config: ReplicatorConfiguration = self.config(target: kConnRefusedTarget,
                                                          type: .pushAndPull,
                                                          continuous: false)
        config.maxAttempts = 4
        config.maxAttemptWaitTime = 2
        
        var diff: TimeInterval = 0
        var time = Date()
        repl = Replicator(config: config)
        repl.addChangeListener { (change) in
            if change.status.activity == .offline {
                diff = Date().timeIntervalSince(time)
                time = Date()
            } else if change.status.activity == .stopped {
                x.fulfill()
            }
        }
        
        repl.start()
        wait(for: [x], timeout: timeout)
        XCTAssert(abs(diff - config.maxAttemptWaitTime) < 1.0)
    }
    
    func testListenerAddRemoveAfterReplicatorStart() throws {
        timeout = 15
        let x1 = self.expectation(description: "#1 repl finish")
        let x2 = self.expectation(description: "#2 repl finish")
        
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("pass", forKey: "name")
        try db.saveDocument(doc1)
        
        var config: ReplicatorConfiguration = self.config(target: kConnRefusedTarget,
                                                          type: .pushAndPull,
                                                          continuous: false)
        config.maxAttempts = 4
        config.maxAttemptWaitTime = 2
        
        repl = Replicator(config: config)
        let token1 = repl.addChangeListener { (change) in
            if change.status.activity == .stopped {
                x1.fulfill()
            }
        }
        
        repl.start()
        let token2 = repl.addChangeListener { (change) in
            if change.status.activity == .stopped {
                // validate the remove change listener after the replicator-start
                XCTFail("shouldn't have called")
            }
        }
        
        let token3 = repl.addChangeListener { (change) in
            if change.status.activity == .offline {
                change.replicator.removeChangeListener(withToken: token2)
            } else if change.status.activity == .stopped {
                x2.fulfill()
            }
        }
        
        wait(for: [x1, x2], timeout: timeout)
        repl.removeChangeListener(withToken: token1)
        repl.removeChangeListener(withToken: token3)
    }
    
    // MARK: ReplicatorConfig
    
    func testCopyingReplicatorConfiguration() throws {
        let basic = BasicAuthenticator(username: "abcd", password: "1234")
        let target = URLEndpoint(url: URL(string: "ws://foo.couchbase.com/db")!)
        var config1 = ReplicatorConfiguration(database: oDB, target: target)
        #if COUCHBASE_ENTERPRISE
        config1.acceptOnlySelfSignedServerCertificate = true
        #endif
        config1.continuous = true
        config1.authenticator = basic
        config1.channels = ["c1", "c2"]
        config1.documentIDs = ["d1", "d2"]
        config1.headers = ["a": "aa", "b": "bb"]
        config1.replicatorType = .pull
        config1.heartbeat = 211
        config1.maxAttempts = 223
        config1.maxAttemptWaitTime = 227
        
        let certData = try dataFromResource(name: "SelfSigned", ofType: "cer")
        let cert = SecCertificateCreateWithData(kCFAllocatorDefault, certData as CFData)!
        config1.pinnedServerCertificate = cert
        
        let filter = { (doc: Document, flags: DocumentFlags) -> Bool in
            guard doc.boolean(forKey: "sync") else {
                return false
            }
            
            return !flags.contains(.deleted)
        }
        config1.pullFilter = filter
        config1.pushFilter = filter
        
        // copying
        let config = ReplicatorConfiguration(config: config1)
        
        // update config1 after passing to configuration’s constructor
        #if COUCHBASE_ENTERPRISE
        config1.acceptOnlySelfSignedServerCertificate = false
        #endif
        config1.continuous = false
        config1.authenticator = nil
        config1.channels = nil
        config1.documentIDs = nil
        config1.headers = nil
        config1.replicatorType = .push
        config1.heartbeat = 11
        config1.maxAttempts = 13
        config1.maxAttemptWaitTime = 17
        config1.pinnedServerCertificate = nil
        config1.pullFilter = nil
        config1.pushFilter = nil
        
        #if COUCHBASE_ENTERPRISE
        XCTAssert(config.acceptOnlySelfSignedServerCertificate)
        #endif
        XCTAssert(config.continuous)
        XCTAssertEqual((config.authenticator as! BasicAuthenticator).username, basic.username)
        XCTAssertEqual((config.authenticator as! BasicAuthenticator).password, basic.password)
        XCTAssertEqual(config.channels, ["c1", "c2"])
        XCTAssertEqual(config.documentIDs, ["d1", "d2"])
        XCTAssertEqual(config.headers, ["a": "aa", "b": "bb"])
        XCTAssertEqual(config.replicatorType, .pull)
        XCTAssertEqual(config.heartbeat, 211)
        XCTAssertEqual(config.maxAttempts, 223)
        XCTAssertEqual(config.maxAttemptWaitTime, 227)
        XCTAssertEqual(config.pinnedServerCertificate, cert)
        XCTAssertNotNil(config.pushFilter)
        XCTAssertNotNil(config.pullFilter)
    }
    
    func testReplicationConfigSetterMethods() throws {
        let basic = BasicAuthenticator(username: "abcd", password: "1234")
        let target = URLEndpoint(url: URL(string: "ws://foo.couchbase.com/db")!)
        var config = ReplicatorConfiguration(database: oDB, target: target)
        #if COUCHBASE_ENTERPRISE
        config.acceptOnlySelfSignedServerCertificate = true
        #endif
        config.continuous = true
        config.authenticator = basic
        config.channels = ["c1", "c2"]
        config.documentIDs = ["d1", "d2"]
        config.headers = ["a": "aa", "b": "bb"]
        config.replicatorType = .pull
        config.heartbeat = 211
        config.maxAttempts = 223
        config.maxAttemptWaitTime = 227
        
        let certData = try dataFromResource(name: "SelfSigned", ofType: "cer")
        let cert = SecCertificateCreateWithData(kCFAllocatorDefault, certData as CFData)!
        config.pinnedServerCertificate = cert
        
        let filter = { (doc: Document, flags: DocumentFlags) -> Bool in
            guard doc.boolean(forKey: "sync") else {
                return false
            }
            
            return !flags.contains(.deleted)
        }
        config.pullFilter = filter
        config.pushFilter = filter
        
        // set correctly on replicator
        repl = Replicator(config:  config)
        
        // -------------
        // update config, after passed to the target's constructor
        #if COUCHBASE_ENTERPRISE
        config.acceptOnlySelfSignedServerCertificate = false
        #endif
        config.continuous = false
        config.authenticator = nil
        config.channels = nil
        config.documentIDs = nil
        config.headers = nil
        config.replicatorType = .push
        config.heartbeat = 11
        config.maxAttempts = 13
        config.maxAttemptWaitTime = 17
        config.pinnedServerCertificate = nil
        config.pullFilter = nil
        config.pushFilter = nil
        
        // update returned configuration.
        var config2 = repl.config
        #if COUCHBASE_ENTERPRISE
        config2.acceptOnlySelfSignedServerCertificate = false
        #endif
        config2.continuous = false
        config2.authenticator = nil
        config2.channels = nil
        config2.documentIDs = nil
        config2.headers = nil
        config2.replicatorType = .push
        config2.heartbeat = 11
        config2.maxAttempts = 13
        config2.maxAttemptWaitTime = 17
        config2.pinnedServerCertificate = nil
        config2.pullFilter = nil
        config2.pushFilter = nil
        
        // validate no impact on above updates.
        #if COUCHBASE_ENTERPRISE
        XCTAssert(repl.config.acceptOnlySelfSignedServerCertificate)
        #endif
        XCTAssert(repl.config.continuous)
        XCTAssertEqual((repl.config.authenticator as! BasicAuthenticator).username, basic.username)
        XCTAssertEqual((repl.config.authenticator as! BasicAuthenticator).password, basic.password)
        XCTAssertEqual(repl.config.channels, ["c1", "c2"])
        XCTAssertEqual(repl.config.documentIDs, ["d1", "d2"])
        XCTAssertEqual(repl.config.headers, ["a": "aa", "b": "bb"])
        XCTAssertEqual(repl.config.replicatorType, .pull)
        XCTAssertEqual(repl.config.heartbeat, 211)
        XCTAssertEqual(repl.config.maxAttempts, 223)
        XCTAssertEqual(repl.config.maxAttemptWaitTime, 227)
        XCTAssertEqual(repl.config.pinnedServerCertificate, cert)
        XCTAssertNotNil(repl.config.pushFilter)
        XCTAssertNotNil(repl.config.pullFilter)
    }
    
    func testDefaultReplicatorConfiguration() throws {
        let target = URLEndpoint(url: URL(string: "ws://foo.couchbase.com/db")!)
        let config = ReplicatorConfiguration(database: oDB, target: target)
        
        #if COUCHBASE_ENTERPRISE
        XCTAssertFalse(config.acceptOnlySelfSignedServerCertificate)
        #endif
        XCTAssertNil(config.authenticator)
        XCTAssertNil(config.channels)
        XCTAssertNil(config.conflictResolver)
        XCTAssertFalse(config.continuous)
        XCTAssertNil(config.documentIDs)
        XCTAssertNil(config.headers)
        XCTAssertEqual(config.heartbeat, 0)
        XCTAssertEqual(config.maxAttempts, 0)
        XCTAssertEqual(config.maxAttemptWaitTime, 0)
        XCTAssertNil(config.pinnedServerCertificate)
        XCTAssertNil(config.pullFilter)
        XCTAssertNil(config.pushFilter)
        XCTAssertEqual(config.replicatorType, .pushAndPull)
    }
}
