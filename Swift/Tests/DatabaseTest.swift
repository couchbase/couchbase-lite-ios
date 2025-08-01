//
//  DatabaseTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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
@testable import CouchbaseLiteSwift

class DatabaseTest: CBLTestCase {

    func verifyDocument(withID id: String, data: Dictionary<String, Any>) throws {
        let doc = try defaultCollection!.document(id: id )
        XCTAssertNotNil(doc)
        XCTAssertEqual(doc!.id, id)
        XCTAssertTrue(doc!.toDictionary() == data)
    }
    
    @discardableResult func createDocs(_ n: Int) throws -> Array<MutableDocument> {
        var docs: Array<MutableDocument> = [];
        for i in 0..<n {
            let docID = String(format: "doc_%03d", i)
            let doc = createDocument(docID)
            doc.setValue(i, forKey: "key")
            try saveDocument(doc)
            docs.append(doc)
        }
        return docs;
    }
    
    func validateDocs(_ n: Int) throws {
        for i in 0..<n {
            let docID = String(format: "doc_%03d", i)
            try verifyDocument(withID: docID, data: ["key": i])
        }
    }
    
    func saveDocument(_ document: MutableDocument,
                      concurrencyControl: ConcurrencyControl?) throws -> Bool
    {
        
        var success = true
        if let cc = concurrencyControl {
            success = try defaultCollection!.save(document: document, concurrencyControl: cc)
            if cc == .failOnConflict {
                XCTAssertFalse(success)
            } else {
                XCTAssertTrue(success)
            }
        } else {
            try defaultCollection!.save(document: document)
        }
        return success
    }
    
    func deleteDocument(_ document: MutableDocument,
                        concurrencyControl: ConcurrencyControl?) throws -> Bool
    {
        var success = true
        if let cc = concurrencyControl {
            success = try defaultCollection!.delete(document: document, concurrencyControl: cc)
            if cc == .failOnConflict {
                XCTAssertFalse(success)
            } else {
                XCTAssertTrue(success)
            }
        } else {
            try defaultCollection!.delete(document: document)
        }
        return success
    }
    
    func testProperties() throws {
        XCTAssertEqual(db.name, self.databaseName)
        XCTAssert(db.path!.contains(self.databaseName))
        XCTAssert(Database.exists(withName: self.databaseName, inDirectory: self.directory))
    }

    func testCreateUntitledDocument() throws {
        let doc = MutableDocument()
        XCTAssertFalse(doc.id.isEmpty)
        XCTAssertTrue(doc.toDictionary() == [:] as [String: Any])
    }
    
    func testCreateNamedDocument() throws {
        XCTAssertNil(try defaultCollection!.document(id: "doc1"))

        let doc = MutableDocument(id: "doc1")
        XCTAssertEqual(doc.id, "doc1")
        XCTAssertTrue(doc.toDictionary() == [:] as [String: Any])
        
        try defaultCollection!.save(document: doc)
    }
    
    
    func testPerformMaintenanceCompact() throws {
        // Create docs:
        let docs = try createDocs(20)
        
        // Update each doc 25 times:
        try db.inBatch {
            for doc in docs {
                for i in 0...25{
                    let mdoc = doc.toMutable()
                    mdoc.setValue(i, forKey: "number")
                    try defaultCollection!.save(document:mdoc)
                }
            }
        }
        
        // Add each doc with a blob object:
        for doc in docs {
            let mdoc = try defaultCollection!.document(id: doc.id)!.toMutable()
            let data = doc.id.data(using: .utf8)
            let blob = Blob.init(contentType: "text/plain", data: data!)
            mdoc.setValue(blob, forKey: "blob")
            try defaultCollection!.save(document:mdoc)
        }
        
        XCTAssertEqual(defaultCollection!.count, 20)
        
        let attachmentDir = (db.path! as NSString).appendingPathComponent("Attachments")
        var attachments = try FileManager.default.contentsOfDirectory(atPath: attachmentDir)
        XCTAssertEqual(attachments.count, 20)
        
        // Compact:
        try db.performMaintenance(type: .compact)
        
        // Delete all docs:
        for doc in docs {
            let doc = try defaultCollection!.document(id: doc.id)!
            try defaultCollection!.delete(document: doc)
            XCTAssertNil(try defaultCollection!.document(id: doc.id))
        }
        XCTAssertEqual(defaultCollection!.count, 0)
        
        attachments = try FileManager.default.contentsOfDirectory(atPath: attachmentDir)
        XCTAssertEqual(attachments.count, 20)
        
        // Compact:
        try db.performMaintenance(type: .compact)
        
        attachments = try FileManager.default.contentsOfDirectory(atPath: attachmentDir)
        XCTAssertEqual(attachments.count, 0)
    }
    
    func testPerformMaintenanceReindex() throws {
        // Create docs:
        try createDocs(20)
        
        // Reindex with no index:
        try db.performMaintenance(type: .reindex)
        
        // Create an index:
        let key = Expression.property("key")
        let keyItem = ValueIndexItem.expression(key)
        let keyIndex = IndexBuilder.valueIndex(items: keyItem)
        try defaultCollection!.createIndex(keyIndex, name: "KeyIndex")
        XCTAssertEqual(try defaultCollection!.indexes().count, 1)
        
        // Check if the index is used:
        let q = QueryBuilder
            .select(SelectResult.expression(key))
            .from(DataSource.collection(defaultCollection!))
            .where(key.greaterThan(Expression.int(9)))
        
        XCTAssert(try isUsingIndex(named: "KeyIndex", for: q))
        
        // Reindex:
        try db.performMaintenance(type: .reindex)
        
        // Check if the index is still there and used:
        XCTAssertEqual(try defaultCollection!.indexes().count, 1)
        XCTAssert(try isUsingIndex(named: "KeyIndex", for: q))
    }
    
    func testPerformMaintenanceIntegrityCheck() throws {
        // Create docs:
        let docs = try createDocs(20)
        
        // Update each doc 25 times:
        try db.inBatch {
            for doc in docs {
                for i in 0...25{
                    let mdoc = doc.toMutable()
                    mdoc.setValue(i, forKey: "number")
                    try defaultCollection!.save(document: mdoc)
                }
            }
        }
        
        // Add each doc with a blob object:
        for doc in docs {
            let mdoc = try defaultCollection!.document(id: doc.id)!.toMutable()
            let data = doc.id.data(using: .utf8)
            let blob = Blob.init(contentType: "text/plain", data: data!)
            mdoc.setValue(blob, forKey: "blob")
            try defaultCollection!.save(document: mdoc)
        }
        
        XCTAssertEqual(defaultCollection!.count, 20)
        
        // Integrity Check:
        try db.performMaintenance(type: .integrityCheck)
        
        // Delete all docs:
        for doc in docs {
            let doc = try defaultCollection!.document(id: doc.id)!
            try defaultCollection!.delete(document: doc)
            XCTAssertNil(try defaultCollection!.document(id: doc.id))
        }
        XCTAssertEqual(defaultCollection!.count, 0)
        
        // Integrity Check:
        try db.performMaintenance(type: .integrityCheck)
    }

    func testInBatch() throws {
        try db.inBatch {
            for i in 0...9{
                let doc = MutableDocument(id: "doc\(i)")
                try defaultCollection!.save(document: doc)
            }
        }
        for _ in 0...9 {
            XCTAssertNotNil(try defaultCollection!.document(id: "doc1"))
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
        let nudb_defaultCol = try nudb.defaultCollection()
        XCTAssertEqual(nudb_defaultCol.count, 10)
        
        let query = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(nudb_defaultCol))
        let rs = try query.execute()
        for r in rs {
            let docID = r.string(at: 0)!
            let doc = try nudb_defaultCol.document(id: docID)!
            XCTAssertEqual(doc.string(forKey: "name"), docID)
            
            let blob = doc.blob(forKey: "data")!
            let data = String.init(data: blob.content!, encoding: .utf8)
            XCTAssertEqual(data, docID)
        }
        
        // Clean up:
        try nudb.close()
        try Database.delete(withName: dbName, inDirectory: dir)
    }
    
    // MARK: Save Document
    
    func testSaveDocWithID() throws {
        let doc = try generateDocument(withID: "doc1")
        XCTAssertEqual(defaultCollection!.count, 1)
        try verifyDocument(withID: doc.id, data: doc.toDictionary())
    }
    
    func testSaveDocWithSpecialCharactersDocID() throws {
        let docID = "`~@#$%^&*()_+{}|\\][=-/.,<>?\":;'"
        let doc = try generateDocument(withID: docID)
        XCTAssertEqual(defaultCollection!.count, 1)
        try verifyDocument(withID: doc.id, data: doc.toDictionary())
    }
    
    func testSaveDocWIthAutoGeneratedID() throws {
        let doc = try generateDocument(withID: nil)
        XCTAssertEqual(defaultCollection!.count, 1)
        try verifyDocument(withID: doc.id, data: doc.toDictionary())
    }
    
    func testSaveDocInDifferenceDBInstance() throws {
        let doc = try generateDocument(withID: "doc1")
        
        let otherDB = try self.openDB(name: db.name)
        XCTAssertNotNil(otherDB)
        XCTAssertEqual(try otherDB.defaultCollection().count, 1)
        
        doc.setValue(2, forKey: "key")
        expectError(domain: CBLError.domain, code: CBLError.invalidParameter) {
            try otherDB.defaultCollection().save(document: doc)
        } // forbidden
        
        try otherDB.close()
    }
    
    func testSaveDocInDifferenceDB() throws {
        let doc = try generateDocument(withID: "doc1")
        
        let otherDB = try self.openDB(name: "otherDB")
        XCTAssertNotNil(otherDB)
        XCTAssertEqual(try otherDB.defaultCollection().count, 0)
        
        doc.setValue(2, forKey: "key")
        expectError(domain: CBLError.domain, code: CBLError.invalidParameter) {
            try otherDB.defaultCollection().save(document: doc)
        } // forbidden
        
        try otherDB.close()
    }
    
    func testSaveSameDocTwice() throws {
        let doc = try generateDocument(withID: "doc1")
        try saveDocument(doc)
        
        let doc1 = try defaultCollection!.document(id: doc.id)!
        XCTAssertEqual(doc1.sequence, 2)
        XCTAssertEqual(defaultCollection!.count, 1)
    }
    
    func testSaveInBatch() throws {
        try db.inBatch {
            try createDocs(10)
        }
        XCTAssertEqual(defaultCollection!.count, 10)
        try validateDocs(10)
    }
    
    func testSaveWithErrorInBatch() throws {
        do {
            try self.db.inBatch {
                try self.createDocs(10)
                XCTAssertEqual(defaultCollection!.count, 10)
                throw NSError(domain: "someDomain", code: 500, userInfo: nil)
            }
        } catch {
            XCTAssertNotNil(error);
            XCTAssertEqual((error as NSError).code, CBLError.unexpectedError);
        }
        XCTAssertEqual(defaultCollection!.count, 0)
    }
    
    func testSaveManyDocs() throws {
        try createDocs(1000)
        XCTAssertEqual(defaultCollection!.count, 1000)
        try validateDocs(1000)
        
        // Cleanup:
        try db.delete()
        try reopenDB()
        
        try db.inBatch {
            try createDocs(1000)
        }
        XCTAssertEqual(defaultCollection!.count, 1000)
        try validateDocs(1000)
    }
    
    func testAndUpdateMutableDoc() throws {
        let doc = createDocument("doc1")
        doc.setString("Daniel", forKey: "firstName")
        try defaultCollection!.save(document: doc)
        
        // Update
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        // Update
        doc.setInt(20, forKey: "age")
        try defaultCollection!.save(document: doc)
        
        let expectedResult: [String : Any] =
            ["firstName": "Daniel", "lastName": "Tiger", "age": 20]
        XCTAssertTrue(doc.toDictionary() == expectedResult)
        XCTAssertEqual(doc.sequence, 3)
        
        let savedDoc = try defaultCollection!.document(id: doc.id)!
        XCTAssertTrue(savedDoc.toDictionary() == expectedResult)
        XCTAssertEqual(savedDoc.sequence, 3)
    }
    
    func testSaveDocWithConflict() throws {
        try testSaveDocWithConflict(usingConcurrencyControl: nil)
        try testSaveDocWithConflict(usingConcurrencyControl: .lastWriteWins)
        try testSaveDocWithConflict(usingConcurrencyControl: .failOnConflict)
    }
    
    func testSaveDocWithConflict(usingConcurrencyControl cc: ConcurrencyControl?) throws
    {
        let doc = createDocument("doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        // Get two doc1 document objects (doc1a and doc1b):
        let doc1a = try defaultCollection!.document(id: doc.id)!.toMutable()
        let doc1b = try defaultCollection!.document(id: doc.id)!.toMutable()
        
        // Modify doc1a:
        doc1a.setString("Scott", forKey: "firstName")
        try defaultCollection!.save(document: doc1a)
        doc1a.setString("Scotty", forKey: "nickName")
        try defaultCollection!.save(document: doc1a)
        XCTAssertTrue(doc1a.toDictionary() ==
            ["firstName": "Scott", "lastName": "Tiger", "nickName": "Scotty"])
        XCTAssertEqual(doc1a.sequence, 3)
        
        // Modify doc1b:
        doc1b.setString("Lion", forKey: "lastName")
        if try saveDocument(doc1b, concurrencyControl: cc) {
            let savedDoc = try defaultCollection!.document(id: doc1b.id)!
            XCTAssertTrue(savedDoc.toDictionary() == doc1b.toDictionary())
            XCTAssertEqual(savedDoc.sequence, 4)
        }
        
        // Cleanup:
        try cleanDB()
    }
    
    func testSaveDocWithNoParentConflict() throws {
        try testSaveDocWithNoParentConflict(usingConcurrencyControl: nil)
        try testSaveDocWithNoParentConflict(usingConcurrencyControl: .lastWriteWins)
        try testSaveDocWithNoParentConflict(usingConcurrencyControl: .failOnConflict)
    }
    
    func testSaveDocWithNoParentConflict(usingConcurrencyControl cc: ConcurrencyControl?) throws
    {
        let doc1a = createDocument("doc1")
        doc1a.setString("Daniel", forKey: "firstName")
        doc1a.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc1a)
        XCTAssertEqual(doc1a.sequence, 1)
        let savedDoc = try defaultCollection!.document(id: "doc1")!
        XCTAssertEqual(savedDoc.sequence, 1)
        
        let doc1b = createDocument(doc1a.id)
        doc1b.setString("Scott", forKey: "firstName")
        doc1b.setString("Tiger", forKey: "lastName")
        if try saveDocument(doc1b, concurrencyControl: cc) {
            let savedDoc = try defaultCollection!.document(id: doc1b.id)!
            XCTAssertTrue(savedDoc.toDictionary() == doc1b.toDictionary())
            XCTAssertEqual(savedDoc.sequence, 2)
        }
        
        // Cleanup:
        try cleanDB()
    }
    
    func testSaveDocWithDeletedConflict() throws {
        try testSaveDocWithDeletedConflict(usingConcurrencyControl: nil)
        try testSaveDocWithDeletedConflict(usingConcurrencyControl: .lastWriteWins)
        try testSaveDocWithDeletedConflict(usingConcurrencyControl: .failOnConflict)
    }
    
    func testSaveDocWithDeletedConflict(usingConcurrencyControl cc: ConcurrencyControl?) throws
    {
        let doc = createDocument("doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        // Get two doc1 document objects (doc1a and doc1b):
        let doc1a = try defaultCollection!.document(id: doc.id)!
        let doc1b = try defaultCollection!.document(id: doc.id)!.toMutable()
        
        // Delete doc1a
        try defaultCollection!.delete(document: doc1a)
        XCTAssertEqual(doc1a.sequence, 2)
        XCTAssertNil(try defaultCollection!.document(id: doc1a.id))
        
        // Modify doc1b:
        doc1b.setString("Lion", forKey: "lastName")
        if try saveDocument(doc1b, concurrencyControl: cc) {
            let savedDoc = try defaultCollection!.document(id: doc1b.id)!
            XCTAssertTrue(savedDoc.toDictionary() == doc1b.toDictionary())
            XCTAssertEqual(savedDoc.sequence, 3)
        }
        
        // Cleanup:
        try cleanDB()
    }
    
    // MARK: Save Conflict Resolution Handler
    
    func testConflictResolution() throws {
        let doc = createDocument("doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        // Get two doc1 document objects (doc1a and doc1b):
        let doc1a = try defaultCollection!.document(id: doc.id)!.toMutable()
        let doc1b = try defaultCollection!.document(id: doc.id)!.toMutable()
        
        // Modify doc1a:
        doc1a.setString("Scott", forKey: "firstName")
        doc1a.setString("Scotty", forKey: "nickName")
        try defaultCollection!.save(document: doc1a)
        XCTAssertTrue(doc1a.toDictionary() == ["firstName": "Scott",
                                               "lastName": "Tiger",
                                               "nickName": "Scotty"])
        XCTAssertEqual(doc1a.sequence, 2)
        
        // Modify doc1b:
        doc1b.setString("Lion", forKey: "middleName")
        
        // merge the dictionaries, and keeping the doc1b dictionary values if duplicate comes in.
        XCTAssertTrue(try defaultCollection!.save(document: doc1b) { (doc, old) -> Bool in
            let merged = doc.toDictionary()
                .merging(old!.toDictionary(), uniquingKeysWith: { (first, _) in first })
            doc.setData(merged)
            return true
        })
        let savedDoc = try defaultCollection!.document(id: doc1b.id)!
        XCTAssertTrue(savedDoc.toDictionary() == ["firstName": "Daniel", // kept previous key value
                                                  "nickName": "Scotty", // merged
                                                  "lastName": "Tiger",  // NA
                                                  "middleName": "Lion"]) // conflicting update
    }
    
    func testCancelConflictHandler() throws {
        let doc = createDocument("doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        // create conflict and return false
        var doc1a = try defaultCollection!.document(id: doc.id)!.toMutable()
        var doc1b = try defaultCollection!.document(id: doc.id)!.toMutable()
        doc1a.setString("Scott", forKey: "firstName")
        try defaultCollection!.save(document: doc1a)
        doc1b.setString("Lion", forKey: "middleName")
        XCTAssertFalse(try defaultCollection!.save(document: doc1b) { (doc, old) -> Bool in
            XCTAssert(doc1b == doc)
            XCTAssertEqual(doc1a, old)
            return false
            })
        
        // check it is same as old doc, and didn't updated the doc
        XCTAssertEqual(try defaultCollection!.document(id: doc1b.id)!, doc1a)
        
        // Updates to Current Mutable Document, should not save contents.
        // create conflict, update the mutable doc, and return false
        doc1a = try defaultCollection!.document(id: doc.id)!.toMutable()
        doc1b = try defaultCollection!.document(id: doc.id)!.toMutable()
        doc1a.setString("Sccotty", forKey: "nickname")
        try defaultCollection!.save(document: doc1a)
        doc1b.setString("Scotty", forKey: "nickname")
        XCTAssertFalse(try defaultCollection!.save(document: doc1b) { (doc, old) -> Bool in
            XCTAssert(doc1b == doc)
            XCTAssertEqual(doc1a, old)
            doc.setString("Scott", forKey: "nickname")
            return false
            })
        // check whether it is same old doc, and no update happened.
        XCTAssertEqual(try defaultCollection!.document(id: doc1b.id)!, doc1a)
    }
    
    func testConflictHandlerWhenDocumentIsPurged() throws {
        let doc = createDocument("doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        // Purge one instance
        let doc1a = try defaultCollection!.document(id: doc.id)!.toMutable()
        try defaultCollection!.purge(document: try defaultCollection!.document(id: doc.id)!)
        
        doc1a.setString("Scotty", forKey: "nickName")
        ignoreException {
            do {
                _ = try self.defaultCollection!.save(document: doc1a) { (doc, old) -> Bool in
                    return true
                }
                XCTFail("Shouldn't reach here, it should throw an exception when saving")
            } catch {
                XCTAssertNotNil(error)
                XCTAssertEqual((error as NSError?)?.code, CBLError.notFound)
            }
        }
    }
    
    func testConflictHandlerWithDeletedOldDoc() throws {
        let doc = createDocument("doc1")
        try defaultCollection!.save(document: doc)
        
        // KEEPS NEW DOC(non-deleted)
        var doc1a = try defaultCollection!.document(id: doc.id)!.toMutable()
        XCTAssertTrue(try defaultCollection!.delete(document: try defaultCollection!.document(id: doc.id)!, concurrencyControl: .failOnConflict))
        
        doc1a.setString("Lion", forKey: "middleName")
        XCTAssertTrue(try defaultCollection!.save(document: doc1a) { (doc, old) -> Bool in
            XCTAssertNil(old)
            XCTAssertNotNil(doc)
            XCTAssert(doc == doc1a)
            return true
        })
        XCTAssert(try defaultCollection!.document(id: doc.id) == doc1a)
        
        // KEEPS THE DELETED(old doc)
        doc1a = try defaultCollection!.document(id: doc.id)!.toMutable()
        XCTAssertTrue(try defaultCollection!.delete(document: try defaultCollection!.document(id: doc.id)!, concurrencyControl: .failOnConflict))
        
        doc1a.setString("Lion", forKey: "nickName")
        XCTAssertFalse(try defaultCollection!.save(document: doc1a) { (doc, old) -> Bool in
            XCTAssertNil(old)
            XCTAssertNotNil(doc)
            XCTAssert(doc == doc1a)
            return false
        })
        XCTAssertNil(try defaultCollection!.document(id: doc.id))
    }
    
    func testConflictHandlerCalledTwice() throws {
        let doc = createDocument("doc1")
        try defaultCollection!.save(document: doc)
        
        let doc1a = try defaultCollection!.document(id: doc.id)!.toMutable()
        let doc1b = try defaultCollection!.document(id: doc.id)!.toMutable()
        doc1a.setString("Scott", forKey: "firstName")
        try defaultCollection!.save(document: doc1a)
        
        doc1b.setString("Lion", forKey: "middleName")
        var count = 0
        _ = try defaultCollection!.save(document: doc1b) { (doc, old) -> Bool in
            count += 1
            let doc1c = try! self.defaultCollection!.document(id: doc.id)!.toMutable()
            if !doc1c.boolean(forKey: "secondUpdate") {
                doc1c.setBoolean(true, forKey: "secondUpdate")
                try! self.defaultCollection!.save(document: doc1c)
            }
            
            // merge contents
            var dict = old!.toDictionary()
            for (key, value) in doc.toDictionary() {
                dict[key] = value
            }
            doc.setData(dict)
            doc.setString("local", forKey: "edit")
            return true
        }
        
        XCTAssertEqual(count, 2) // make sure the save handler called twice
        XCTAssertEqual(defaultCollection!.count, 1)
        let dict: [String: Any] = ["middleName": "Lion", // old doc contents - merged
            "firstName": "Scott", // savedDoc contents
            "secondUpdate": true, // second update did.
            "edit": "local"] // new prop added during resolve.
        XCTAssert(try defaultCollection!.document(id: doc1b.id)!.toDictionary() == dict)
    }
    
    /// disabling since, exceptions inside conflict handler will leak, since objc doesn't perform release
    /// when exception happens
    func _testConflictHandlerThrowingException() throws {
        let doc = createDocument("doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        let doc1a = try defaultCollection!.document(id: doc.id)!.toMutable()
        let doc1b = try defaultCollection!.document(id: doc.id)!.toMutable()
        doc1a.setString("Scott", forKey: "firstName")
        try defaultCollection!.save(document: doc1a)
        
        // conflicting save
        doc1b.setString("Lion", forKey: "middleName")
        ignoreException {
            XCTAssertFalse(try self.defaultCollection!.save(document: doc1b) { (cur, old) -> Bool in
                NSException(name: .internalInconsistencyException,
                            reason: "some exception happened inside save handler",
                            userInfo: nil).raise()
                return true
                })
        }
    }
    
    // MARK: Delete Document
    
    func testDeletePreSaveDoc() throws {
        let doc = MutableDocument(id: "doc1")
        doc.setValue(1, forKey: "key")
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            try self.defaultCollection!.delete(document: doc)
        }
    }
    
    func testDeleteDoc() throws {
        let doc = try generateDocument(withID: "doc1")
        try defaultCollection!.delete(document: doc)
        XCTAssertEqual(defaultCollection!.count, 0)
        XCTAssertNil(try defaultCollection!.document(id: doc.id))
    }
    
    func testDeleteSameDocTwice() throws {
        let doc = try generateDocument(withID: "doc1")
        
        // First time deletion:
        try defaultCollection!.delete(document: doc)
        XCTAssertEqual(defaultCollection!.count, 0)
        XCTAssertNil(try defaultCollection!.document(id: doc.id))
        XCTAssertEqual(doc.sequence, 2)
        
        // Second time deletion:
        try defaultCollection!.delete(document: doc)
        XCTAssertEqual(defaultCollection!.count, 0)
        XCTAssertNil(try defaultCollection!.document(id: doc.id))
        XCTAssertEqual(doc.sequence, 3)
    }
    
    func testDeleteNoneExistingDoc() throws {
        let doc1a = try generateDocument(withID: "doc1")
        let doc1b = try defaultCollection!.document(id: doc1a.id)!
        
        // Purge doc:
        try defaultCollection!.purge(document: doc1a)
        XCTAssertEqual(defaultCollection!.count, 0)
        XCTAssertNil(try defaultCollection!.document(id: doc1a.id))
        
        // Delete doc1a, 404 error:
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            try self.defaultCollection!.delete(document: doc1a)
        }
        
        // Delete doc, 404 error:
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            try self.defaultCollection!.delete(document: doc1b)
        }
        
        XCTAssertEqual(defaultCollection!.count, 0)
        XCTAssertNil(try defaultCollection!.document(id: doc1b.id))
    }
    
    func testDeleteDocInBatch() throws {
        // Save 10 docs:
        let docs = try createDocs(10)
        try db.inBatch {
            for i in 0...9 {
                let doc = try defaultCollection!.document(id: docs[i].id)!
                try defaultCollection!.delete(document: doc)
                XCTAssertEqual(defaultCollection!.count, UInt64(9 - i))
            }
        }
        XCTAssertEqual(defaultCollection!.count, 0)
    }
    
    func testDeleteWithErrorInBatch() throws {
        let docs = try createDocs(10)
        do {
            try self.db.inBatch {
                for i in 0...9 {
                    let doc = try defaultCollection!.document(id: docs[i].id)!
                    try defaultCollection!.delete(document: doc)
                    XCTAssertEqual(defaultCollection!.count, UInt64(9 - i))
                }
                throw NSError(domain: "someDomain", code: 500, userInfo: nil)
            }
        } catch {
            XCTAssertNotNil(error);
            XCTAssertEqual((error as NSError).code, CBLError.unexpectedError);
        }
        XCTAssertEqual(defaultCollection!.count, 10)
    }
    
    func testDeleteDocOnDeletedDB() throws {
        let doc = MutableDocument(id: "doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        try defaultCollection!.delete(document: doc)
        XCTAssertEqual(doc.sequence, 2)
        XCTAssertNil(try defaultCollection!.document(id: doc.id))
        
        doc.setString("Scott", forKey: "firstName")
        try defaultCollection!.save(document: doc)
        XCTAssertEqual(doc.sequence, 3)
        XCTAssertTrue(doc.toDictionary() ==
            ["firstName": "Scott", "lastName": "Tiger"])
        
        let savedDoc = try defaultCollection!.document(id: doc.id)!
        XCTAssertTrue(savedDoc.toDictionary() == doc.toDictionary())
    }
    
    func testDeleteAndUpdateDoc() throws {
        let doc = MutableDocument(id: "doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        try defaultCollection!.delete(document: doc)
        XCTAssertEqual(doc.sequence, 2)
        XCTAssertNil(try defaultCollection!.document(id: doc.id))
        
        doc.setString("Scott", forKey: "firstName")
        try defaultCollection!.save(document: doc)
        XCTAssertEqual(doc.sequence, 3)
        XCTAssertTrue(doc.toDictionary() == ["firstName": "Scott", "lastName": "Tiger"])
        
        let savedDoc = try defaultCollection!.document(id: doc.id)!
        XCTAssertTrue(savedDoc.toDictionary() == doc.toDictionary())
    }
    
    func testDeleteAlreadyDeletedDoc() throws {
        let doc = MutableDocument(id: "doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        // Get two doc1 document objects (doc1a and doc1b):
        let doc1a = try defaultCollection!.document(id: doc.id)!
        let doc1b = try defaultCollection!.document(id: doc.id)!.toMutable()
        
        // Delete doc1a:
        try defaultCollection!.delete(document: doc1a)
        XCTAssertEqual(doc1a.sequence, 2)
        XCTAssertNil(try defaultCollection!.document(id: doc.id))
        
        // Delete doc1b:
        try defaultCollection!.delete(document: doc1b)
        XCTAssertEqual(doc1a.sequence, 2)
        XCTAssertNil(try defaultCollection!.document(id: doc.id))
    }
    
    func testDeleteDocWithConflict() throws {
        try testDeleteDocWithConflict(usingConcurrencyControl: nil)
        try testDeleteDocWithConflict(usingConcurrencyControl: .lastWriteWins)
        try testDeleteDocWithConflict(usingConcurrencyControl: .failOnConflict)
    }
    
    func testDeleteDocWithConflict(usingConcurrencyControl cc: ConcurrencyControl?) throws {
        let doc = MutableDocument(id: "doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try defaultCollection!.save(document: doc)
        
        // Get two document objects (doc1a and doc1b):
        let doc1a = try defaultCollection!.document(id: doc.id)!.toMutable()
        let doc1b = try defaultCollection!.document(id: doc.id)!.toMutable()
        
        // Modify doc1a
        doc1a.setString("Scott", forKey: "firstName")
        try defaultCollection!.save(document: doc1a)
        XCTAssertTrue(doc1a.toDictionary() == ["firstName": "Scott", "lastName": "Tiger"])
        XCTAssertEqual(doc1a.sequence, 2)
        
        // Modify doc1b and delete, result to conflict when delete:
        doc1b.setString("Lion", forKey: "lastName")
        if try deleteDocument(doc1b, concurrencyControl: cc) {
            XCTAssertEqual(doc1b.sequence, 3)
            XCTAssertNil(try defaultCollection!.document(id: doc1b.id))
        }
        XCTAssertTrue(doc1b.toDictionary() == ["firstName": "Daniel", "lastName": "Lion"])
        
        // Cleanup
        try cleanDB()
    }
    
    // MARK: Purge Document
    
    func testPurgePreSaveDoc() throws {
        let doc = createDocument("doc1")
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            try self.defaultCollection!.purge(document: doc)
        }
    }
    
    func testPurgeDoc() throws {
        let doc = try generateDocument(withID: "doc1")
        try defaultCollection!.purge(document: doc)
        XCTAssertNil(try defaultCollection!.document(id: "doc1"))
        XCTAssertEqual(defaultCollection!.count, 0)
    }
    
    func testPurgeDocInDifferentDBInstance() throws {
        let doc = try generateDocument(withID: "doc1")
        let otherDB = try openDB(name: db.name)
        XCTAssertNotNil(try otherDB.defaultCollection().document(id: doc.id))
        XCTAssertEqual(try otherDB.defaultCollection().count, 1)
        expectError(domain: CBLError.domain, code: CBLError.invalidParameter) {
            try otherDB.defaultCollection().purge(document: doc)
        }
        try otherDB.close()
    }
    
    func testPurgeDocInDifferentDB() throws {
        let doc = try generateDocument(withID: "doc1")
        let otherDB = try openDB(name: "otherDB")
        expectError(domain: CBLError.domain, code: CBLError.invalidParameter) {
            try otherDB.defaultCollection().purge(document: doc)
        }
        try otherDB.delete()
    }
    
    func testPurgeSameDocTwice() throws {
        let doc = try generateDocument(withID: "doc1")
        try defaultCollection!.purge(document: doc)
        XCTAssertNil(try defaultCollection!.document(id: "doc1"))
        XCTAssertEqual(defaultCollection!.count, 0)
        
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            try self.defaultCollection!.purge(document: doc)
        }
    }
    
    func testPurgeDocInBatch() throws {
        try createDocs(10)
        try db.inBatch {
            for i in 0..<10 {
                let docID = String(format: "doc_%03d", i)
                let doc = try defaultCollection!.document(id: docID)!
                try self.defaultCollection!.purge(document: doc)
                XCTAssertNil(try defaultCollection!.document(id: docID))
                XCTAssertEqual(self.defaultCollection!.count, UInt64(9 - i))
            }
        }
        XCTAssertEqual(defaultCollection!.count, 0)
    }
    
    func testPurgeWithErrorInBatch() throws {
        let docs = try createDocs(10)
        do {
            try self.db.inBatch {
                for i in 0...9 {
                    let doc = try defaultCollection!.document(id: docs[i].id)!
                    try defaultCollection!.purge(document: doc)
                    XCTAssertEqual(defaultCollection!.count, UInt64(9 - i))
                }
                throw NSError(domain: "someDomain", code: 500, userInfo: nil)
            }
        } catch {
            XCTAssertNotNil(error);
            XCTAssertEqual((error as NSError).code, CBLError.unexpectedError);
        }
        XCTAssertEqual(defaultCollection!.count, 10)
    }
    
    func testPurgeDocumentOnADeletedDocument() throws {
        let document = try generateDocument(withID: nil)
        
        // Delete document
        try self.defaultCollection!.delete(document: document)
        
        // Purge doc
        try defaultCollection!.purge(document: document)
        XCTAssertEqual(defaultCollection!.count, 0)
        XCTAssertNil(try defaultCollection!.document(id: document.id))
    }
    
    // MARK: Purge Document With ID
    
    func testPreSavePurgeDocumentWithID() throws {
        let documentID = "\(Date().timeIntervalSince1970)"
        let _ = createDocument(documentID)
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            try self.defaultCollection!.purge(id: documentID)
        }
    }
    
    func testPurgeDocumentWithID() throws {
        let doc = try generateDocument(withID: nil)
        
        try self.defaultCollection!.purge(document: doc)
        
        XCTAssertNil(try defaultCollection!.document(id: doc.id))
        XCTAssertEqual(defaultCollection!.count, 0)
    }
    
    func testPurgeDocumentWithIDInDifferentDBInstance() throws {
        let document = try generateDocument(withID: nil)
        let documentID = document.id
        let otherDB = try openDB(name: db.name)
        XCTAssertNotNil(try otherDB.defaultCollection().document(id: documentID))
        XCTAssertEqual(try otherDB.defaultCollection().count, 1)
        
        // should delete it without any errors
        try otherDB.defaultCollection().purge(id: documentID)
        
        try otherDB.close()
    }
    
    func testPurgeDocumentWithIDInDifferentDB() throws {
        let document = try generateDocument(withID: nil)
        let documentID = document.id
        let otherDB = try openDB(name: "otherDB")
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            try otherDB.defaultCollection().purge(id: documentID)
        }
        try otherDB.delete()
    }
    
    func testCallPurgeDocumentWithIDTwice() throws {
        let document = try generateDocument(withID: nil)
        let documentID = document.id
        try defaultCollection!.purge(id: documentID)
        XCTAssertNil(try defaultCollection!.document(id: documentID))
        XCTAssertEqual(defaultCollection!.count, 0)
        
        expectError(domain: CBLError.domain, code: CBLError.notFound) { [unowned self] in
            try self.defaultCollection!.purge(id: documentID)
        }
    }
    
    func testPurgeDocumentWithIDInBatch() throws {
        let totalDocumentsCount = 10
        try createDocs(totalDocumentsCount)
        try db.inBatch { [unowned self] in
            for i in 0..<totalDocumentsCount {
                let documentID = String(format: "doc_%03d", i)
                try self.defaultCollection!.purge(id: documentID)
                XCTAssertNil(try defaultCollection!.document(id: documentID))
                XCTAssertEqual(self.defaultCollection!.count, UInt64((totalDocumentsCount - 1) - i))
            }
        }
        XCTAssertEqual(defaultCollection!.count, 0)
    }
    
    func testPurgeDocIDWithErrorInBatch() throws {
        let docs = try createDocs(10)
        do {
            try self.db.inBatch {
                for i in 0...9 {
                    try self.defaultCollection!.purge(id: docs[i].id)
                    XCTAssertEqual(defaultCollection!.count, UInt64(9 - i))
                }
                throw NSError(domain: "someDomain", code: 500, userInfo: nil)
            }
        } catch {
            XCTAssertNotNil(error);
            XCTAssertEqual((error as NSError).code, CBLError.unexpectedError);
        }
        XCTAssertEqual(defaultCollection!.count, 10)
    }
    
    func testDeletePurgedDocumentWithID() throws {
        let document = try generateDocument(withID: nil)
        let documentID = document.id
        let anotherDocumentReference = try defaultCollection!.document(id: documentID)!
        
        // Purge doc
        try defaultCollection!.purge(id: documentID)
        XCTAssertEqual(defaultCollection!.count, 0)
        XCTAssertNil(try defaultCollection!.document(id: documentID))
        
        // Delete document & anotherDocumentReference -> 404 NotFound
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            try self.defaultCollection!.delete(document: document)
        }
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            try self.defaultCollection!.delete(document: anotherDocumentReference)
        }
        
        XCTAssertEqual(defaultCollection!.count, 0)
        XCTAssertNil(try defaultCollection!.document(id: documentID))
    }
    
    func testPurgeDocumentWithIDOnADeletedDocument() throws {
        let document = try generateDocument(withID: nil)
        let documentID = document.id
        
        // Delete document
        try self.defaultCollection!.delete(document: document)
        
        // Purge doc
        try defaultCollection!.purge(id: documentID)
        XCTAssertEqual(defaultCollection!.count, 0)
        XCTAssertNil(try defaultCollection!.document(id: documentID))
    }
    
    // MARK: Index
    
    func testCreateIndex() throws {
        // Precheck:
        XCTAssertEqual(try defaultCollection!.indexes().count, 0)

        // Create value index:
        let fNameItem = ValueIndexItem.expression(Expression.property("firstName"))
        let lNameItem = ValueIndexItem.expression(Expression.property("lastName"))

        let index1 = IndexBuilder.valueIndex(items: fNameItem, lNameItem)
        try defaultCollection!.createIndex(index1, name: "index1")

        let index2 = IndexBuilder.valueIndex(items: [fNameItem, lNameItem])
        try defaultCollection!.createIndex(index2, name: "index2")

        // Create FTS index:
        let detailItem = FullTextIndexItem.property("detail")
        let index3 = IndexBuilder.fullTextIndex(items: detailItem)
        try defaultCollection!.createIndex(index3, name: "index3")

        let detailItem2 = FullTextIndexItem.property("es-detail")
        let index4 = IndexBuilder.fullTextIndex(items: detailItem2).language("es").ignoreAccents(true)
        try defaultCollection!.createIndex(index4, name: "index4")

        let nameItem = FullTextIndexItem.property("name")
        let index5 = IndexBuilder.fullTextIndex(items: [nameItem, detailItem])
        try defaultCollection!.createIndex(index5, name: "index5")

        XCTAssertEqual(try defaultCollection!.indexes().count, 5)
        XCTAssertEqual(try defaultCollection!.indexes(), ["index1", "index2", "index3", "index4", "index5"])
    }
    
    func testCreateCollectionIndex() throws {
        let colA = try self.db.createCollection(name: "colA")
        
        // Precheck:
        XCTAssertEqual(try colA.indexes().count, 0)

        // Create value index:
        let fNameItem = ValueIndexItem.expression(Expression.property("firstName"))
        let lNameItem = ValueIndexItem.expression(Expression.property("lastName"))

        let index1 = IndexBuilder.valueIndex(items: fNameItem, lNameItem)
        try colA.createIndex(index1, name: "index1")

        let index2 = IndexBuilder.valueIndex(items: [fNameItem, lNameItem])
        try colA.createIndex(index2, name: "index2")

        // Create FTS index:
        let detailItem = FullTextIndexItem.property("detail")
        let index3 = IndexBuilder.fullTextIndex(items: detailItem)
        try colA.createIndex(index3, name: "index3")

        let detailItem2 = FullTextIndexItem.property("es-detail")
        let index4 = IndexBuilder.fullTextIndex(items: detailItem2).language("es").ignoreAccents(true)
        try colA.createIndex(index4, name: "index4")

        let nameItem = FullTextIndexItem.property("name")
        let index5 = IndexBuilder.fullTextIndex(items: [nameItem, detailItem])
        try colA.createIndex(index5, name: "index5")

        XCTAssertEqual(try colA.indexes().count, 5)
        XCTAssertEqual(try colA.indexes(), ["index1", "index2", "index3", "index4", "index5"])
    }
    
    func testFullTextIndexExpression() throws {
        let colA = try self.db.createCollection(name: "colA")
        
        // Create FTS index:
        let detailItem = FullTextIndexItem.property("passage")
        let index2 = IndexBuilder.fullTextIndex(items: detailItem)
        try colA.createIndex(index2, name: "passageIndex")
        
        var doc = createDocument("doc1")
        doc.setString("The boy said to the child, 'Mommy, I want a cat.'", forKey: "passage")
        try colA.save(document: doc)
        
        doc = createDocument("doc2")
        doc.setString("The mother replied 'No, you already have too many cats.'", forKey: "passage")
        try colA.save(document: doc)
        
        let plainIndex = Expression.fullTextIndex("passageIndex")
        let qualifiedIndex = Expression.fullTextIndex("passageIndex").from("colAa")
        
        var query = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(colA).as("colAa"))
            .where(FullTextFunction.match(plainIndex, query: "cat"))
        
        var rows = try verifyQuery(query, block: { (n, r) in
            XCTAssertEqual(r.string(at: 0), "doc\(n)")
        })
        XCTAssertEqual(rows, 2);
        
        query = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(colA).as("colAa"))
            .where(FullTextFunction.match(qualifiedIndex, query: "cat"))
        
        rows = try verifyQuery(query, block: { (n, r) in
            XCTAssertEqual(r.string(at: 0), "doc\(n)")
        })
        XCTAssertEqual(rows, 2);
    }
    
    func testFTSQueryWithJoin() throws {
        let colA = try self.db.createCollection(name: "colA")
        
        // Create FTS index:
        let detailItem = FullTextIndexItem.property("passage")
        let index2 = IndexBuilder.fullTextIndex(items: detailItem)
        try colA.createIndex(index2, name: "passageIndex")
        
        var doc = createDocument("doc1")
        doc.setString("The boy said to the child, 'Mommy, I want a cat.'", forKey: "passage")
        doc.setString("en", forKey: "lang")
        try colA.save(document: doc)
        
        doc = createDocument("doc2")
        doc.setString("The mother replied 'No, you already have too many cats.'", forKey: "passage")
        doc.setString("en", forKey: "lang")
        try colA.save(document: doc)
        
        let join = Join.leftJoin(DataSource.collection(colA).as("secondary")).on(
            Expression.property("lang").from("main")
                .equalTo(Expression.property("lang").from("secondary")))
        
        let plainIndex = Expression.fullTextIndex("passageIndex")
        var query = QueryBuilder
            .select(SelectResult.expression(Meta.id.from("main")))
            .from(DataSource.collection(colA).as("main"))
            .join(join)
            .where(FullTextFunction.match(plainIndex, query: "cat"))
            .orderBy(Ordering.expression(Meta.id.from("main")).ascending())
        
        var rows = try verifyQuery(query, block: { (n, r) in
            XCTAssert(r.string(at: 0)!.hasPrefix("doc"))
        })
        XCTAssertEqual(rows, 4);
        
        let qualifiedIndex = Expression.fullTextIndex("passageIndex").from("main")
        query = QueryBuilder
            .select(SelectResult.expression(Meta.id.from("main")))
            .from(DataSource.collection(colA).as("main"))
            .join(join)
            .where(FullTextFunction.match(qualifiedIndex, query: "cat"))
            .orderBy(Ordering.expression(Meta.id.from("main")).ascending())
        
        rows = try verifyQuery(query, block: { (n, r) in
            XCTAssert(r.string(at: 0)!.hasPrefix("doc"))
        })
        XCTAssertEqual(rows, 4);
    }
    
    func testN1QLCreateIndexSanity() throws {
        XCTAssertEqual(try defaultCollection!.indexes().count, 0)
        
        let config1 = ValueIndexConfiguration(["firstName", "lastName"])
        try defaultCollection!.createIndex(withName: "index1", config: config1)
        
        let config2 = FullTextIndexConfiguration(["detail"])
        try defaultCollection!.createIndex(withName: "index2", config: config2)
        
        let config3 = FullTextIndexConfiguration(["es_detail"], ignoreAccents: true, language: "es")
        try defaultCollection!.createIndex(withName: "index3", config: config3)
        
        let config4 = FullTextIndexConfiguration(["name"], ignoreAccents: false, language: "en")
        try defaultCollection!.createIndex(withName: "index4", config: config4)
        
        // use backtick in case of property name with hyphen
        let config5 = FullTextIndexConfiguration(["`es-detail`"], ignoreAccents: true, language: "es")
        try defaultCollection!.createIndex(withName: "index5", config: config5)
        
        // same index twice: no-op
        let config6 = FullTextIndexConfiguration(["detail"])
        try defaultCollection!.createIndex(withName: "index2", config: config6)
        
        XCTAssertEqual(try defaultCollection!.indexes().count, 5)
        XCTAssertEqual(try defaultCollection!.indexes(), ["index1", "index2", "index3", "index4", "index5"])
    }
    
    func testCreateSameIndexTwice() throws {
        let item = ValueIndexItem.expression(Expression.property("firstName"))
        
        // Create index with first name:
        let index = IndexBuilder.valueIndex(items: item)
        try defaultCollection!.createIndex(index, name: "myindex")
        
        // Call create index again:
        try defaultCollection!.createIndex(index, name: "myindex")
        
        XCTAssertEqual(try defaultCollection!.indexes().count, 1)
        XCTAssertEqual(try defaultCollection!.indexes(), ["myindex"])
    }
    
    func failingTestCreateSameNameIndexes() throws {
        // Create value index with first name:
        let fNameItem = ValueIndexItem.expression(Expression.property("firstName"))
        let fNameIndex = IndexBuilder.valueIndex(items: fNameItem)
        try defaultCollection!.createIndex(fNameIndex, name: "myindex")
        
        // Create value index with last name:
        let lNameItem = ValueIndexItem.expression(Expression.property("lastName"))
        let lNameIndex = IndexBuilder.valueIndex(items: lNameItem)
        try defaultCollection!.createIndex(lNameIndex, name: "myindex")
        
        // Check:
        XCTAssertEqual(try defaultCollection!.indexes().count, 1)
        XCTAssertEqual(try defaultCollection!.indexes(), ["myindex"])
        
        // Create FTS index:
        let detailItem = FullTextIndexItem.property("detail")
        let detailIndex = IndexBuilder.fullTextIndex(items: detailItem)
        try defaultCollection!.createIndex(detailIndex, name: "myindex")
        
        // Check:
        XCTAssertEqual(try defaultCollection!.indexes().count, 1)
        XCTAssertEqual(try defaultCollection!.indexes(), ["myindex"])
    }
    
    func testDeleteIndex() throws {
        // Precheck:
        XCTAssertEqual(try defaultCollection!.indexes().count, 0)
        
        // Create value index:
        let fNameItem = ValueIndexItem.expression(Expression.property("firstName"))
        let lNameItem = ValueIndexItem.expression(Expression.property("lastName"))
        
        let index1 = IndexBuilder.valueIndex(items: fNameItem, lNameItem)
        try defaultCollection!.createIndex(index1, name: "index1")
        
        // Create FTS index:
        let detailItem = FullTextIndexItem.property("detail")
        let index2 = IndexBuilder.fullTextIndex(items: detailItem)
        try defaultCollection!.createIndex(index2, name: "index2")
        
        let detailItem2 = FullTextIndexItem.property("es-detail")
        let index3 = IndexBuilder.fullTextIndex(items: detailItem2).language("es").ignoreAccents(true)
        try defaultCollection!.createIndex(index3, name: "index3")
        
        XCTAssertEqual(try defaultCollection!.indexes().count, 3)
        XCTAssertEqual(try defaultCollection!.indexes(), ["index1", "index2", "index3"])
        
        // Delete indexes:
        try defaultCollection!.deleteIndex(forName: "index1")
        XCTAssertEqual(try defaultCollection!.indexes().count, 2)
        XCTAssertEqual(try defaultCollection!.indexes(), ["index2", "index3"])
        
        try defaultCollection!.deleteIndex(forName: "index2")
        XCTAssertEqual(try defaultCollection!.indexes().count, 1)
        XCTAssertEqual(try defaultCollection!.indexes(), ["index3"])
        
        try defaultCollection!.deleteIndex(forName: "index3")
        XCTAssertEqual(try defaultCollection!.indexes().count, 0)
        
        // Delete non existing index:
        try defaultCollection!.deleteIndex(forName: "dummy")
        
        // Delete deleted indexes:
        try defaultCollection!.deleteIndex(forName: "index1")
        try defaultCollection!.deleteIndex(forName: "index2")
        try defaultCollection!.deleteIndex(forName: "index3")
    }
    
    func testCloseWithActiveLiveQueries() throws {
        let change1 = expectation(description: "changes 1")
        let change2 = expectation(description: "changes 2")
        
        let ds = DataSource.collection(defaultCollection!)
        
        let q1 = QueryBuilder.select().from(ds)
        q1.addChangeListener { (ch) in change1.fulfill() }
        
        let q2 = QueryBuilder.select().from(ds)
        q2.addChangeListener { (ch) in change2.fulfill() }
        
        wait(for: [change1, change2], timeout: expTimeout)
        
        try db.close()
    }
    
    #if COUCHBASE_ENTERPRISE
    
    func testCloseWithActiveReplicators() throws {
        // Live Queries:
        
        let change1 = expectation(description: "changes 1")
        let change2 = expectation(description: "changes 2")
        
        let ds = DataSource.database(db)
        
        let q1 = QueryBuilder.select().from(ds)
        q1.addChangeListener { (ch) in change1.fulfill() }
        
        let q2 = QueryBuilder.select().from(ds)
        q2.addChangeListener { (ch) in change2.fulfill() }
        
        wait(for: [change1, change2], timeout: expTimeout)
        
        // Replicators:
        
        try! openOtherDB()
        
        let target = DatabaseEndpoint(database: otherDB!)
        var config = ReplicatorConfiguration(database: db, target: target)
        config.continuous = true
        
        config.replicatorType = .push
        let r1 = Replicator(config: config)
        let idle1 = allowOverfillExpectation(description: "Idle 1")
        let stopped1 = expectation(description: "Stopped 1")
        startReplicator(r1, idleExpectation: idle1, stoppedExpectation: stopped1)
     
        config.replicatorType = .pull
        let r2 = Replicator(config: config)
        let idle2 = allowOverfillExpectation(description: "Idle 2")
        let stopped2 = expectation(description: "Stopped 2")
        startReplicator(r2, idleExpectation: idle2, stoppedExpectation: stopped2)
        
        wait(for: [idle1, idle2], timeout: expTimeout)
        
        try! db.close()
        
        wait(for: [stopped1, stopped2], timeout: expTimeout)
    }
    
    func startReplicator(_ replicator: Replicator, idleExpectation: XCTestExpectation, stoppedExpectation: XCTestExpectation) {
        replicator.addChangeListener { (change) in
            if change.status.activity == .idle { idleExpectation.fulfill() }
            else if change.status.activity == .stopped { stoppedExpectation.fulfill() }
        }
        replicator.start()
    }
    
    func testCloseWithActiveLiveQueriesAndReplicators() throws {
        try! openOtherDB()
              
        let target = DatabaseEndpoint(database: otherDB!)
        var config = ReplicatorConfiguration(database: db, target: target)
        config.continuous = true
              
        config.replicatorType = .push
        let r1 = Replicator(config: config)
        let idle1 = allowOverfillExpectation(description: "Idle 1")
        let stopped1 = expectation(description: "Stopped 1")
        startReplicator(r1, idleExpectation: idle1, stoppedExpectation: stopped1)
           
        config.replicatorType = .pull
        let r2 = Replicator(config: config)
        let idle2 = allowOverfillExpectation(description: "Idle 2")
        let stopped2 = expectation(description: "Stopped 2")
        startReplicator(r2, idleExpectation: idle2, stoppedExpectation: stopped2)
              
        wait(for: [idle1, idle2], timeout: expTimeout)
              
        try! db.close()
              
        wait(for: [stopped1, stopped2], timeout: expTimeout)
    }
    
    #endif
    
    // MARK: DatabaseConfig
    
    func testSetDatabaseConfigurationProperties() throws {
        // remove temp folder
        let dir = NSTemporaryDirectory().appending("/cbl_temp")
        if FileManager.default.fileExists(atPath: dir) {
            try! FileManager.default.removeItem(atPath: dir)
        }
        XCTAssertTrue(!FileManager.default.fileExists(atPath: dir))
        
        var config = DatabaseConfiguration()
        config.directory = dir
        #if COUCHBASE_ENTERPRISE
        config.encryptionKey = EncryptionKey.password("somePassword")
        #endif
        
        let db = try Database(name: "dbName", config: config)
        XCTAssertEqual(db.config.directory, dir)
        
        #if COUCHBASE_ENTERPRISE
        XCTAssertNotNil(db.config.encryptionKey)
        #endif
    }
    
    func testDefaultDatabaseConfiguration() {
        let config = DatabaseConfiguration()
        XCTAssertEqual(config.directory, DatabaseConfiguration().directory)
        
        #if COUCHBASE_ENTERPRISE
        XCTAssertNil(config.encryptionKey)
        #endif
    }
    
    func testCopyingDatabaseConfiguration() throws {
        var config = DatabaseConfiguration()
        config.directory = self.directory
        #if COUCHBASE_ENTERPRISE
        config.encryptionKey  = EncryptionKey.password("somePassword")
        #endif
        
        db = try Database(name: "someName", config: config)
        let config1 = DatabaseConfiguration(config: config)
        
        // update the config, after passing to constructor;
        config.directory = "\(self.directory)/updatedURL"
        #if COUCHBASE_ENTERPRISE
        config.encryptionKey = nil
        #endif
        // validate no impact on original passed in config.
        XCTAssertEqual(db.config.directory, self.directory)
        XCTAssertEqual(config1.directory, self.directory)
        #if COUCHBASE_ENTERPRISE
        XCTAssertNotNil(db.config.encryptionKey)
        XCTAssertNotNil(config1.encryptionKey)
        #endif
        
        // update the copied config.
        var config2 = db.config
        config2.directory = "\(self.directory)/updatedURL"
        #if COUCHBASE_ENTERPRISE
        config2.encryptionKey = nil
        #endif
        // validate no impact on original passed in config.
        XCTAssertEqual(db.config.directory, self.directory)
        #if COUCHBASE_ENTERPRISE
        XCTAssertNotNil(db.config.encryptionKey)
        #endif
    }
    
    // MARK: Full Sync Option
    /// Test Spec v1.0.0:
    /// https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0003-SQLite-Options.md
    
    /// 1. TestSQLiteFullSyncConfig
    /// Description:
    ///     Test that the FullSync default is as expected and that it's setter and getter work.
    /// Steps
    ///     1. Create a DatabaseConfiguration object.
    ///     2. Get and check the value of the FullSync property: it should be false.
    ///     3. Set the FullSync property true.
    ///     4. Get the config FullSync property and verify that it is true.
    ///     5. Set the FullSync property false.
    ///     6. Get the config FullSync property and verify that it is false.
    func testSQLiteFullSyncConfig() {
        var config = DatabaseConfiguration()
        XCTAssertFalse(config.fullSync)
        
        config.fullSync = true
        XCTAssert(config.fullSync)
        
        config.fullSync = false
        XCTAssertFalse(config.fullSync)
    }
    
    /// 2. TestDBWithFullSync
    /// Description:
    ///     Test that the FullSync default is as expected and that it's setter and getter work.
    /// Steps
    ///     1. Create a DatabaseConfiguration object and set Full Sync false.
    ///     2. Create a database with the config.
    ///     3. Get the configuration object from the Database and verify that FullSync is false.
    ///     4. Use c4db_config2 (perhaps necessary only for this test) to confirm that its config does not contain the kC4DB_DiskSyncFull flag. - done in Obj-C
    ///     5. Set the config's FullSync property true.
    ///     6. Create a database with the config.
    ///     7. Get the configuration object from the Database and verify that FullSync is true.
    ///     8. Use c4db_config2 to confirm that its config contains the kC4DB_DiskSyncFull flag. - done in Obj-C
    func testDBWithFullSync() throws {
        let dbName = "fullsyncdb"
        try deleteDB(name: dbName)
        XCTAssertFalse(Database.exists(withName: dbName, inDirectory: self.directory))
        
        var config = DatabaseConfiguration()
        config.directory = self.directory
        db = try Database(name: dbName, config: config)
        XCTAssertFalse(db.config.fullSync)
        
        db = nil
        config.fullSync = true
        db = try Database(name: dbName, config: config)
        XCTAssert(db.config.fullSync)
    }
    
    // MARK: MMap
    /// Test Spec v1.0.1:
    /// https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0006-MMap-Config.md

     /// 1. TestDefaultMMapConfig
     /// Description
     ///   Test that the mmapEnabled default value is as expected and that it's setter and getter work.
     /// Steps
     ///   1. Create a DatabaseConfiguration object.
     ///   2. Get and check that the value of the mmapEnabled property is true.
     ///   3. Set the mmapEnabled property to false and verify that the value is false.
     ///   4. Set the mmapEnabled property to true, and verify that the mmap value is true.

    func testDefaultMMapConfig() throws {
        var config = DatabaseConfiguration()
        XCTAssertTrue(config.mmapEnabled)
        
        config.mmapEnabled = false;
        XCTAssertFalse(config.mmapEnabled)
        
        config.mmapEnabled = true;
        XCTAssertTrue(config.mmapEnabled)
    }

    /// 2. TestDatabaseWithConfiguredMMap
    /// Description
    ///    Test that a Database respects the mmapEnabled property.
    /// Steps
    ///    1. Create a DatabaseConfiguration object and set mmapEnabled to false.
    ///    2. Create a database with the config.
    ///    3. Get the configuration object from the database and check that the mmapEnabled is false.
    ///    4. Use c4db_config2 to confirm that its config contains the kC4DB_MmapDisabled flag - done in Obj-C
    ///    5. Set the config's mmapEnabled property true
    ///    6. Create a database with the config.
    ///    7. Get the configuration object from the database and verify that mmapEnabled is true
    ///    8. Use c4db_config2 to confirm that its config doesn't contains the kC4DB_MmapDisabled flag - done in Obj-C

    func testDatabaseWithConfiguredMMap() throws {
        var config = DatabaseConfiguration()
        config.mmapEnabled = false;
        let db1 = try Database(name: "mmap1", config: config)
        XCTAssertFalse(db1.config.mmapEnabled)

        config.mmapEnabled = true;
        let db2 = try Database(name: "mmap2", config: config)
        XCTAssert(db2.config.mmapEnabled)
    }

}
