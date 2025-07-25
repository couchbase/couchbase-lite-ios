//
//  DocumentExpiration.swift
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

class DocumentExpirationTest: CBLTestCase {
    
    func testGetExpirationPreSave() {
        let doc = createDocument(nil)
        XCTAssertEqual(defaultCollection!.count, 0)
        XCTAssertNil(try defaultCollection!.getDocumentExpiration(id: doc.id))
    }
    
    func testExpirationFromDocumentWithoutExpiry() throws {
        let doc = try generateDocument(withID: nil)
        XCTAssertEqual(defaultCollection!.count, 1)
        XCTAssertNil(try defaultCollection!.getDocumentExpiration(id: doc.id))
    }
    
    func testSetAndGetExpiration() throws {
        let doc = try generateDocument(withID: nil)
        
        let expiryDate = Date().addingTimeInterval(3.0)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        let expected = try defaultCollection!.getDocumentExpiration(id: doc.id)
        XCTAssertNotNil(expected)
        
        let delta = expiryDate.timeIntervalSince(expected!)
        XCTAssert(fabs(delta) < 0.1)
    }
    
    func testSetExpiryToNonExistingDocument() {
        let expiryDate = Date(timeIntervalSinceNow: 30)
        expectError(domain: CBLError.domain, code: CBLError.notFound) { [unowned self] in
            try self.defaultCollection!.setDocumentExpiration(id: "someInvalidID", expiration: expiryDate)
        }
    }
    
    func testDocumentPurgingAfterSettingExpiry() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create & set expiry
        let doc = try generateDocument(withID: nil)
        try defaultCollection!.setDocumentExpiration(id: doc.id,
                                     expiration: Date().addingTimeInterval(1))
        
        try defaultCollection!.purge(document: doc)
        
        // Validate it is not crashing due to the expiry timer!!
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            promise.fulfill()
        }
        waitForExpectations(timeout: expTimeout)
    }
    
    func testDocumentPurgedAfterExpiration() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        let token = defaultCollection!.addDocumentChangeListener(id: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            if try! change.collection.document(id: doc.id) == nil {
                promise.fulfill()
            }
        }
        
        // Set expiry
        try defaultCollection!.setDocumentExpiration(id: doc.id,
                                     expiration: Date().addingTimeInterval(1))
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        
        // Remove listener
        token.remove();
    }
    
    func testDocumentNotShownUpInQueryAfterExpiration() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        let token = defaultCollection!.addDocumentChangeListener(id: doc.id) { [unowned self] (change) in
            XCTAssertEqual(doc.id, change.documentID)
            if try! change.collection.document(id: doc.id) == nil {
                try! self.verifyQueryResultCount(0, deletedDocs: 0)
                promise.fulfill()
            }
        }
        
        // Set expiry
        let expiryDate = Date().addingTimeInterval(1)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        
        // Remove listener
        token.remove()
    }
    
    func verifyQueryResultCount(_ count: Int, deletedDocs: Int) throws {
        var rs = try QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .execute()
        XCTAssertEqual(rs.allResults().count, count)

        rs = try QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .where(Meta.isDeleted).execute()
        XCTAssertEqual(rs.allResults().count, deletedDocs)
    }
    
    func testDocumentNotPurgedBeforeExpiration() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        let token = defaultCollection!.addDocumentChangeListener(id: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            if try! change.collection.document(id: doc.id) == nil {
                promise.fulfill()
            }
        }
        
        // Set Expiry
        let begin = Date().timeIntervalSince1970
        let expiryDate = Date(timeIntervalSince1970: begin + 2.0)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        
        // Remove listener
        token.remove()
    }
    
    func testSetExpirationThenCloseDatabase() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Set Expiry
        let expiryDate = Date().addingTimeInterval(1.0)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        // Close database
        try db.close()
        
        // Validate it is not crashing due to the expiry timer!!
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Crash, if not removed!
            promise.fulfill()
        }
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
    }
    
    func testExpiredDocumentPurgedAfterReopenDatabase() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Set Expiry
        let expiryDate = Date().addingTimeInterval(2.0)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        // Reopen database
        try self.reopenDB()
        
        // Setup document change notification
        let token = defaultCollection!.addDocumentChangeListener(id: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            if try! change.collection.document(id: doc.id) == nil {
                promise.fulfill()
            }
        }
        
        XCTAssertNotNil(try self.defaultCollection!.document(id: doc.id))
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        
        // Remove listener
        token.remove()
    }
    
    func testExpiredDocumentPurgedOnDifferentDBInstance() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Create otherDB instance with same name
        let otherDB = try self.openDB(name: db.name)
        
        let otherDB_defaultCollection = try otherDB.defaultCollection()
        
        // Setup document change notification on otherDB
        let token = otherDB_defaultCollection.addDocumentChangeListener(id: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            if try! otherDB_defaultCollection.document(id: doc.id) == nil {
                promise.fulfill()
            }
        }
        
        // Set expiry on db instance
        let expiryDate = Date().addingTimeInterval(1.0)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        XCTAssertNotNil(try self.defaultCollection!.document(id: doc.id))
        XCTAssertNotNil(try otherDB_defaultCollection.document(id: doc.id))
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        
        XCTAssertNil(try self.defaultCollection!.document(id: doc.id))
        XCTAssertNil(try otherDB_defaultCollection.document(id: doc.id))
        
        // Remove listener
        token.remove()
        
        // Close otherDB
        try otherDB.close()
    }
    
    func testOverrideExpirationWithFartherDate() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        var purgeTime: TimeInterval = 0.0
        let token = defaultCollection!.addDocumentChangeListener(id: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            if try! change.collection.document(id: doc.id) == nil {
                purgeTime = Date().timeIntervalSince1970
                promise.fulfill()
            }
        }
        
        // Set Expiry
        let begin = Date().timeIntervalSince1970
        let expiryDate = Date(timeIntervalSince1970: begin + 1.0)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        // Override
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate.addingTimeInterval(1.0))
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        
        // Validate
        XCTAssert(purgeTime - begin >= 2.0)
        
        // Remove listener
        token.remove();
    }
    
    func testOverrideExpirationWithCloserDate() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        var purgeTime: TimeInterval = 0.0
        let token = defaultCollection!.addDocumentChangeListener(id: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            if try! change.collection.document(id: doc.id) == nil {
                purgeTime = Date().timeIntervalSince1970
                promise.fulfill()
            }
        }
        
        // Set Expiry
        let begin = Date().timeIntervalSince1970
        let expiryDate = Date(timeIntervalSince1970: begin + 10.0)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        // Override
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate.addingTimeInterval(-9.0))
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        
        // Validate
        XCTAssert(purgeTime - begin < 3.0)
        
        // Remove listener
        token.remove();
    }
    
    func testRemoveExpirationDate() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Set expiry on db instance
        let expiryDate = Date().addingTimeInterval(1.0)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        // Remove expiry
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: nil)
    
        // Validate
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [unowned self] in
            XCTAssertNotNil(try! self.defaultCollection!.document(id: doc.id))
            promise.fulfill()
        }
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
    }
    
    func testSetExpirationThenDeletionAfterwards() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        var count: Int = 0
        let token = defaultCollection!.addDocumentChangeListener(id: doc.id) { (change) in
            count = count + 1
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(try! change.collection.document(id: doc.id))
            if count == 2 {
                promise.fulfill()
            }
        }
        
        // Set expiry
        let expiryDate = Date().addingTimeInterval(2.0)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        // Delete doc
        try defaultCollection!.delete(document: doc)
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        XCTAssertEqual(count, 2)
        
        // Remove listener
        token.remove()
    }
    
    func testSetExpirationOnDeletedDocument() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        var count: Int = 0
        let token = defaultCollection!.addDocumentChangeListener(id: doc.id) { (change) in
            count = count + 1
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(try! change.collection.document(id: doc.id))
            if count == 2 {
                promise.fulfill()
            }
        }
        
        // Delete doc
        try defaultCollection!.delete(document: doc)
        
        // Set expiry
        let expiryDate = Date().addingTimeInterval(1.0)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        XCTAssertEqual(count, 2)
        
        // Remove listener
        token.remove()
    }
    
    func testPurgeImmedietly() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        var purgeTime: Date!
        let begin = Date()
        let token = defaultCollection!.addDocumentChangeListener(id: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            if try! change.collection.document(id: doc.id) == nil {
                purgeTime = Date()
                promise.fulfill()
            }
        }
        
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: Date())
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        
        
        /// Validate. Delay inside the KeyStore::now() is in seconds, without milliseconds part.
        /// Depending on the current milliseconds, we cannot gurantee, this will get purged exactly
        /// within a second but in ~1 second.
        let delta = purgeTime.timeIntervalSince(begin)
        assert(delta < 2);
        
        // Remove listener
        token.remove()
    }
    
    func testWhetherDatabaseEventTrigged() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        let token = defaultCollection!.addChangeListener { (change) in
            XCTAssertEqual(change.documentIDs.count, 1)
            let docID = change.documentIDs.first
            XCTAssertNotNil(docID)
            XCTAssertEqual(doc.id, docID)
            promise.fulfill()
        }
        
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: Date(timeIntervalSinceNow: 1))
        
        // Wait for result
        waitForExpectations(timeout: expTimeout)
        
        // Remove listener
        token.remove()
    }
    
}
