//
//  DatabaseTest.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift


class DatabaseTest: CBLTestCase {

    func testProperties() throws {
        XCTAssertEqual(db.name, kDatabaseName)
        XCTAssert(db.path!.contains(kDatabaseName))
        XCTAssert(Database.exists(kDatabaseName, inDirectory: kDirectory))
    }

    func testCreateUntitledDocument() throws {
        let doc = Document()
        XCTAssertFalse(doc.id.isEmpty)
        XCTAssertFalse(doc.isDeleted)
        XCTAssertTrue(doc.toDictionary() == [:] as [String: Any])
    }

    func testCreateNamedDocument() throws {
        XCTAssertFalse(db.contains("doc1"))

        let doc = Document("doc1")
        XCTAssertEqual(doc.id, "doc1")
        XCTAssertFalse(doc.isDeleted)
        XCTAssertTrue(doc.toDictionary() == [:] as [String: Any])
        
        try db.save(doc)
    }

    func testInBatch() throws {
        try db.inBatch {
            for i in 0...9{
                let doc = Document("doc\(i)")
                try db.save(doc)
            }
        }
        for i in 0...9 {
            XCTAssert(db.contains("doc\(i)"))
        }
    }
    
    func testCopy() throws {
        for i in 0...9 {
            let docID = "doc\(i)"
            let doc = self.createDocument(docID)
            doc.setValue(docID, forKey: "name")
            
            let data = docID.data(using: .utf8)
            let blob = Blob.init(contentType: "text/plain", data: data!)
            doc.setValue(blob, forKey: "data")
            
            try self.saveDocument(doc)
        }
        
        let dbName = "nudb"
        let config = db.config
        let dir = config.directory
        
        // Make sure no an existing database at the new location:
        try Database.delete(dbName, inDirectory: dir)
        
        // Copy:
        try Database.copy(fromPath: db.path!, toDatabase: dbName, config: config)
        
        // Verify:
        XCTAssert(Database.exists(dbName, inDirectory: dir))
        let nudb = try Database.init(name: dbName, config: config)
        XCTAssertEqual(nudb.count, 10)
        
        let query = Query
            .select(SelectResult.expression(Expression.meta().id))
            .from(DataSource.database(self.db))
        let rs = try query.run()
        for r in rs {
            let docID = r.string(at: 0)!
            let doc = nudb.getDocument(docID)!
            XCTAssertEqual(doc.string(forKey: "name"), docID)
            
            let blob = doc.blob(forKey: "data")!
            let data = String.init(data: blob.content!, encoding: .utf8)
            XCTAssertEqual(data, docID)
        }
        
        // Clean up:
        try nudb.close()
        try Database.delete(dbName, inDirectory: dir)
    }
}
