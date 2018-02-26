//
//  DatabaseTest.swift
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


class DatabaseTest: CBLTestCase {
    
    func testProperties() throws {
        XCTAssertEqual(db.name, self.databaseName)
        XCTAssert(db.path!.contains(self.databaseName))
        XCTAssert(Database.exists(withName: self.databaseName, inDirectory: self.directory))
    }

    func testCreateUntitledDocument() throws {
        let doc = MutableDocument()
        XCTAssertFalse(doc.id.isEmpty)
        XCTAssertFalse(doc.isDeleted)
        XCTAssertTrue(doc.toDictionary() == [:] as [String: Any])
    }
    
    func testCreateNamedDocument() throws {
        XCTAssertNil(db.document(withID: "doc1"))

        let doc = MutableDocument(id: "doc1")
        XCTAssertEqual(doc.id, "doc1")
        XCTAssertFalse(doc.isDeleted)
        XCTAssertTrue(doc.toDictionary() == [:] as [String: Any])
        
        try db.saveDocument(doc)
    }

    func testInBatch() throws {
        try db.inBatch {
            for i in 0...9{
                let doc = MutableDocument(id: "doc\(i)")
                try db.saveDocument(doc)
            }
        }
        for _ in 0...9 {
            XCTAssertNotNil(db.document(withID: "doc1"))
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
        try Database.delete(withName: dbName, inDirectory: dir)
        
        // Copy:
        try Database.copy(fromPath: db.path!, toDatabase: dbName, withConfig: config)
        
        // Verify:
        XCTAssert(Database.exists(withName: dbName, inDirectory: dir))
        let nudb = try Database.init(name: dbName, config: config)
        XCTAssertEqual(nudb.count, 10)
        
        let query = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.database(self.db))
        let rs = try query.execute()
        for r in rs {
            let docID = r.string(at: 0)!
            let doc = nudb.document(withID: docID)!
            XCTAssertEqual(doc.string(forKey: "name"), docID)
            
            let blob = doc.blob(forKey: "data")!
            let data = String.init(data: blob.content!, encoding: .utf8)
            XCTAssertEqual(data, docID)
        }
        
        // Clean up:
        try nudb.close()
        try Database.delete(withName: dbName, inDirectory: dir)
    }
    
    func testCreateIndex() throws {
        // Precheck:
        XCTAssertEqual(db.indexes.count, 0)
        
        // Create value index:
        let fNameItem = ValueIndexItem.expression(Expression.property("firstName"))
        let lNameItem = ValueIndexItem.expression(Expression.property("lastName"))
        
        let index1 = IndexBuilder.valueIndex(items: fNameItem, lNameItem)
        try db.createIndex(index1, withName: "index1")
        
        let index2 = IndexBuilder.valueIndex(items: [fNameItem, lNameItem])
        try db.createIndex(index2, withName: "index2")
        
        // Create FTS index:
        let detailItem = FullTextIndexItem.property("detail")
        let index3 = IndexBuilder.fullTextIndex(items: detailItem)
        try db.createIndex(index3, withName: "index3")
        
        let detailItem2 = FullTextIndexItem.property("es-detail")
        let index4 = IndexBuilder.fullTextIndex(items: detailItem2).language("es").ignoreAccents(true)
        try db.createIndex(index4, withName: "index4")
        
        let nameItem = FullTextIndexItem.property("name")
        let index5 = IndexBuilder.fullTextIndex(items: [nameItem, detailItem])
        try db.createIndex(index5, withName: "index5")
        
        XCTAssertEqual(db.indexes.count, 5)
        XCTAssertEqual(db.indexes, ["index1", "index2", "index3", "index4", "index5"])
    }
    
    func testCreateSameIndexTwice() throws {
        let item = ValueIndexItem.expression(Expression.property("firstName"))
        
        // Create index with first name:
        let index = IndexBuilder.valueIndex(items: item)
        try db.createIndex(index, withName: "myindex")
        
        // Call create index again:
        try db.createIndex(index, withName: "myindex")
        
        XCTAssertEqual(db.indexes.count, 1)
        XCTAssertEqual(db.indexes, ["myindex"])
    }
    
    func failingTestCreateSameNameIndexes() throws {
        // Create value index with first name:
        let fNameItem = ValueIndexItem.expression(Expression.property("firstName"))
        let fNameIndex = IndexBuilder.valueIndex(items: fNameItem)
        try db.createIndex(fNameIndex, withName: "myindex")
        
        // Create value index with last name:
        let lNameItem = ValueIndexItem.expression(Expression.property("lastName"))
        let lNameIndex = IndexBuilder.valueIndex(items: lNameItem)
        try db.createIndex(lNameIndex, withName: "myindex")
        
        // Check:
        XCTAssertEqual(db.indexes.count, 1)
        XCTAssertEqual(db.indexes, ["myindex"])
        
        // Create FTS index:
        let detailItem = FullTextIndexItem.property("detail")
        let detailIndex = IndexBuilder.fullTextIndex(items: detailItem)
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
        
        let index1 = IndexBuilder.valueIndex(items: fNameItem, lNameItem)
        try db.createIndex(index1, withName: "index1")
        
        // Create FTS index:
        let detailItem = FullTextIndexItem.property("detail")
        let index2 = IndexBuilder.fullTextIndex(items: detailItem)
        try db.createIndex(index2, withName: "index2")
        
        let detailItem2 = FullTextIndexItem.property("es-detail")
        let index3 = IndexBuilder.fullTextIndex(items: detailItem2).language("es").ignoreAccents(true)
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
