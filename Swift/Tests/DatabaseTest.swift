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
    
    func generateDocument(withID id: String?) throws -> MutableDocument {
        let doc = createDocument(id);
        doc.setValue(1, forKey: "key")
        try saveDocument(doc)
        XCTAssertEqual(doc.sequence, 1)
        XCTAssertNotNil(doc.id)
        if id != nil {
            XCTAssertEqual(doc.id, id)
        }
        return doc
    }
    
    func verifyDocument(withID id: String, data: Dictionary<String, Any>) {
        let doc = db.document(withID: id)
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
    
    func validateDocs(_ n: Int) {
        for i in 0..<n {
            let docID = String(format: "doc_%03d", i)
            verifyDocument(withID: docID, data: ["key": i])
        }
    }
    
    func saveDocument(_ document: MutableDocument,
                      concurrencyControl: ConcurrencyControl?) throws -> Bool
    {
        var success = true
        if let cc = concurrencyControl {
            success = try db.saveDocument(document, concurrencyControl: cc)
            if cc == .failOnConflict {
                XCTAssertFalse(success)
            } else {
                XCTAssertTrue(success)
            }
        } else {
            try db.saveDocument(document)
        }
        return success
    }
    
    func deleteDocument(_ document: MutableDocument,
                        concurrencyControl: ConcurrencyControl?) throws -> Bool
    {
        var success = true
        if let cc = concurrencyControl {
            success = try db.deleteDocument(document, concurrencyControl: cc)
            if cc == .failOnConflict {
                XCTAssertFalse(success)
            } else {
                XCTAssertTrue(success)
            }
        } else {
            try db.deleteDocument(document)
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
        XCTAssertNil(db.document(withID: "doc1"))

        let doc = MutableDocument(id: "doc1")
        XCTAssertEqual(doc.id, "doc1")
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
    
    // MARK: Save Document
    
    func testSaveDocWithID() throws {
        let doc = try generateDocument(withID: "doc1")
        XCTAssertEqual(db.count, 1)
        verifyDocument(withID: doc.id, data: doc.toDictionary())
    }
    
    func testSaveDocWithSpecialCharactersDocID() throws {
        let docID = "`~@#$%^&*()_+{}|\\][=-/.,<>?\":;'"
        let doc = try generateDocument(withID: docID)
        XCTAssertEqual(db.count, 1)
        verifyDocument(withID: doc.id, data: doc.toDictionary())
    }
    
    func testSaveDocWIthAutoGeneratedID() throws {
        let doc = try generateDocument(withID: nil)
        XCTAssertEqual(db.count, 1)
        verifyDocument(withID: doc.id, data: doc.toDictionary())
    }
    
    func testSaveDocInDifferenceDBInstance() throws {
        let doc = try generateDocument(withID: "doc1")
        
        let otherDB = try self.openDB(name: db.name)
        XCTAssertNotNil(otherDB)
        XCTAssertEqual(otherDB.count, 1)
        
        doc.setValue(2, forKey: "key")
        expectError(domain: CBLErrorDomain, code: CBLErrorInvalidParameter) {
            try otherDB.saveDocument(doc)
        } // forbidden
        
        try otherDB.close()
    }
    
    func testSaveDocInDifferenceDB() throws {
        let doc = try generateDocument(withID: "doc1")
        
        let otherDB = try self.openDB(name: "otherDB")
        XCTAssertNotNil(otherDB)
        XCTAssertEqual(otherDB.count, 0)
        
        doc.setValue(2, forKey: "key")
        expectError(domain: CBLErrorDomain, code: CBLErrorInvalidParameter) {
            try otherDB.saveDocument(doc)
        } // forbidden
        
        try otherDB.close()
    }
    
    func testSaveSameDocTwice() throws {
        let doc = try generateDocument(withID: "doc1")
        try saveDocument(doc)
        
        let doc1 = db.document(withID: doc.id)!
        XCTAssertEqual(doc1.sequence, 2)
        XCTAssertEqual(db.count, 1)
    }
    
    func testSaveInBatch() throws {
        try db.inBatch {
            try createDocs(10)
        }
        XCTAssertEqual(db.count, 10)
        validateDocs(10)
    }
    
    func testSaveManyDocs() throws {
        try createDocs(1000)
        XCTAssertEqual(db.count, 1000)
        validateDocs(1000)
        
        // Cleanup:
        try db.delete()
        try reopenDB()
        
        try db.inBatch {
            try createDocs(1000)
        }
        XCTAssertEqual(db.count, 1000)
        validateDocs(1000)
    }
    
    func testAndUpdateMutableDoc() throws {
        let doc = createDocument("doc1")
        doc.setString("Daniel", forKey: "firstName")
        try db.saveDocument(doc)
        
        // Update
        doc.setString("Tiger", forKey: "lastName")
        try db.saveDocument(doc)
        
        // Update
        doc.setInt(20, forKey: "age")
        try db.saveDocument(doc)
        
        let expectedResult: [String : Any] =
            ["firstName": "Daniel", "lastName": "Tiger", "age": 20]
        XCTAssertTrue(doc.toDictionary() == expectedResult)
        XCTAssertEqual(doc.sequence, 3)
        
        let savedDoc = db.document(withID: doc.id)!
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
        try db.saveDocument(doc)
        
        // Get two doc1 document objects (doc1a and doc1b):
        let doc1a = db.document(withID: doc.id)!.toMutable()
        let doc1b = db.document(withID: doc.id)!.toMutable()
        
        // Modify doc1a:
        doc1a.setString("Scott", forKey: "firstName")
        try db.saveDocument(doc1a)
        doc1a.setString("Scotty", forKey: "nickName")
        try db.saveDocument(doc1a)
        XCTAssertTrue(doc1a.toDictionary() ==
            ["firstName": "Scott", "lastName": "Tiger", "nickName": "Scotty"])
        XCTAssertEqual(doc1a.sequence, 3)
        
        // Modify doc1b:
        doc1b.setString("Lion", forKey: "lastName")
        if try saveDocument(doc1b, concurrencyControl: cc) {
            let savedDoc = db.document(withID: doc1b.id)!
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
        try db.saveDocument(doc1a)
        XCTAssertEqual(doc1a.sequence, 1)
        let savedDoc = db.document(withID: "doc1")!
        XCTAssertEqual(savedDoc.sequence, 1)
        
        let doc1b = createDocument(doc1a.id)
        doc1b.setString("Scott", forKey: "firstName")
        doc1b.setString("Tiger", forKey: "lastName")
        if try saveDocument(doc1b, concurrencyControl: cc) {
            let savedDoc = db.document(withID: doc1b.id)!
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
        try db.saveDocument(doc)
        
        // Get two doc1 document objects (doc1a and doc1b):
        let doc1a = db.document(withID: doc.id)!
        let doc1b = db.document(withID: doc.id)!.toMutable()
        
        // Delete doc1a
        try db.deleteDocument(doc1a)
        XCTAssertEqual(doc1a.sequence, 2)
        XCTAssertNil(db.document(withID: doc1a.id))
        
        // Modify doc1b:
        doc1b.setString("Lion", forKey: "lastName")
        if try saveDocument(doc1b, concurrencyControl: cc) {
            let savedDoc = db.document(withID: doc1b.id)!
            XCTAssertTrue(savedDoc.toDictionary() == doc1b.toDictionary())
            XCTAssertEqual(savedDoc.sequence, 3)
        }
        
        // Cleanup:
        try cleanDB()
    }
    
    // MARK: Delete Document
    
    func testDeletePreSaveDoc() throws {
        let doc = MutableDocument(id: "doc1")
        doc.setValue(1, forKey: "key")
        expectError(domain: CBLErrorDomain, code: CBLErrorNotFound) {
            try self.db.deleteDocument(doc)
        }
    }
    
    func testDeleteDoc() throws {
        let doc = try generateDocument(withID: "doc1")
        try db.deleteDocument(doc)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: doc.id))
    }
    
    func testDeleteSameDocTwice() throws {
        let doc = try generateDocument(withID: "doc1")
        
        // First time deletion:
        try db.deleteDocument(doc)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: doc.id))
        XCTAssertEqual(doc.sequence, 2)
        
        // Second time deletion:
        try db.deleteDocument(doc)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: doc.id))
        XCTAssertEqual(doc.sequence, 3)
    }
    
    func testDeleteNoneExistingDoc() throws {
        let doc1a = try generateDocument(withID: "doc1")
        let doc1b = db.document(withID: doc1a.id)!
        
        // Purge doc:
        try db.purgeDocument(doc1a)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: doc1a.id))
        
        // Delete doc1a, 404 error:
        expectError(domain: CBLErrorDomain, code: CBLErrorNotFound) {
            try self.db.deleteDocument(doc1a)
        }
        
        // Delete doc, no-ops:
        try db.deleteDocument(doc1b)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: doc1b.id))
    }
    
    func testDeleteDocInBatch() throws {
        // Save 10 docs:
        let docs = try createDocs(10)
        try db.inBatch {
            for i in 0...9 {
                let doc = db.document(withID: docs[i].id)!
                try db.deleteDocument(doc)
                XCTAssertEqual(db.count, UInt64(9 - i))
            }
        }
        XCTAssertEqual(db.count, 0)
    }
    
    func testDeleteDocOnDeletedDB() throws {
        let doc = MutableDocument(id: "doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try db.saveDocument(doc)
        
        try db.deleteDocument(doc)
        XCTAssertEqual(doc.sequence, 2)
        XCTAssertNil(db.document(withID: doc.id))
        
        doc.setString("Scott", forKey: "firstName")
        try db.saveDocument(doc)
        XCTAssertEqual(doc.sequence, 3)
        XCTAssertTrue(doc.toDictionary() ==
            ["firstName": "Scott", "lastName": "Tiger"])
        
        let savedDoc = db.document(withID: doc.id)!
        XCTAssertTrue(savedDoc.toDictionary() == doc.toDictionary())
    }
    
    func testDeleteAndUpdateDoc() throws {
        let doc = MutableDocument(id: "doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try db.saveDocument(doc)
        
        try db.deleteDocument(doc)
        XCTAssertEqual(doc.sequence, 2)
        XCTAssertNil(db.document(withID: doc.id))
        
        doc.setString("Scott", forKey: "firstName")
        try db.saveDocument(doc)
        XCTAssertEqual(doc.sequence, 3)
        XCTAssertTrue(doc.toDictionary() == ["firstName": "Scott", "lastName": "Tiger"])
        
        let savedDoc = db.document(withID: doc.id)!
        XCTAssertTrue(savedDoc.toDictionary() == doc.toDictionary())
    }
    
    func testDeleteAlreadyDeletedDoc() throws {
        let doc = MutableDocument(id: "doc1")
        doc.setString("Daniel", forKey: "firstName")
        doc.setString("Tiger", forKey: "lastName")
        try db.saveDocument(doc)
        
        // Get two doc1 document objects (doc1a and doc1b):
        let doc1a = db.document(withID: doc.id)!
        let doc1b = db.document(withID: doc.id)!.toMutable()
        
        // Delete doc1a:
        try db.deleteDocument(doc1a)
        XCTAssertEqual(doc1a.sequence, 2)
        XCTAssertNil(db.document(withID: doc.id))
        
        // Delete doc1b:
        try db.deleteDocument(doc1b)
        XCTAssertEqual(doc1a.sequence, 2)
        XCTAssertNil(db.document(withID: doc.id))
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
        try db.saveDocument(doc)
        
        // Get two document objects (doc1a and doc1b):
        let doc1a = db.document(withID: doc.id)!.toMutable()
        let doc1b = db.document(withID: doc.id)!.toMutable()
        
        // Modify doc1a
        doc1a.setString("Scott", forKey: "firstName")
        try db.saveDocument(doc1a)
        XCTAssertTrue(doc1a.toDictionary() == ["firstName": "Scott", "lastName": "Tiger"])
        XCTAssertEqual(doc1a.sequence, 2)
        
        // Modify doc1b and delete, result to conflict when delete:
        doc1b.setString("Lion", forKey: "lastName")
        if try deleteDocument(doc1b, concurrencyControl: cc) {
            XCTAssertEqual(doc1b.sequence, 3)
            XCTAssertNil(db.document(withID: doc1b.id))
        }
        XCTAssertTrue(doc1b.toDictionary() == ["firstName": "Daniel", "lastName": "Lion"])
        
        // Cleanup
        try cleanDB()
    }
    
    // MARK: Purge Document
    
    func testPurgePreSaveDoc() throws {
        let doc = createDocument("doc1")
        expectError(domain: CBLErrorDomain, code: CBLErrorNotFound) {
            try self.db.purgeDocument(doc)
        }
    }
    
    func testPurgeDoc() throws {
        let doc = try generateDocument(withID: "doc1")
        try db.purgeDocument(doc)
        XCTAssertNil(db.document(withID: "doc1"))
        XCTAssertEqual(db.count, 0)
    }
    
    func testPurgeDocInDifferentDBInstance() throws {
        let doc = try generateDocument(withID: "doc1")
        let otherDB = try openDB(name: db.name)
        XCTAssertNotNil(otherDB.document(withID: doc.id))
        XCTAssertEqual(otherDB.count, 1)
        expectError(domain: CBLErrorDomain, code: CBLErrorInvalidParameter) {
            try otherDB.purgeDocument(doc)
        }
        try otherDB.close()
    }
    
    func testPurgeDocInDifferentDB() throws {
        let doc = try generateDocument(withID: "doc1")
        let otherDB = try openDB(name: "otherDB")
        expectError(domain: CBLErrorDomain, code: CBLErrorInvalidParameter) {
            try otherDB.purgeDocument(doc)
        }
        try otherDB.delete()
    }
    
    func testPurgeSameDocTwice() throws {
        let doc = try generateDocument(withID: "doc1")
        try db.purgeDocument(doc)
        XCTAssertNil(db.document(withID: "doc1"))
        XCTAssertEqual(db.count, 0)
        
        expectError(domain: CBLErrorDomain, code: CBLErrorNotFound) {
            try self.db.purgeDocument(doc)
        }
    }
    
    func testPurgeDocInBatch() throws {
        try createDocs(10)
        try db.inBatch {
            for i in 0..<10 {
                let docID = String(format: "doc_%03d", i)
                let doc = db.document(withID: docID)!
                try self.db.purgeDocument(doc)
                XCTAssertNil(db.document(withID: docID))
                XCTAssertEqual(self.db.count, UInt64(9 - i))
            }
        }
    }
    
    func testPurgeDocumentOnADeletedDocument() throws {
        let document = try generateDocument(withID: nil)
        
        // Delete document
        try self.db.deleteDocument(document)
        
        // Purge doc
        try db.purgeDocument(document)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: document.id))
    }
    
    // MARK: Purge Document With ID
    
    func testPreSavePurgeDocumentWithID() throws {
        let documentID = "\(Date().timeIntervalSince1970)"
        let _ = createDocument(documentID)
        expectError(domain: CBLErrorDomain, code: CBLErrorNotFound) {
            try self.db.purgeDocument(withID: documentID)
        }
    }
    
    func testPurgeDocumentWithID() throws {
        let doc = try generateDocument(withID: nil)
        
        try self.db.purgeDocument(doc)
        
        XCTAssertNil(db.document(withID: doc.id))
        XCTAssertEqual(db.count, 0)
    }
    
    func testPurgeDocumentWithIDInDifferentDBInstance() throws {
        let document = try generateDocument(withID: nil)
        let documentID = document.id
        let otherDB = try openDB(name: db.name)
        XCTAssertNotNil(otherDB.document(withID: documentID))
        XCTAssertEqual(otherDB.count, 1)
        
        // should delete it without any errors
        try otherDB.purgeDocument(withID: documentID)
        
        try otherDB.close()
    }
    
    func testPurgeDocumentWithIDInDifferentDB() throws {
        let document = try generateDocument(withID: nil)
        let documentID = document.id
        let otherDB = try openDB(name: "otherDB")
        expectError(domain: CBLErrorDomain, code: CBLErrorNotFound) {
            try otherDB.purgeDocument(withID: documentID)
        }
        try otherDB.delete()
    }
    
    func testCallPurgeDocumentWithIDTwice() throws {
        let document = try generateDocument(withID: nil)
        let documentID = document.id
        try db.purgeDocument(withID: documentID)
        XCTAssertNil(db.document(withID: documentID))
        XCTAssertEqual(db.count, 0)
        
        expectError(domain: CBLErrorDomain, code: CBLErrorNotFound) { [unowned self] in
            try self.db.purgeDocument(withID: documentID)
        }
    }
    
    func testPurgeDocumentWithIDInBatch() throws {
        let totalDocumentsCount = 10
        try createDocs(totalDocumentsCount)
        try db.inBatch { [unowned self] in
            for i in 0..<totalDocumentsCount {
                let documentID = String(format: "doc_%03d", i)
                try self.db.purgeDocument(withID: documentID)
                XCTAssertNil(db.document(withID: documentID))
                XCTAssertEqual(self.db.count, UInt64((totalDocumentsCount - 1) - i))
            }
        }
        XCTAssertEqual(db.count, 0)
    }
    
    func testDeletePurgedDocumentWithID() throws {
        let document = try generateDocument(withID: nil)
        let documentID = document.id
        let anotherDocumentReference = db.document(withID: documentID)!
        
        // Purge doc
        try db.purgeDocument(withID: documentID)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: documentID))
        
        // Delete document & anotherDocumentReference -> no-ops
        try self.db.deleteDocument(document)
        try db.deleteDocument(anotherDocumentReference)
        
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: documentID))
    }
    
    func testPurgeDocumentWithIDOnADeletedDocument() throws {
        let document = try generateDocument(withID: nil)
        let documentID = document.id
        
        // Delete document
        try self.db.deleteDocument(document)
        
        // Purge doc
        try db.purgeDocument(withID: documentID)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: documentID))
    }
    
    // MARK: Index
    
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
    
    // MARK: Document Expiration
    
    func testGetExpirationPreSave() {
        let doc = createDocument(nil)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.getDocumentExpiration(withID: doc.id))
    }
    
    func testExpirationFromDocumentWithoutExpiry() throws {
        let doc = try generateDocument(withID: nil)
        
        XCTAssertEqual(db.count, 1)
        XCTAssertNil(db.getDocumentExpiration(withID: doc.id))
    }
    
    func testSetAndGetExpiration() throws {
        let doc = try generateDocument(withID: nil)
        
        let expiryTime: TimeInterval = 3.0
        let expiryDate = Date().addingTimeInterval(expiryTime)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        let savedDate = db.getDocumentExpiration(withID: doc.id)
        XCTAssertNotNil(savedDate)
        XCTAssert(expiryDate.timeIntervalSince(savedDate!) < 1)
    }
    
    func testSetExpiryToNonExistingDocument() {
        let expiryDate = Date(timeIntervalSinceNow: 30)
        
        expectError(domain: CBLErrorDomain, code: CBLErrorNotFound) { [unowned self] in
            try self.db.setDocumentExpiration(withID: "someInvalidID", expiration: expiryDate)
        }
    }
    
    func testWhetherDocumentRemovedAfterExpiry() throws {
        let promise = expectation(description: "document expiry expectation")
        let doc = try generateDocument(withID: nil)
        
        let expiryTime: TimeInterval = 4.0
        let bufferTime: TimeInterval = 2.0
        let expiryDate = Date().addingTimeInterval(expiryTime)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + expiryTime + bufferTime) { [unowned self] in
            XCTAssertNil(self.db.document(withID: doc.id))
            promise.fulfill()
        }
        
        waitForExpectations(timeout: expiryTime + bufferTime) { (error) in
            XCTAssertNil(error)
        }
    }
    
    func testWhetherDocumentNotRemovedBeforeExpiry() throws {
        let promise = expectation(description: "document expiry expectation")
        let doc = try generateDocument(withID: nil)
        
        let expiryTime: TimeInterval = 4.0
        let bufferTime: TimeInterval = 1.0
        let expiryDate = Date().addingTimeInterval(expiryTime)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + expiryTime - bufferTime) { [unowned self] in
            XCTAssertNotNil(self.db.document(withID: doc.id))
            promise.fulfill()
        }
        
        waitForExpectations(timeout: expiryTime + bufferTime) { (error) in
            XCTAssertNil(error)
        }
    }
    
    func testUnScheduleAfterDBClosed() throws {
        let promise = expectation(description: "document expiry expectation")
        let doc = try generateDocument(withID: nil)
        
        let expiryTime: TimeInterval = 5.0
        let bufferTime: TimeInterval = 2.0
        let expiryDate = Date().addingTimeInterval(expiryTime)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        try db.close()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + expiryTime + bufferTime) {
            // crash, if not removed!
            promise.fulfill()
        }
        
        waitForExpectations(timeout: expiryTime + (2 * bufferTime)) { (error) in
            XCTAssertNil(error)
        }
    }
    
    func testReScheduleOfPurgeDocuments() throws {
        let promise = expectation(description: "document expiry expectation")
        let doc = try generateDocument(withID: nil)
        
        let expiryTime: TimeInterval = 5.0
        let bufferTime: TimeInterval = 2.0
        let expiryDate = Date().addingTimeInterval(expiryTime)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        try db.close()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + bufferTime) { [unowned self] in
            try! self.reopenDB()
            XCTAssertNotNil(self.db.document(withID: doc.id))
        }
        
        DispatchQueue
            .main
            .asyncAfter(deadline: .now() + expiryTime + bufferTime) { [unowned self] in
                XCTAssertNil(self.db.document(withID: doc.id))
                promise.fulfill()
        }
        
        waitForExpectations(timeout: expiryTime + (2 * bufferTime)) { (error) in
            XCTAssertNil(error)
        }
    }
    
    func testExpiryDocumentRemovesDocFromDifferentDBInstance() throws {
        let promise = expectation(description: "document expiry expectation")
        let doc = try generateDocument(withID: nil)
        
        let expiryTime: TimeInterval = 3.0
        let bufferTime: TimeInterval = 2.0
        let expiryDate = Date().addingTimeInterval(expiryTime)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        let otherDB = try self.openDB(name: db.name)
        XCTAssertNotNil(otherDB)
        XCTAssertEqual(otherDB.count, 1)
        
        DispatchQueue
            .main
            .asyncAfter(deadline: .now() + expiryTime + bufferTime) { [unowned self] in
                XCTAssertNil(self.db.document(withID: doc.id))
                XCTAssertNil(otherDB.document(withID: doc.id))
                promise.fulfill()
                XCTAssertEqual(self.db.count, 0)
                XCTAssertEqual(otherDB.count, 0)
                
                try! otherDB.close()
        }
        
        waitForExpectations(timeout: expiryTime + (2 * bufferTime)) { (error) in
            XCTAssertNil(error)
        }
    }
    
    func testOverrideExpirationWithFartherDateIsValid() throws {
        let promise = expectation(description: "document expiry expectation")
        let doc = try generateDocument(withID: nil)
        
        let expiryTime: TimeInterval = 3.0
        let bufferTime: TimeInterval = 2.0
        let initialExpiryDate = Date().addingTimeInterval(expiryTime)
        try db.setDocumentExpiration(withID: doc.id, expiration: initialExpiryDate)
        
        // override
        let secondaryExpiryDate = initialExpiryDate.addingTimeInterval(expiryTime)
        try db.setDocumentExpiration(withID: doc.id, expiration: secondaryExpiryDate)
        
        DispatchQueue
            .main
            .asyncAfter(deadline: .now() + expiryTime + bufferTime) { [unowned self] in
                XCTAssertNotNil(self.db.document(withID: doc.id))
        }
        
        DispatchQueue
            .main
            .asyncAfter(deadline: .now() + (2 * expiryTime) +  bufferTime) { [unowned self] in
                XCTAssertNil(self.db.document(withID: doc.id))
                promise.fulfill()
        }
        
        waitForExpectations(timeout: (2 * expiryTime) + (2 * bufferTime)) { (error) in
            XCTAssertNil(error)
        }
    }
    
    func testOverrideExpirationWithCloserDateIsValid() throws {
        let promise = expectation(description: "document expiry expectation")
        let doc = try generateDocument(withID: nil)
        
        let expiryTime: TimeInterval = 10.0
        let bufferTime: TimeInterval = 2.0
        let initialExpiryDate = Date().addingTimeInterval(expiryTime)
        try db.setDocumentExpiration(withID: doc.id, expiration: initialExpiryDate)
        
        // override
        let secondaryExpiryDate = initialExpiryDate.addingTimeInterval(-expiryTime/2)
        try db.setDocumentExpiration(withID: doc.id, expiration: secondaryExpiryDate)
        
        DispatchQueue
            .main
            .asyncAfter(deadline: .now() + (expiryTime/2) +  bufferTime) { [unowned self] in
                XCTAssertNil(self.db.document(withID: doc.id))
                promise.fulfill()
        }
        
        waitForExpectations(timeout: expiryTime + (2 * bufferTime)) { (error) in
            XCTAssertNil(error)
        }
    }
    
    func testRemoveExpirationDate() throws {
        let promise = expectation(description: "document expiry expectation")
        let doc = try generateDocument(withID: nil)
        
        let expiryTime: TimeInterval = 10.0
        let bufferTime: TimeInterval = 2.0
        let expiryDate = Date().addingTimeInterval(expiryTime)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        XCTAssertNotNil(db.getDocumentExpiration(withID: doc.id))
        
        // override
        try db.setDocumentExpiration(withID: doc.id, expiration: nil)
        XCTAssertNil(db.getDocumentExpiration(withID: doc.id))
        
        DispatchQueue
            .main
            .asyncAfter(deadline: .now() + (expiryTime) +  bufferTime) { [unowned self] in
                XCTAssertNotNil(self.db.document(withID: doc.id))
                promise.fulfill()
        }
        
        waitForExpectations(timeout: expiryTime + (2 * bufferTime)) { (error) in
            XCTAssertNil(error)
        }
    }
}
