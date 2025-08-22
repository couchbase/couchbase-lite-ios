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
    var repl: Replicator!
    
    // connect to an unknown-db on same machine, for the connection refused transient error.
    let kConnRefusedTarget: URLEndpoint = URLEndpoint(url: URL(string: "ws://localhost:4083/unknown-db-wXBl5n3fed")!)
    
    override func setUp() {
        super.setUp()
        try! openOtherDB()
    }
    
    override func tearDown() {
        repl = nil
        super.tearDown()
    }
    
    func config(collections: [Collection],
                target: Endpoint,
                type: ReplicatorType = .pushAndPull,
                continuous: Bool = false,
                auth: Authenticator? = nil,
                acceptSelfSignedOnly: Bool = false,
                serverCert: SecCertificate? = nil,
                maxAttempts: UInt = 0) -> ReplicatorConfiguration {
        let configs = CollectionConfiguration.fromCollections(collections)
        return config(configs: configs,
                      target: target,
                      type: type,
                      continuous: continuous,
                      auth: auth,
                      acceptSelfSignedOnly: acceptSelfSignedOnly,
                      serverCert: serverCert,
                      maxAttempts: maxAttempts)
    }
    
    func config(configs: [CollectionConfiguration]? = nil,
                target: Endpoint,
                type: ReplicatorType = .pushAndPull,
                continuous: Bool = false,
                auth: Authenticator? = nil,
                acceptSelfSignedOnly: Bool = false,
                serverCert: SecCertificate? = nil,
                maxAttempts: UInt = 0) -> ReplicatorConfiguration {
        var config: ReplicatorConfiguration
        if let configs = configs {
            config = ReplicatorConfiguration(collections: configs, target: target)
        } else {
            config = ReplicatorConfiguration(target: target)
        }
        
        config.replicatorType = type
        config.continuous = continuous
        config.authenticator = auth
        config.pinnedServerCertificate = serverCert
        config.maxAttempts = maxAttempts
        
    #if COUCHBASE_ENTERPRISE
        config.acceptOnlySelfSignedServerCertificate = acceptSelfSignedOnly
    #endif
        return config
    }
    
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
    
    func run(target: Endpoint,
             type: ReplicatorType = .pushAndPull,
             continuous: Bool = false,
             auth: Authenticator? = nil,
             acceptSelfSignedOnly: Bool = false,
             serverCert: SecCertificate? = nil,
             maxAttempts: UInt = 0,
             expectedError: Int? = nil) {
        let config = self.config(collections: [defaultCollection!],
                                 target: target,
                                 type: type,
                                 continuous: continuous,
                                 auth: auth,
                                 acceptSelfSignedOnly: acceptSelfSignedOnly,
                                 serverCert: serverCert,
                                 maxAttempts: maxAttempts)
        run(config: config, reset: false, expectedError: expectedError)
    }
    
    func run(replicator: Replicator, expectedError: Int? = nil) {
        run(replicator: replicator, reset: false, expectedError: expectedError);
    }
    
    func run(replicator: Replicator, reset: Bool, expectedError: Int? = nil) {
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
        
        wait(for: [x], timeout: expTimeout)
        
        if replicator.status.activity != .stopped {
            replicator.stop()
        }
        replicator.removeChangeListener(withToken: token)
    }
}

class ReplicatorTest_Main: ReplicatorTest {

    #if COUCHBASE_ENTERPRISE
    
    func testEmptyPush() throws {
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [defaultCollection!], target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
    }
    
    func testStartWithCheckpoint() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "pattern")
        try defaultCollection!.save(document: doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("striped", forKey: "pattern")
        try defaultCollection!.save(document: doc2)
        
        // Push:
        let target = DatabaseEndpoint(database: otherDB!)
        var config = self.config(collections: [defaultCollection!], target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
        
        // Pull:
        config = self.config(collections: [defaultCollection!], target: target, type: .pull, continuous: false)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(defaultCollection!.count, 2)
        
        var doc = try defaultCollection!.document(id: "doc1")!
        try defaultCollection!.purge(document: doc)
        
        doc = try defaultCollection!.document(id: "doc2")!
        try defaultCollection!.purge(document: doc)
        
        XCTAssertEqual(defaultCollection!.count, 0)
        
        // Pull again, shouldn't have any new changes:
        run(config: config, expectedError: nil)
        XCTAssertEqual(defaultCollection!.count, 0)
        
        // Reset and pull:
        run(config: config, reset: true, expectedError: nil)
        XCTAssertEqual(defaultCollection!.count, 2)
    }
    
    func testStartWithResetCheckpointContinuous() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "pattern")
        try defaultCollection!.save(document: doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("striped", forKey: "pattern")
        try defaultCollection!.save(document: doc2)
        
        // Push:
        let target = DatabaseEndpoint(database: otherDB!)
        var config = self.config(collections: [defaultCollection!], target: target, type: .push, continuous: true)
        run(config: config, expectedError: nil)
        
        // Pull:
        config = self.config(collections: [defaultCollection!], target: target, type: .pull, continuous: true)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(defaultCollection!.count, 2)
        
        var doc = try defaultCollection!.document(id: "doc1")!
        try defaultCollection!.purge(document: doc)
        
        doc = try defaultCollection!.document(id: "doc2")!
        try defaultCollection!.purge(document: doc)
        
        XCTAssertEqual(defaultCollection!.count, 0)
        
        // Pull again, shouldn't have any new changes:
        run(config: config, expectedError: nil)
        XCTAssertEqual(defaultCollection!.count, 0)
        
        // Reset and pull:
        run(config: config, reset: true, expectedError: nil)
        XCTAssertEqual(defaultCollection!.count, 2)
    }
    
    func testDocumentReplicationEvent() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "pattern")
        try defaultCollection!.save(document: doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("Striped", forKey: "pattern")
        try defaultCollection!.save(document: doc2)
        
        // Push:
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [defaultCollection!], target: target, type: .push, continuous: false)
        
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
        try defaultCollection!.save(document: doc3)
        
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
        try defaultCollection!.save(document: doc4)
        
        // Remove document replication listener:
        replicator.removeChangeListener(withToken: token)
        
        // Run the replicator again:
        self.run(replicator: replicator, expectedError: nil)
        
        // Should not getting a new document replication event:
        XCTAssertEqual(docs.count, 3)
    }
    
    func testRemoveDocumentReplicationListener() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "pattern")
        try defaultCollection!.save(document: doc1)
        
        // Push:
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [defaultCollection!], target: target, type: .push)
        
        let x = self.expectation(description: "Document Replication - Inverted")
        x.isInverted = true
        
        self.run(config: config, reset: false, expectedError: nil) { (r) in
            let token = r.addDocumentReplicationListener { doc in
                x.fulfill()
            }
            token.remove()
        }
        wait(for: [x], timeout: 5)
    }
    
    func testDocumentReplicationEventWithPushConflict() throws {
        let doc1a = MutableDocument(id: "doc1")
        doc1a.setString("Tiger", forKey: "species")
        doc1a.setString("Star", forKey: "pattern")
        try defaultCollection!.save(document: doc1a)
        
        let doc1b = MutableDocument(id: "doc1")
        doc1b.setString("Tiger", forKey: "species")
        doc1b.setString("Striped", forKey: "pattern")
        try otherDB_defaultCollection!.save(document: doc1b)
        
        // Push:
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [defaultCollection!], target: target, type: .push, continuous: false)
        
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
        XCTAssertEqual(err.domain, CBLError.domain)
        XCTAssertEqual(err.code, CBLError.httpConflict)
        XCTAssertFalse(docs[0].flags.contains(.deleted))
        XCTAssertFalse(docs[0].flags.contains(.accessRemoved))
        
        // Remove document replication listener:
        replicator.removeChangeListener(withToken: token)
    }
    
    func testDocumentReplicationEventWithPullConflict() throws {
        let doc1a = MutableDocument(id: "doc1")
        doc1a.setString("Tiger", forKey: "species")
        doc1a.setString("Star", forKey: "pattern")
        try defaultCollection!.save(document: doc1a)
        
        let doc1b = MutableDocument(id: "doc1")
        doc1b.setString("Tiger", forKey: "species")
        doc1b.setString("Striped", forKey: "pattern")
        try otherDB_defaultCollection!.save(document: doc1b)
        
        // Pull:
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [defaultCollection!], target: target, type: .pull, continuous: false)

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
        try defaultCollection!.save(document: doc1)
        
        // Delete:
        try defaultCollection!.delete(document: doc1)
        
        // Push:
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [defaultCollection!], target: target, type: .push, continuous: false)
        
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
        try defaultCollection!.save(document: doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("Striped", forKey: "pattern")
        doc2.setBlob(blob, forKey: "photo")
        try defaultCollection!.save(document: doc2)
        
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("Tiger", forKey: "species")
        doc3.setString("Star", forKey: "pattern")
        doc3.setBlob(blob, forKey: "photo")
        try defaultCollection!.save(document: doc3)
        try defaultCollection!.delete(document: doc3)
        
        // Create replicator with push filter:
        let docIds = NSMutableSet()
        let target = DatabaseEndpoint(database: otherDB!)
        var colConfig = CollectionConfiguration(collection: defaultCollection!)
        colConfig.pushFilter = { (doc, flags) in
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
        
        let config = self.config(configs: [colConfig], target: target, type: .push, continuous: isContinuous)

        // Run the replicator:
        run(config: config, expectedError: nil)
        
        // Check documents passed to the filter:
        XCTAssertEqual(docIds.count, 3)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("doc2"))
        XCTAssert(docIds.contains("doc3"))
        
        // Check replicated documents:
        XCTAssertNotNil(try otherDB_defaultCollection!.document(id: "doc1"))
        XCTAssertNil(try otherDB_defaultCollection!.document(id: "doc2"))
        XCTAssertNil(try otherDB_defaultCollection!.document(id: "doc3"))
    }
    
    func testPullFilter() throws {
        // Add a document to db database so that it can pull the deleted docs from:
        let doc0 = MutableDocument(id: "doc0")
        doc0.setString("Cat", forKey: "species")
        try defaultCollection!.save(document: doc0)
        
        // Create documents:
        let content = "I'm a tiger.".data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "pattern")
        doc1.setBlob(blob, forKey: "photo")
        try self.otherDB_defaultCollection!.save(document: doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("Striped", forKey: "pattern")
        doc2.setBlob(blob, forKey: "photo")
        try self.otherDB_defaultCollection!.save(document: doc2)
        
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("Tiger", forKey: "species")
        doc3.setString("Star", forKey: "pattern")
        doc3.setBlob(blob, forKey: "photo")
        try self.otherDB_defaultCollection!.save(document: doc3)
        try self.otherDB_defaultCollection!.delete(document: doc3)
        
        // Create replicator with pull filter:
        let target = DatabaseEndpoint(database: otherDB!)
        
        let docIds = NSMutableSet()
        var colConfig = CollectionConfiguration(collection: defaultCollection!)
        colConfig.pullFilter = { (doc, flags) in
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
        
        let config = self.config(configs: [colConfig], target: target, type: .pull, continuous: false)
        
        // Run the replicator:
        run(config: config, expectedError: nil)
        
        // Check documents passed to the filter:
        XCTAssertEqual(docIds.count, 3)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("doc2"))
        XCTAssert(docIds.contains("doc3"))
        
        // Check replicated documents:
        XCTAssertNotNil(try defaultCollection!.document(id: "doc1"))
        XCTAssertNil(try defaultCollection!.document(id: "doc2"))
        XCTAssertNil(try defaultCollection!.document(id: "doc3"))
    }
    
    func testPushAndForget() throws {
        let doc = MutableDocument(id: "doc1")
        doc.setString("Tiger", forKey: "species")
        doc.setString("Hobbes", forKey: "pattern")
        try defaultCollection!.save(document: doc)
        
        let promise = expectation(description: "document expiry expectation")
        let docChangeToken =
            defaultCollection!.addDocumentChangeListener(id: doc.id) { [unowned self] (change) in
                XCTAssertEqual(doc.id, change.documentID)
                if try! self.defaultCollection!.document(id: doc.id) == nil {
                    promise.fulfill()
                }
        }
        XCTAssertEqual(self.defaultCollection!.count, 1)
        XCTAssertEqual(self.otherDB_defaultCollection!.count, 0)
        
        // Push:
        let target = DatabaseEndpoint(database: otherDB!)
        let config = self.config(collections: [defaultCollection!], target: target, type: .push, continuous: false)
        var replicator: Replicator!
        var docReplicationToken: ListenerToken!
        self.run(config: config, reset: false, expectedError: nil) { [unowned self] (r) in
            replicator = r
            docReplicationToken = r.addDocumentReplicationListener({ [unowned self] (replication) in
                try! self.defaultCollection!.setDocumentExpiration(id: doc.id, expiration: Date())
            })
        }
        
        waitForExpectations(timeout: 5.0)
        
        replicator.removeChangeListener(withToken: docReplicationToken)
        docChangeToken.remove()
        
        XCTAssertEqual(self.defaultCollection!.count, 0)
        XCTAssertEqual(otherDB_defaultCollection!.count, 1)
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
        try otherDB_defaultCollection!.save(document: doc1)
        
        let doc2 = MutableDocument(id: "pass")
        doc2.setString("pass", forKey: "name")
        try otherDB_defaultCollection!.save(document: doc2)
        
        // Create replicator with push filter:
        let target = DatabaseEndpoint(database: otherDB!)
        
        let docIds = NSMutableSet()
        var colConfig = CollectionConfiguration(collection: defaultCollection!)
        colConfig.pullFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            
            let isAccessRemoved = flags.contains(.accessRemoved)
            if isAccessRemoved {
                docIds.add(doc.id)
                return doc.id == "pass"
            }
            return doc.string(forKey: "name") == "pass"
        }
        
        let config = self.config(configs: [colConfig], target: target, type: .pull, continuous: isContinuous)
        
        // Run the replicator:
        run(config: config, expectedError: nil)
        XCTAssertEqual(docIds.count, 0)
        
        XCTAssertNotNil(try defaultCollection!.document(id: "doc1"))
        XCTAssertNotNil(try defaultCollection!.document(id: "pass"))
        
        guard let doc1Mutable = try otherDB_defaultCollection!.document(id: "doc1")?.toMutable() else {
            fatalError("Docs must exists")
        }
        doc1Mutable.setData(["_removed": true])
        try otherDB_defaultCollection!.save(document: doc1Mutable)
        
        guard let doc2Mutable = try otherDB_defaultCollection!.document(id: "pass")?.toMutable() else {
            fatalError("Docs must exists")
        }
        doc2Mutable.setData(["_removed": true])
        try otherDB_defaultCollection!.save(document: doc2Mutable)
        
        run(config: config, expectedError: nil)
        
        // Check documents passed to the filter:
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("pass"))
        
        XCTAssertNotNil(try defaultCollection!.document(id: "doc1"))
        XCTAssertNil(try defaultCollection!.document(id: "pass"))
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
        try defaultCollection!.save(document: doc1)
        
        let doc2 = MutableDocument(id: "pass")
        doc2.setString("pass", forKey: "name")
        try defaultCollection!.save(document: doc2)
        
        // Create replicator with push filter:
        let target = DatabaseEndpoint(database: otherDB!)
        
        let docIds = NSMutableSet()
        var colConfig = CollectionConfiguration(collection: defaultCollection!)
        colConfig.pushFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            
            let isDeleted = flags.contains(.deleted)
            if isDeleted {
                docIds.add(doc.id)
                return doc.id == "pass"
            }
            return doc.string(forKey: "name") == "pass"
        }
        
        let config = self.config(configs: [colConfig], target: target, type: .push, continuous: isContinuous)
        
        // Run the replicator:
        run(config: config, expectedError: nil)
        XCTAssertEqual(docIds.count, 0)
        
        XCTAssertNotNil(try otherDB_defaultCollection!.document(id: "doc1"))
        XCTAssertNotNil(try otherDB_defaultCollection!.document(id: "pass"))
        
        try defaultCollection!.delete(document: doc1)
        try defaultCollection!.delete(document: doc2)
        
        run(config: config, expectedError: nil)
        
        // Check documents passed to the filter:
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("pass"))
        
        XCTAssertNotNil(try otherDB_defaultCollection!.document(id: "doc1"))
        XCTAssertNil(try otherDB_defaultCollection!.document(id: "pass"))
    }
    
    func testPullDeletedDocWithFilter(_ isContinuous: Bool) throws {
        // Create documents:
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("pass", forKey: "name")
        try otherDB_defaultCollection!.save(document: doc1)
        
        let doc2 = MutableDocument(id: "pass")
        doc2.setString("pass", forKey: "name")
        try otherDB_defaultCollection!.save(document: doc2)
        
        // Create replicator with push filter:
        let target = DatabaseEndpoint(database: otherDB!)
        
        let docIds = NSMutableSet()
        var colConfig = CollectionConfiguration(collection: defaultCollection!)
        colConfig.pullFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            
            let isDeleted = flags.contains(.deleted)
            if isDeleted {
                docIds.add(doc.id)
                return doc.id == "pass"
            }
            return doc.string(forKey: "name") == "pass"
        }
        
        let config = self.config(configs: [colConfig], target: target, type: .pull, continuous: isContinuous)
        
        // Run the replicator:
        run(config: config, expectedError: nil)
        XCTAssertEqual(docIds.count, 0)
        
        XCTAssertNotNil(try defaultCollection!.document(id: "doc1"))
        XCTAssertNotNil(try defaultCollection!.document(id: "pass"))
        
        try otherDB_defaultCollection!.delete(document: doc1)
        try otherDB_defaultCollection!.delete(document: doc2)
        
        run(config: config, expectedError: nil)
        
        // Check documents passed to the filter:
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("pass"))
        
        XCTAssertNotNil(try defaultCollection!.document(id: "doc1"))
        XCTAssertNil(try defaultCollection!.document(id: "pass"))
    }
    
    // MARK: stop and restart replication with filter
    
    func testStopAndRestartPushReplicationWithFilter() throws {
        // Create documents:
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("pass", forKey: "name")
        try defaultCollection!.save(document: doc1)
        
        // Create replicator with pull filter:
        let target = DatabaseEndpoint(database: otherDB!)
        
        let docIds = NSMutableSet()
        var colConfig = CollectionConfiguration(collection: defaultCollection!)
        colConfig.pushFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            docIds.add(doc.id)
            return doc.string(forKey: "name") == "pass"
        }
        
        let config = self.config(configs: [colConfig], target: target, type: .push, continuous: true)
        
        // create a replicator
        repl = Replicator(config: config)
        run(replicator: repl, expectedError: nil)
        
        XCTAssertEqual(docIds.count, 1)
        XCTAssertEqual(otherDB_defaultCollection!.count, 1)
        XCTAssertEqual(defaultCollection!.count, 1)
        
        // make some more changes
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("pass", forKey: "name")
        try defaultCollection!.save(document: doc2)
        
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("donotpass", forKey: "name")
        try defaultCollection!.save(document: doc3)
        
        // restart the same replicator
        docIds.removeAllObjects()
        run(replicator: repl, expectedError: nil)
        
        // should use the same replicator filter.
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc3"))
        XCTAssert(docIds.contains("doc2"))
        
        XCTAssertNotNil(try otherDB_defaultCollection!.document(id: "doc1"))
        XCTAssertNotNil(try otherDB_defaultCollection!.document(id: "doc2"))
        XCTAssertNil(try otherDB_defaultCollection!.document(id: "doc3"))
        XCTAssertEqual(defaultCollection!.count, 3)
        XCTAssertEqual(otherDB_defaultCollection!.count, 2)
    }
    
    func testStopAndRestartPullReplicationWithFilter() throws {
        // Create documents:
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("pass", forKey: "name")
        try otherDB_defaultCollection!.save(document: doc1)
        
        // Create replicator with pull filter:
        let target = DatabaseEndpoint(database: otherDB!)
        
        let docIds = NSMutableSet()
        var colConfig = CollectionConfiguration(collection: defaultCollection!)
        colConfig.pullFilter = { (doc, flags) in
            XCTAssertNotNil(doc.id)
            docIds.add(doc.id)
            return doc.string(forKey: "name") == "pass"
        }
        
        let config = self.config(configs: [colConfig], target: target, type: .pull, continuous: true)
        
        // create a replicator
        repl = Replicator(config: config)
        run(replicator: repl, expectedError: nil)
        
        XCTAssertEqual(docIds.count, 1)
        XCTAssertEqual(otherDB_defaultCollection!.count, 1)
        XCTAssertEqual(defaultCollection!.count, 1)
        
        // make some more changes
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("pass", forKey: "name")
        try otherDB_defaultCollection!.save(document: doc2)
        
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("donotpass", forKey: "name")
        try otherDB_defaultCollection!.save(document: doc3)
        
        // restart the same replicator
        docIds.removeAllObjects()
        run(replicator: repl, expectedError: nil)
        
        // should use the same replicator filter.
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc3"))
        XCTAssert(docIds.contains("doc2"))
        
        XCTAssertNotNil(try defaultCollection!.document(id: "doc1"))
        XCTAssertNotNil(try defaultCollection!.document(id: "doc2"))
        XCTAssertNil(try defaultCollection!.document(id: "doc3"))
        XCTAssertEqual(otherDB_defaultCollection!.count, 3)
        XCTAssertEqual(defaultCollection!.count, 2)
    }
    
    #endif
    
    func testReplicatorConfigDefaultValues() {
        let target = URLEndpoint(url: URL(string: "ws://foo.couchbase.com/db")!)
        let collections = CollectionConfiguration.fromCollections([defaultCollection!])
        var config = ReplicatorConfiguration(collections: collections, target: target)
        
        XCTAssertEqual(config.replicatorType, ReplicatorConfiguration.defaultType)
        XCTAssertEqual(config.continuous, ReplicatorConfiguration.defaultContinuous)
        
#if os(iOS)
        XCTAssertEqual(config.allowReplicatingInBackground, ReplicatorConfiguration.defaultAllowReplicatingInBackground)
#endif
        XCTAssertEqual(config.heartbeat, ReplicatorConfiguration.defaultHeartbeat)
        XCTAssertEqual(config.maxAttempts, ReplicatorConfiguration.defaultMaxAttemptsSingleShot)
        XCTAssertEqual(config.maxAttemptWaitTime, ReplicatorConfiguration.defaultMaxAttemptsWaitTime)
        XCTAssertEqual(config.enableAutoPurge, ReplicatorConfiguration.defaultEnableAutoPurge)
        
        config.continuous = true
        XCTAssertEqual(config.maxAttempts, ReplicatorConfiguration.defaultMaxAttemptsContinuous)
    }
    
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
        let collections = CollectionConfiguration.fromCollections([defaultCollection!])
        var config = ReplicatorConfiguration(collections: collections, target: kConnRefusedTarget)
        XCTAssertEqual(config.heartbeat, ReplicatorConfiguration.defaultHeartbeat)
        config.heartbeat = 60
        repl = Replicator(config: config)
        
        XCTAssertEqual(repl.config.heartbeat, 60)
        XCTAssertEqual(config.heartbeat, 60)
        repl = nil
    }
    
    // MARK: MaxAttempt Logic
    
    func testMaxAttemptCount() {
        // single shot
        let collections = CollectionConfiguration.fromCollections([defaultCollection!])
        var config = ReplicatorConfiguration(collections: collections, target: kConnRefusedTarget)
        XCTAssertEqual(config.maxAttempts, ReplicatorConfiguration.defaultMaxAttemptsSingleShot)
        
        // continous
        config.continuous = true
        XCTAssertEqual(config.maxAttempts, ReplicatorConfiguration.defaultMaxAttemptsContinuous)
    }
    
    func testCustomMaxAttemptCount() {
        // single shot
        let collections = CollectionConfiguration.fromCollections([defaultCollection!])
        var config = ReplicatorConfiguration(collections: collections, target: kConnRefusedTarget)
        XCTAssertEqual(config.maxAttempts, ReplicatorConfiguration.defaultMaxAttemptsSingleShot)
        config.maxAttempts = 22
        XCTAssertEqual(config.maxAttempts, 22)
        
        // continous
        config = ReplicatorConfiguration(collections: collections, target: kConnRefusedTarget)
        config.continuous = true
        XCTAssertEqual(config.maxAttempts, ReplicatorConfiguration.defaultMaxAttemptsContinuous)
        config.maxAttempts = 11
        XCTAssertEqual(config.maxAttempts, 11)
    }
    
    func testMaxAttempt(attempt: UInt, count: Int, continuous: Bool) {
        let x = self.expectation(description: "repl finish")
        let config: ReplicatorConfiguration = self.config(collections: [defaultCollection!],
                                                          target: kConnRefusedTarget,
                                                          type: .pushAndPull,
                                                          continuous: continuous,
                                                          maxAttempts: attempt)
        var offlineCount = 0
        repl = Replicator(config: config)
        repl.addChangeListener { (change) in
            if change.status.activity == .offline {
                offlineCount += 1
            } else if change.status.activity == .stopped {
                x.fulfill()
            }
        }
        
        repl.start()
        wait(for: [x], timeout:  pow(2, Double(count + 1)) + expTimeout)
        XCTAssertEqual(count, offlineCount)
    }
    
    // todo - currently failing on last two
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
        var config = self.config(collections: [defaultCollection!], target: kConnRefusedTarget,
                                 type: .pushAndPull, continuous: false)
        XCTAssertEqual(config.maxAttemptWaitTime, ReplicatorConfiguration.defaultMaxAttemptsWaitTime)
        
        // continous
        config = self.config(collections: [defaultCollection!], target: kConnRefusedTarget,
                             type: .pushAndPull, continuous: true)
        XCTAssertEqual(config.maxAttemptWaitTime, ReplicatorConfiguration.defaultMaxAttemptsWaitTime)
        
        repl = Replicator(config: config)
        XCTAssertEqual(repl.config.maxAttemptWaitTime, ReplicatorConfiguration.defaultMaxAttemptsWaitTime)
    }
    
    func testCustomMaxAttemptWaitTime() {
        // single shot
        var config: ReplicatorConfiguration = self.config(target: self.kConnRefusedTarget,
                                                          type: .pushAndPull, continuous: false)
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
                    var config: ReplicatorConfiguration = self.config(target: self.kConnRefusedTarget,
                                                                      type: .pushAndPull, continuous: false)
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
        let x = self.expectation(description: "repl finish")
        var config = self.config(collections: [defaultCollection!], target: kConnRefusedTarget,
                                 type: .pushAndPull, continuous: false)
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
        wait(for: [x], timeout: expTimeout)
        XCTAssert(abs(diff - config.maxAttemptWaitTime) < 1.0)
    }
    
    // MARK: Change Listener
    
    func testRemoveChangeListener() throws {
        let x1 = self.expectation(description: "Replicator Stopped")
        let x2 = self.expectation(description: "Replicator Stopped - Inverted")
        x2.isInverted = true
        
        var config = self.config(collections: [defaultCollection!], target: kConnRefusedTarget)
        config.maxAttempts = 1
        
        repl = Replicator(config: config)
        let token1 = repl.addChangeListener { (change) in
            if change.status.activity == .stopped {
                x1.fulfill()
            }
        }
        
        let token2 = repl.addChangeListener { (change) in
            x2.fulfill()
        }
        token2.remove()
        
        repl.start()
        wait(for: [x1, x2], timeout: expTimeout)
        token1.remove()
    }
    
    // MARK: ReplicatorConfig
    
    func testCopyingReplicatorConfiguration() throws {
        let target = URLEndpoint(url: URL(string: "ws://foo.couchbase.com/db")!)
        
        let filter = { (doc: Document, flags: DocumentFlags) -> Bool in
            guard doc.boolean(forKey: "sync") else {
                return false
            }
            
            return !flags.contains(.deleted)
        }
        
        var colConfig1 = CollectionConfiguration(collection: otherDB_defaultCollection!)
        colConfig1.channels = ["c1", "c2"]
        colConfig1.documentIDs = ["d1", "d2"]
        colConfig1.pushFilter = filter
        colConfig1.pullFilter = filter

        var config1 = ReplicatorConfiguration(collections: [colConfig1], target: target)
        
        #if COUCHBASE_ENTERPRISE
        config1.acceptOnlySelfSignedServerCertificate = true
        #endif
        
        config1.continuous = true
        config1.headers = ["a": "aa", "b": "bb"]
        config1.replicatorType = .pull
        config1.heartbeat = 211
        config1.maxAttempts = 223
        config1.maxAttemptWaitTime = 227
        
        let basic = BasicAuthenticator(username: "abcd", password: "1234")
        config1.authenticator = basic
        
        let certData = try dataFromResource(name: "SelfSigned", ofType: "cer")
        let cert = SecCertificateCreateWithData(kCFAllocatorDefault, certData as CFData)!
        config1.pinnedServerCertificate = cert
        
        // copying
        let config = ReplicatorConfiguration(config: config1)
        
        // update config1 after passing to configuration’s constructor
        #if COUCHBASE_ENTERPRISE
        config1.acceptOnlySelfSignedServerCertificate = false
        #endif
        config1.continuous = false
        config1.authenticator = nil
        config1.headers = nil
        config1.replicatorType = .push
        config1.heartbeat = 11
        config1.maxAttempts = 13
        config1.maxAttemptWaitTime = 17
        config1.pinnedServerCertificate = nil
        colConfig1.channels = nil
        colConfig1.documentIDs = nil
        colConfig1.pullFilter = nil
        colConfig1.pushFilter = nil
        
        XCTAssert(config.continuous)
        XCTAssertEqual((config.authenticator as! BasicAuthenticator).username, basic.username)
        XCTAssertEqual((config.authenticator as! BasicAuthenticator).password, basic.password)
        XCTAssertEqual(config.headers, ["a": "aa", "b": "bb"])
        XCTAssertEqual(config.replicatorType, .pull)
        XCTAssertEqual(config.heartbeat, 211)
        XCTAssertEqual(config.maxAttempts, 223)
        XCTAssertEqual(config.maxAttemptWaitTime, 227)
        XCTAssertEqual(config.pinnedServerCertificate, cert)
        XCTAssertEqual(config.collectionConfigs.count, 1)
        XCTAssertEqual(config.collectionConfigs.first?.channels, ["c1", "c2"])
        XCTAssertEqual(config.collectionConfigs.first?.documentIDs, ["d1", "d2"])
        XCTAssertNotNil(config.collectionConfigs.first?.pushFilter)
        XCTAssertNotNil(config.collectionConfigs.first?.pullFilter)
        
    #if COUCHBASE_ENTERPRISE
        XCTAssert(config.acceptOnlySelfSignedServerCertificate)
    #endif
    }
    
    func testReplicationConfigSetterMethods() throws {
        let target = URLEndpoint(url: URL(string: "ws://foo.couchbase.com/db")!)
        
        let filter = { (doc: Document, flags: DocumentFlags) -> Bool in
            guard doc.boolean(forKey: "sync") else {
                return false
            }
            
            return !flags.contains(.deleted)
        }
        
        var colConfig = CollectionConfiguration(collection: otherDB_defaultCollection!)
        colConfig.channels = ["c1", "c2"]
        colConfig.documentIDs = ["d1", "d2"]
        colConfig.pushFilter = filter
        colConfig.pullFilter = filter
        
        var config = ReplicatorConfiguration(collections: [colConfig], target: target)
        config.continuous = true
        config.headers = ["a": "aa", "b": "bb"]
        config.replicatorType = .pull
        config.heartbeat = 211
        config.maxAttempts = 223
        config.maxAttemptWaitTime = 227
        
        let basic = BasicAuthenticator(username: "abcd", password: "1234")
        config.authenticator = basic
        
        let certData = try dataFromResource(name: "SelfSigned", ofType: "cer")
        let cert = SecCertificateCreateWithData(kCFAllocatorDefault, certData as CFData)!
        config.pinnedServerCertificate = cert
        
    #if COUCHBASE_ENTERPRISE
        config.acceptOnlySelfSignedServerCertificate = true
    #endif
        
        // set correctly on replicator
        repl = Replicator(config:  config)
        
        XCTAssert(repl.config.continuous)
        XCTAssertEqual((repl.config.authenticator as! BasicAuthenticator).username, basic.username)
        XCTAssertEqual((repl.config.authenticator as! BasicAuthenticator).password, basic.password)
        XCTAssertEqual(repl.config.headers, ["a": "aa", "b": "bb"])
        XCTAssertEqual(repl.config.replicatorType, .pull)
        XCTAssertEqual(repl.config.heartbeat, 211)
        XCTAssertEqual(repl.config.maxAttempts, 223)
        XCTAssertEqual(repl.config.maxAttemptWaitTime, 227)
        XCTAssertEqual(repl.config.pinnedServerCertificate, cert)
        
    #if COUCHBASE_ENTERPRISE
        XCTAssert(repl.config.acceptOnlySelfSignedServerCertificate)
    #endif
        
        let colConfigs = repl.config.collectionConfigs
        XCTAssertEqual(colConfigs.count, 1)
        XCTAssertEqual(colConfigs.first?.channels, ["c1", "c2"])
        XCTAssertEqual(colConfigs.first?.documentIDs, ["d1", "d2"])
        XCTAssertNotNil(colConfigs.first?.pushFilter)
        XCTAssertNotNil(colConfigs.first?.pullFilter)
    }
    
    func testDefaultReplicatorConfiguration() throws {
        let target = URLEndpoint(url: URL(string: "ws://foo.couchbase.com/db")!)
        let collections = CollectionConfiguration.fromCollections([otherDB_defaultCollection!])
        var config = ReplicatorConfiguration(collections: collections, target: target)
        
        XCTAssertNil(config.authenticator)
        XCTAssertNil(config.headers)
        XCTAssertNil(config.pinnedServerCertificate)
        XCTAssertEqual(config.continuous, ReplicatorConfiguration.defaultContinuous)
        XCTAssertEqual(config.heartbeat, ReplicatorConfiguration.defaultHeartbeat)
        XCTAssertEqual(config.maxAttempts, ReplicatorConfiguration.defaultMaxAttemptsSingleShot)
        XCTAssertEqual(config.maxAttemptWaitTime, ReplicatorConfiguration.defaultMaxAttemptsWaitTime)
        XCTAssertEqual(config.replicatorType, ReplicatorConfiguration.defaultType)
        XCTAssertEqual(config.enableAutoPurge, ReplicatorConfiguration.defaultEnableAutoPurge)
        
    #if os(iOS)
        XCTAssertEqual(config.allowReplicatingInBackground, ReplicatorConfiguration.defaultAllowReplicatingInBackground)
    #endif
        
    #if COUCHBASE_ENTERPRISE
        XCTAssertEqual(config.acceptOnlySelfSignedServerCertificate, ReplicatorConfiguration.defaultSelfSignedCertificateOnly)
    #endif
        
        XCTAssertEqual(config.collectionConfigs.count, 1)
        XCTAssertNil(config.collectionConfigs.first?.channels)
        XCTAssertNil(config.collectionConfigs.first?.conflictResolver)
        XCTAssertNil(config.collectionConfigs.first?.documentIDs)
        XCTAssertNil(config.collectionConfigs.first?.pullFilter)
        XCTAssertNil(config.collectionConfigs.first?.pushFilter)
    }
}

class TestConflictResolver: ConflictResolverProtocol {
    var winner: Document? = nil
    let _resolver: (Conflict) -> Document?
    
    // set this resolver, which will be used while resolving the conflict
    init(_ resolver: @escaping (Conflict) -> Document?) {
        _resolver = resolver
    }
    
    func resolve(conflict: Conflict) -> Document? {
        winner = _resolver(conflict)
        return winner
    }
}
