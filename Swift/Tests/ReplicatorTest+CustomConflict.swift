//
//  ReplicatorTest+CustomConflict.swift
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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

class ReplicatorTest_CustomConflict: ReplicatorTest {
    
    #if COUCHBASE_ENTERPRISE
    
    func testConflictHandlerRemoteWins() throws {
        let doc = MutableDocument(id: "doc")
        doc.setString("Tiger", forKey: "species")
        try db.saveDocument(doc)
        
        let target = DatabaseEndpoint(database: otherDB)
        var config = self.config(target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
        
        // make changes to both documents from db and otherDB
        let doc1 = db.document(withID: "doc")!.toMutable()
        doc1.setString("Hobbes", forKey: "name")
        try db.saveDocument(doc1)
        
        let doc2 = otherDB.document(withID: "doc")!.toMutable()
        doc2.setString("striped", forKey: "pattern")
        try otherDB.saveDocument(doc2)
        
        // Pull:
        config = self.config(target: target, type: .pull, continuous: false)
        let resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.remoteDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(db.count, 1)
        
        let savedDoc = db.document(withID: "doc")!
        
        let exp: [String: Any] = ["species": "Tiger", "pattern": "striped"]
        XCTAssertEqual(resolver.winner!, savedDoc)
        XCTAssertEqual(savedDoc.toDictionary().count, 2)
        XCTAssertEqual(savedDoc.toDictionary().keys, exp.keys)
    }
    
    func testConflictHandlerLocalWins() throws {
        let doc = MutableDocument(id: "doc")
        doc.setString("Tiger", forKey: "species")
        try db.saveDocument(doc)
        
        let target = DatabaseEndpoint(database: otherDB)
        var config = self.config(target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
        
        // make changes to both documents from db and otherDB
        let doc1 = db.document(withID: "doc")!.toMutable()
        doc1.setString("Hobbes", forKey: "name")
        try db.saveDocument(doc1)
        
        let doc2 = otherDB.document(withID: "doc")!.toMutable()
        doc2.setString("striped", forKey: "pattern")
        try otherDB.saveDocument(doc2)
        
        // Pull:
        config = self.config(target: target, type: .pull, continuous: false)
        let resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.localDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(db.count, 1)
        
        let savedDoc = db.document(withID: "doc")!
        
        let exp: [String: Any] = ["species": "Tiger", "name": "Hobbes"]
        XCTAssertEqual(resolver.winner!, savedDoc)
        XCTAssertEqual(savedDoc.toDictionary().count, 2)
        XCTAssertEqual(savedDoc.toDictionary().keys, exp.keys)
    }
    
    func testConflictHandlerNullDoc() throws {
        let doc = MutableDocument(id: "doc")
        doc.setString("Tiger", forKey: "species")
        try db.saveDocument(doc)
        
        let target = DatabaseEndpoint(database: otherDB)
        var config = self.config(target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
        
        // make changes to both documents from db and otherDB
        let doc1 = db.document(withID: "doc")!.toMutable()
        doc1.setString("Hobbes", forKey: "name")
        try db.saveDocument(doc1)
        
        let doc2 = otherDB.document(withID: "doc")!.toMutable()
        doc2.setString("striped", forKey: "pattern")
        try otherDB.saveDocument(doc2)
        
        // Pull:
        config = self.config(target: target, type: .pull, continuous: false)
        let resolver = TestConflictResolver() { (conflict) -> Document? in
            return nil
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertNil(resolver.winner)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: "doc"))
    }
    
    func testConflictHandlerDeletedLocalWins() throws {
        let doc = MutableDocument(id: "doc")
        doc.setString("Tiger", forKey: "species")
        try db.saveDocument(doc)
        
        let target = DatabaseEndpoint(database: otherDB)
        var config = self.config(target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
        
        // make changes to both documents from db and otherDB
        try db.deleteDocument(db.document(withID: "doc")!)
        
        let doc2 = otherDB.document(withID: "doc")!.toMutable()
        doc2.setString("striped", forKey: "pattern")
        try otherDB.saveDocument(doc2)
        
        // Pull:
        config = self.config(target: target, type: .pull, continuous: false)
        let resolver = TestConflictResolver() { (conflict) -> Document? in
            return nil
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertNil(resolver.winner)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: "doc"))
    }
    
    func testConflictHandlerDeletedRemoteWins() throws {
        let doc = MutableDocument(id: "doc")
        doc.setString("Tiger", forKey: "species")
        try db.saveDocument(doc)
        
        let target = DatabaseEndpoint(database: otherDB)
        var config = self.config(target: target, type: .push, continuous: false)
        run(config: config, expectedError: nil)
        
        // make changes to both documents from db and otherDB
        let doc1 = db.document(withID: "doc")!.toMutable()
        doc1.setString("Hobbes", forKey: "name")
        try db.saveDocument(doc1)
        
        try otherDB.deleteDocument(otherDB.document(withID: "doc")!)
        
        // Pull:
        config = self.config(target: target, type: .pull, continuous: false)
        let resolver = TestConflictResolver() { (conflict) -> Document? in
            return nil
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertNil(resolver.winner)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: "doc"))
    }
    
    #endif
}


class TestConflictResolver: ConflictResolver {
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
