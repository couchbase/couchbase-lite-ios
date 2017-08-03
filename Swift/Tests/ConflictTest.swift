//
//  ConflictTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/19/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift


class ConflictTest: CBLTestCase {
    class TheirsWins: ConflictResolver {
        func resolve(conflict: Conflict) -> ReadOnlyDocument? {
            return conflict.theirs
        }
    }
    
    
    class MergeThenTheirsWins: ConflictResolver {
        func resolve(conflict: Conflict) -> ReadOnlyDocument? {
            let resolved = Document()
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
        func resolve(conflict: Conflict) -> ReadOnlyDocument? {
            return nil
        }
    }
    
    
    class DoNotResolve: ConflictResolver {
        func resolve(conflict: Conflict) -> ReadOnlyDocument? {
            XCTAssert(false, "Resolver should not have been called!")
            return nil
        }
    }
    
    
    func setupConflict() throws -> Document {
        // Setup a default database conflict resolver:
        let doc = createDocument("doc1")
        doc.setValue("profile", forKey: "type")
        doc.setValue("Scott", forKey: "name")
        try saveDocument(doc)
        
        // Force a conflict:
        let properties: [String: Any] = ["name": "Scotty"];
        try saveProperties(properties, docID: doc.id)
        
        // Change document in memory, so save will trigger a conflict
        doc.setValue("Scott Pilgrim", forKey: "name")
        return doc
    }
    
    
    func saveProperties(_ props: Dictionary<String, Any>, docID: String) throws {
        // Save to database
        let doc = db.getDocument(docID)!
        doc.setDictionary(props)
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
        try saveDocument(doc1)
        XCTAssertEqual(doc1.string(forKey: "name")!, "Scotty")
        
        // Get a new document with its own conflict resolver:
        self.conflictResolver = MergeThenTheirsWins()
        try reopenDB()
        
        let doc2 = createDocument("doc2")
        doc2.setValue("profile", forKey: "type")
        doc2.setValue("Scott", forKey: "name")
        try saveDocument(doc2)
        
        // Force a conflict again:
        var properties = doc2.toDictionary()
        properties["type"] = "bio"
        properties["gender"] = "male"
        try saveProperties(properties, docID: doc2.id)
        
        doc2.setValue("biography", forKey: "type")
        doc2.setValue(31, forKey: "age")
        try saveDocument(doc2)
        
        XCTAssertEqual(doc2.int(forKey: "age"), 31)
        XCTAssertEqual(doc2.string(forKey: "type")!, "bio")
        XCTAssertEqual(doc2.string(forKey: "gender")!, "male")
        XCTAssertEqual(doc2.string(forKey: "name")!, "Scott")
    }
    
    
    func testConflictResolverGivesUp() throws {
        self.conflictResolver = GiveUp()
        try reopenDB()
        
        let doc = try setupConflict()
        XCTAssertThrowsError(try saveDocument(doc), "") { (e) in
            let error = e as NSError
            XCTAssertEqual(error.domain, "LiteCore")
            XCTAssertEqual(error.code, 14)
        }
    }
    
    
    func testDeletionConflict() throws {
        self.conflictResolver = DoNotResolve()
        try reopenDB()
        
        let doc = try setupConflict()
        try db.delete(doc)
        XCTAssertFalse(doc.isDeleted)
        XCTAssertEqual(doc.string(forKey: "name")!, "Scotty")
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
        
        try saveDocument(doc)
        XCTAssertEqual(doc.string(forKey: "name")!, "Scott of the Sahara")
    }
}

