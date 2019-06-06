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
    
    func getConfig(_ type: ReplicatorType) -> ReplicatorConfiguration {
        let target = DatabaseEndpoint(database: otherDB)
        return config(target: target, type: type, continuous: false)
    }
    
    func makeConflict(forID docID: String,
                      withLocal localData: [String: String],
                      withRemote remoteData: [String: String]) throws {
        // create doc
        let doc = createDocument(docID)
        try saveDocument(doc)
        
        // sync the doc in both DBs.
        let config = getConfig(.push)
        run(config: config, expectedError: nil)
        
        // Now make different changes in db and otherDBs
        let doc1a = db.document(withID: docID)!.toMutable()
        doc1a.setData(localData)
        try saveDocument(doc1a)
        
        let doc1b = otherDB.document(withID: docID)!.toMutable()
        doc1b.setData(remoteData)
        try otherDB.saveDocument(doc1b)
    }
    
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
    
    func testConflictResolverCalledTwice() throws {
        let docID = "doc"
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        let config = getConfig(.pull)
        
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        var count = 0;
        let resolver = TestConflictResolver() { [unowned self] (conflict) -> Document? in
            count += 1
            
            // update the doc will cause a second conflict
            let savedDoc = self.db.document(withID: docID)!.toMutable()
            if !savedDoc["secondUpdate"].exists {
                savedDoc.setBoolean(true, forKey: "secondUpdate")
                try! self.db.saveDocument(savedDoc)
            }
            
            let mDoc = conflict.localDocument!.toMutable()
            mDoc.setString("local", forKey: "edit")
            return mDoc
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(count, 2)
        XCTAssertEqual(self.db.count, 1)
        var expectedDocDict: [String: Any] = localData
        expectedDocDict["edit"] = "local"
        expectedDocDict["secondUpdate"] = true
        XCTAssert(self.db.document(withID: docID)!.toDictionary() == expectedDocDict)
    }
    
    func testConflictResolverMergeDoc() throws {
        let docID = "doc"
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        var resolver: TestConflictResolver!
        let config = getConfig(.pull)
        
        // EDIT LOCAL DOCUMENT
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict: Conflict) -> Document? in
            let doc = conflict.localDocument?.toMutable()
            doc?.setString("local", forKey: "edit")
            return doc
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        var expectedDocDict = localData
        expectedDocDict["edit"] = "local"
        XCTAssert(expectedDocDict == db.document(withID: docID)!.toDictionary())
        
        // EDIT REMOTE DOCUMENT
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict: Conflict) -> Document? in
            let doc = conflict.remoteDocument?.toMutable()
            doc?.setString("remote", forKey: "edit")
            return doc
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        expectedDocDict = remoteData
        expectedDocDict["edit"] = "remote"
        XCTAssert(expectedDocDict == db.document(withID: docID)!.toDictionary())
        
        // CREATE NEW DOCUMENT
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict: Conflict) -> Document? in
            let doc = MutableDocument(id: conflict.localDocument!.id)
            doc.setString("new-with-same-ID", forKey: "docType")
            return doc
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssert(["docType": "new-with-same-ID"] == db.document(withID: docID)!.toDictionary())
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
