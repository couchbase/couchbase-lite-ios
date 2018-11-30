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
    var otherDB: Database!
    var repl: Replicator!
    
    override func setUp() {
        super.setUp()
        Database.setLogLevel(.debug, domain: .all)
        otherDB = try! openDB(name: "otherdb")
        XCTAssertNotNil(otherDB)
    }
    
    override func tearDown() {
        // Workaround to ensure that replicator's background cleaning task was done:
        // https://github.com/couchbase/couchbase-lite-core/issues/520
        Thread.sleep(forTimeInterval: 0.3);
        
        try! otherDB.close()
        otherDB = nil
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
        
        replicator.stop()
        replicator.removeChangeListener(withToken: token)
    }

    #if COUCHBASE_ENTERPRISE
    
    func testEmptyPush() throws {
        let target = DatabaseEndpoint(database: otherDB)
        let config = self.config(target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
    }
    
    func testResetCheckpoint() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "name")
        try self.db.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("striped", forKey: "pattern")
        try self.db.saveDocument(doc2)
        
        // Push:
        let target = DatabaseEndpoint(database: otherDB)
        var config = self.config(target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
        
        // Pull:
        config = self.config(target: target, type: .pull, continuous: false)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(self.db.count, 2)
        
        var doc = self.db.document(withID: "doc1")!
        try self.db.purgeDocument(doc)
        
        doc = self.db.document(withID: "doc2")!
        try self.db.purgeDocument(doc)
        
        XCTAssertEqual(self.db.count, 0)
        
        // Pull again, shouldn't have any new changes:
        run(config: config, expectedError: nil)
        XCTAssertEqual(self.db.count, 0)
        
        // Reset and pull:
        run(config: config, reset: true, expectedError: nil)
        XCTAssertEqual(self.db.count, 2)
    }
    
    func testResetCheckpointContinuous() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "name")
        try self.db.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("striped", forKey: "pattern")
        try self.db.saveDocument(doc2)
        
        // Push:
        let target = DatabaseEndpoint(database: otherDB)
        var config = self.config(target: target, type: .push, continuous: true)
        run(config: config, expectedError: nil)
        
        // Pull:
        config = self.config(target: target, type: .pull, continuous: true)
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(self.db.count, 2)
        
        var doc = self.db.document(withID: "doc1")!
        try self.db.purgeDocument(doc)
        
        doc = self.db.document(withID: "doc2")!
        try self.db.purgeDocument(doc)
        
        XCTAssertEqual(self.db.count, 0)
        
        // Pull again, shouldn't have any new changes:
        run(config: config, expectedError: nil)
        XCTAssertEqual(self.db.count, 0)
        
        // Reset and pull:
        run(config: config, reset: true, expectedError: nil)
        XCTAssertEqual(self.db.count, 2)
    }
    
    func testDocumentReplicationListener() throws {
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("Tiger", forKey: "species")
        doc1.setString("Hobbes", forKey: "name")
        try self.db.saveDocument(doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("Tiger", forKey: "species")
        doc2.setString("Striped", forKey: "pattern")
        try self.db.saveDocument(doc2)
        
        // Push:
        let target = DatabaseEndpoint(database: otherDB)
        let config = self.config(target: target, type: .push, continuous: false)
        
        var replicator: Replicator!
        var token: ListenerToken!
        let docIds = NSMutableSet()
        self.run(config: config, reset: false, expectedError: nil) { (r) in
            replicator = r
            token = r.addReplicationListener({ (replication) in
                docIds.add(replication.documentID)
            })
        }
        
        // Check if getting two document replication events:
        XCTAssertEqual(docIds.count, 2)
        XCTAssert(docIds.contains("doc1"))
        XCTAssert(docIds.contains("doc2"))
        
        // Add another doc:
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("Tiger", forKey: "species")
        doc3.setString("Star", forKey: "pattern")
        try self.db.saveDocument(doc3)
        
        // Run the replicator again:
        self.run(withReplicator: replicator, expectedError: nil)
        
        // Check if getting a new document replication event:
        XCTAssertEqual(docIds.count, 3)
        XCTAssert(docIds.contains("doc3"))
        
        // Add another doc:
        let doc4 = MutableDocument(id: "doc4")
        doc4.setString("Tiger", forKey: "species")
        doc4.setString("WhiteStriped", forKey: "pattern")
        try self.db.saveDocument(doc4)
        
        // Remove document replication listener:
        replicator.removeChangeListener(withToken: token)
        
        // Run the replicator again:
        self.run(withReplicator: replicator, expectedError: nil)
        
        // Should not getting a new document replication event:
        XCTAssertEqual(docIds.count, 3)
    }
    
    #endif
}
