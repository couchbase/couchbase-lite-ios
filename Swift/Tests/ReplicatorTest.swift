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
    
    override func setUp() {
        super.setUp()
        otherDB = try! openDB(name: "otherdb")
        XCTAssertNotNil(otherDB)
    }
    
    override func tearDown() {
        try! otherDB.close()
        super.tearDown()
    }
    
    func run(type: ReplicatorType, target: Endpoint, expectedError: Int?) {
        let config = ReplicatorConfiguration(database: self.db, target: target)
        config.replicatorType = type
        run(config: config, reset: false, expectedError: expectedError)
    }
    
    func run(type: ReplicatorType, target: Endpoint, reset: Bool, expectedError: Int?) {
        let config = ReplicatorConfiguration(database: self.db, target: target)
        config.replicatorType = type
        run(config: config, reset: reset, expectedError: expectedError)
    }
    
    func run(config: ReplicatorConfiguration, reset: Bool, expectedError: Int?) {
        let x = self.expectation(description: "change")
        let repl = Replicator(config: config)
        let token = repl.addChangeListener { (change) in
            let status = change.status
            if status.activity == .stopped {
                if let err = expectedError {
                    let error = status.error as NSError?
                    XCTAssertNotNil(error)
                    XCTAssertEqual(error!.code, err)
                }
                x.fulfill()
            }
        }
        
        if reset {
            repl.resetCheckpoint()
        }
        
        repl.start()
        wait(for: [x], timeout: 5.0)
        repl.removeChangeListener(withToken: token)
    }

    #if COUCHBASE_ENTERPRISE
    
    func testEmptyPush() throws {
        let target = DatabaseEndpoint(database: otherDB)
        run(type: .push, target: target, expectedError: nil)
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
        run(type: .push, target: target, expectedError: nil)
        
        // Pull:
        run(type: .pull, target: target, expectedError: nil)
        
        XCTAssertEqual(self.db.count, 2)
        
        var doc = self.db.document(withID: "doc1")!
        try self.db.purgeDocument(doc)
        
        doc = self.db.document(withID: "doc2")!
        try self.db.purgeDocument(doc)
        
        XCTAssertEqual(self.db.count, 0)
        
        // Pull again, shouldn't have any new changes:
        run(type: .pull, target: target, expectedError: nil)
        XCTAssertEqual(self.db.count, 0)
        
        // Reset and pull:
        run(type: .pull, target: target, reset: true, expectedError: nil)
        XCTAssertEqual(self.db.count, 2)
    }
    
    #endif
}
