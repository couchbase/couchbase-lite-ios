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
        XCTAssertEqual(db.name, self.databaseName)
        XCTAssert(db.path!.contains(self.databaseName))
        XCTAssert(Database.exists(self.databaseName, inDirectory: self.directory))
    }

    func testCreateUntitledDocument() throws {
        let doc = MutableDocument()
        XCTAssertFalse(doc.id.isEmpty)
        XCTAssertFalse(doc.isDeleted)
        XCTAssertTrue(doc.toDictionary() == [:] as [String: Any])
    }
    
    func testCreateNamedDocument() throws {
        XCTAssertFalse(db.contains("doc1"))

        let doc = MutableDocument("doc1")
        XCTAssertEqual(doc.id, "doc1")
        XCTAssertFalse(doc.isDeleted)
        XCTAssertTrue(doc.toDictionary() == [:] as [String: Any])
        
        try db.save(doc)
    }

    func testInBatch() throws {
        try db.inBatch {
            for i in 0...9{
                let doc = MutableDocument("doc\(i)")
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
    
    func testCreateIndex() throws {
        // Precheck:
        XCTAssertEqual(db.indexes.count, 0)
        
        // Create value index:
        let fNameItem = ValueIndexItem.expression(Expression.property("firstName"))
        let lNameItem = ValueIndexItem.expression(Expression.property("lastName"))
        
        let index1 = Index.valueIndex().on(fNameItem, lNameItem)
        try db.createIndex(index1, withName: "index1")
        
        // Create FTS index:
        let detailItem = FTSIndexItem.expression(Expression.property("detail"))
        let index2 = Index.ftsIndex().on(detailItem)
        try db.createIndex(index2, withName: "index2")
        
        let detailItem2 = FTSIndexItem.expression(Expression.property("es-detail"))
        let index3 = Index.ftsIndex().on(detailItem2).locale("es").ignoreAccents(true)
        try db.createIndex(index3, withName: "index3")
        
        XCTAssertEqual(db.indexes.count, 3)
        XCTAssertEqual(db.indexes, ["index1", "index2", "index3"])
    }
    
    func testCreateSameIndexTwice() throws {
        let item = ValueIndexItem.expression(Expression.property("firstName"))
        
        // Create index with first name:
        let index = Index.valueIndex().on(item)
        try db.createIndex(index, withName: "myindex")
        
        // Call create index again:
        try db.createIndex(index, withName: "myindex")
        
        XCTAssertEqual(db.indexes.count, 1)
        XCTAssertEqual(db.indexes, ["myindex"])
    }
    
    func failingTestCreateSameNameIndexes() throws {
        // Create value index with first name:
        let fNameItem = ValueIndexItem.expression(Expression.property("firstName"))
        let fNameIndex = Index.valueIndex().on(fNameItem)
        try db.createIndex(fNameIndex, withName: "myindex")
        
        // Create value index with last name:
        let lNameItem = ValueIndexItem.expression(Expression.property("lastName"))
        let lNameIndex = Index.valueIndex().on(lNameItem)
        try db.createIndex(lNameIndex, withName: "myindex")
        
        // Check:
        XCTAssertEqual(db.indexes.count, 1)
        XCTAssertEqual(db.indexes, ["myindex"])
        
        // Create FTS index:
        let detailItem = FTSIndexItem.expression(Expression.property("detail"))
        let detailIndex = Index.ftsIndex().on(detailItem)
        try db.createIndex(detailIndex, withName: "myindex")
        
        // Check:
        XCTAssertEqual(db.indexes.count, 1)
        XCTAssertEqual(db.indexes, ["myindex"])
    }
    
    func testDeleteIndex() throws {
        // Precheck:
        XCTAssertEqual(db.indexes.count, 0)
        
        // Create value index:
        let fNameItem = ValueIndexItem.expression(Expression.property("firstName"))
        let lNameItem = ValueIndexItem.expression(Expression.property("lastName"))
        
        let index1 = Index.valueIndex().on(fNameItem, lNameItem)
        try db.createIndex(index1, withName: "index1")
        
        // Create FTS index:
        let detailItem = FTSIndexItem.expression(Expression.property("detail"))
        let index2 = Index.ftsIndex().on(detailItem)
        try db.createIndex(index2, withName: "index2")
        
        let detailItem2 = FTSIndexItem.expression(Expression.property("es-detail"))
        let index3 = Index.ftsIndex().on(detailItem2).locale("es").ignoreAccents(true)
        try db.createIndex(index3, withName: "index3")
        
        XCTAssertEqual(db.indexes.count, 3)
        XCTAssertEqual(db.indexes, ["index1", "index2", "index3"])
        
        // Delete indexes:
        try db.deleteIndex(forName: "index1")
        XCTAssertEqual(db.indexes.count, 2)
        XCTAssertEqual(db.indexes, ["index2", "index3"])
        
        try db.deleteIndex(forName: "index2")
        XCTAssertEqual(db.indexes.count, 1)
        XCTAssertEqual(db.indexes, ["index3"])
        
        try db.deleteIndex(forName: "index3")
        XCTAssertEqual(db.indexes.count, 0)
        
        // Delete non existing index:
        try db.deleteIndex(forName: "dummy")
        
        // Delete deleted indexes:
        try db.deleteIndex(forName: "index1")
        try db.deleteIndex(forName: "index2")
        try db.deleteIndex(forName: "index3")
    }
}
