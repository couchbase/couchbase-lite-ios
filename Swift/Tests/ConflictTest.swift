//
//  ConflictTest.swift
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


class ConflictTest: CBLTestCase {
    class TheirsWins: ConflictResolver {
        func resolve(conflict: Conflict) -> Document? {
            return conflict.theirs
        }
    }
    
    
    class MergeThenTheirsWins: ConflictResolver {
        func resolve(conflict: Conflict) -> Document? {
            let resolved = MutableDocument()
            if let base = conflict.base {
                for key in base {
                    resolved.setValue(base.value(forKey: key), forKey: key)
                }
            }
            
            var changed = Set<String>()
            for key in conflict.theirs {
                resolved.setValue(conflict.theirs.value(forKey: key), forKey: key)
                changed.insert(key)
            }
            
            for key in conflict.mine {
                if !changed.contains(key) {
                    resolved.setValue(conflict.mine.value(forKey: key), forKey: key)
                }
            }
            return resolved
        }
    }
    
    
    class GiveUp: ConflictResolver {
        func resolve(conflict: Conflict) -> Document? {
            return nil
        }
    }
    
    
    class DoNotResolve: ConflictResolver {
        func resolve(conflict: Conflict) -> Document? {
            XCTAssert(false, "Resolver should not have been called!")
            return nil
        }
    }
    
    
    func setupConflict() throws -> MutableDocument {
        // Setup a default database conflict resolver:
        var doc = createDocument("doc1")
        doc.setValue("profile", forKey: "type")
        doc.setValue("Scott", forKey: "name")
        let savedDoc = try saveDocument(doc)
        
        // Force a conflict:
        let properties: [String: Any] = ["name": "Scotty"];
        try saveProperties(properties, docID: doc.id)
        
        // Change document in memory, so save will trigger a conflict
        doc = savedDoc.toMutable()
        doc.setValue("Scott Pilgrim", forKey: "name")
        return doc
    }
    
    
    func saveProperties(_ props: Dictionary<String, Any>, docID: String) throws {
        // Save to database
        let doc = db.document(withID: docID)!.toMutable()
        doc.setData(props)
        try saveDocument(doc)
    }
    
    
    override func setUp() {
        self.conflictResolver = DoNotResolve()
        super.setUp()
    }
    
    
    func testConflict() throws {
        self.conflictResolver = TheirsWins()
        try reopenDB()
        
        let doc1 = try setupConflict()
        let savedDoc1 = try saveDocument(doc1)
        XCTAssertEqual(savedDoc1.string(forKey: "name")!, "Scotty")
        
        // Get a new document with its own conflict resolver:
        self.conflictResolver = MergeThenTheirsWins()
        try reopenDB()
        
        var doc2 = createDocument("doc2")
        doc2.setValue("profile", forKey: "type")
        doc2.setValue("Scott", forKey: "name")
        var savedDoc2 = try saveDocument(doc2)
        
        // Force a conflict again:
        var properties = savedDoc2.toDictionary()
        properties["type"] = "bio"
        properties["gender"] = "male"
        try saveProperties(properties, docID: savedDoc2.id)
        
        doc2 = savedDoc2.toMutable()
        doc2.setValue("biography", forKey: "type")
        doc2.setValue(31, forKey: "age")
        savedDoc2 = try saveDocument(doc2)
        
        XCTAssertEqual(savedDoc2.int(forKey: "age"), 31)
        XCTAssertEqual(savedDoc2.string(forKey: "type")!, "bio")
        XCTAssertEqual(savedDoc2.string(forKey: "gender")!, "male")
        XCTAssertEqual(savedDoc2.string(forKey: "name")!, "Scott")
    }
    
    
    func testConflictResolverGivesUp() throws {
        self.conflictResolver = GiveUp()
        try reopenDB()
        
        let doc = try setupConflict()
        XCTAssertThrowsError(try saveDocument(doc), "") { (e) in
            let error = e as NSError
            XCTAssertEqual(error.domain, CBLErrorDomain)
            XCTAssertEqual(error.code, CBLErrorConflict)
        }
    }
    
    
    func testDeletionConflict() throws {
        self.conflictResolver = nil
        try reopenDB()
        
        let doc = try setupConflict()
        try db.deleteDocument(doc)
        
        let deletedDoc = db.document(withID: doc.id)
        XCTAssertNil (deletedDoc)
    }
    
    func testConflictMineIsDeeper() throws {
        self.conflictResolver = nil
        try reopenDB()
        
        let doc = try setupConflict()
        try saveDocument(doc)
        XCTAssertEqual(doc.string(forKey: "name")!, "Scott Pilgrim")
    }
    
    
    func testConflictTheirsIsDepper() throws {
        self.conflictResolver = nil
        try reopenDB()
        
        let doc = try setupConflict()
        
        // Add another revision to the conflict, so it'll have a higher generation:
        var properties = doc.toDictionary()
        properties["name"] = "Scott of the Sahara"
        try saveProperties(properties, docID: doc.id)
        
        let savedDoc = try saveDocument(doc)
        XCTAssertEqual(savedDoc.string(forKey: "name")!, "Scott of the Sahara")
    }
}

