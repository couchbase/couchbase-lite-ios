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
        
        let expiryDate = Date().addingTimeInterval(3.0)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        let expected = db.getDocumentExpiration(withID: doc.id)
        XCTAssertNotNil(expected)
        
        let delta = expiryDate.timeIntervalSince(expected!)
        XCTAssert(fabs(delta) < 0.1)
    }
    
    func testSetExpiryToNonExistingDocument() {
        let expiryDate = Date(timeIntervalSinceNow: 30)
        expectError(domain: CBLErrorDomain, code: CBLErrorNotFound) { [unowned self] in
            try self.db.setDocumentExpiration(withID: "someInvalidID", expiration: expiryDate)
        }
    }
    
    func testDocumentPurgedAfterExpiration() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        let token = db.addDocumentChangeListener(withID: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(self.db.document(withID: doc.id))
            promise.fulfill()
        }
        
        // Set expiry
        let expiryDate = Date().addingTimeInterval(1)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
        
        // Remove listener
        db.removeChangeListener(withToken: token);
    }
    
    func testDocumentNotShownUpInQueryAfterExpiration() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        let token = db.addDocumentChangeListener(withID: doc.id) { [unowned self] (change) in
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(self.db.document(withID: doc.id))
            try! self.verifyQueryResultCount(0, includeDeleted: true)
            promise.fulfill()
        }
        
        // Set expiry
        let expiryDate = Date().addingTimeInterval(1)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
        
        // Remove listener
        db.removeChangeListener(withToken: token);
    }
    
    func verifyQueryResultCount(_ count: Int, includeDeleted: Bool = false) throws {
        var rs = try QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.database(db))
            .execute()
        XCTAssertEqual(rs.allResults().count, count)

        if includeDeleted {
            rs = try QueryBuilder
                .select(SelectResult.expression(Meta.id))
                .from(DataSource.database(db))
                .where(Meta.isDeleted).execute()
            XCTAssertEqual(rs.allResults().count, count)
        }
    }
    
    func testDocumentNotPurgedBeforeExpiration() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        var purgeTime: TimeInterval = 0.0
        let token = db.addDocumentChangeListener(withID: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(self.db.document(withID: doc.id))
            purgeTime = Date().timeIntervalSince1970
            promise.fulfill()
        }
        
        // Set Expiry
        let begin = Date().timeIntervalSince1970
        let expiryDate = Date(timeIntervalSince1970: begin + 2.0)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
        
        // Validate
        XCTAssert(purgeTime - begin >= 2.0)
        
        // Remove listener
        db.removeChangeListener(withToken: token);
    }
    
    func testSetExpirationThenCloseDatabase() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Set Expiry
        let expiryDate = Date().addingTimeInterval(1.0)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        // Close database
        try db.close()
        
        // Validate it is not crashing due to the expiry timer!!
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Crash, if not removed!
            promise.fulfill()
        }
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
    }
    
    func testExpiredDocumentPurgedAfterReopenDatabase() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Set Expiry
        let expiryDate = Date().addingTimeInterval(2.0)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        // Reopen database
        try self.reopenDB()
        
        // Setup document change notification
        let token = db.addDocumentChangeListener(withID: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(self.db.document(withID: doc.id))
            promise.fulfill()
        }
        
        XCTAssertNotNil(self.db.document(withID: doc.id))
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
        
        // Remove listener
        db.removeChangeListener(withToken: token);
    }
    
    func testExpiredDocumentPurgedOnDifferentDBInstance() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Create otherDB instance with same name
        let otherDB = try self.openDB(name: db.name)
        
        // Setup document change notification on otherDB
        let token = otherDB.addDocumentChangeListener(withID: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(otherDB.document(withID: doc.id))
            promise.fulfill()
        }
        
        // Set expiry on db instance
        let expiryDate = Date().addingTimeInterval(1.0)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        XCTAssertNotNil(self.db.document(withID: doc.id))
        XCTAssertNotNil(otherDB.document(withID: doc.id))
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
        
        XCTAssertNil(self.db.document(withID: doc.id))
        XCTAssertNil(otherDB.document(withID: doc.id))
        
        // Remove listener
        otherDB.removeChangeListener(withToken: token);
        
        // Close otherDB
        try otherDB.close()
    }
    
    func testOverrideExpirationWithFartherDate() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        var purgeTime: TimeInterval = 0.0
        let token = db.addDocumentChangeListener(withID: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(self.db.document(withID: doc.id))
            purgeTime = Date().timeIntervalSince1970
            promise.fulfill()
        }
        
        // Set Expiry
        let begin = Date().timeIntervalSince1970
        let expiryDate = Date(timeIntervalSince1970: begin + 1.0)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        // Override
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate.addingTimeInterval(1.0))
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
        
        // Validate
        XCTAssert(purgeTime - begin >= 2.0)
        
        // Remove listener
        db.removeChangeListener(withToken: token);
    }
    
    func testOverrideExpirationWithCloserDate() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        var purgeTime: TimeInterval = 0.0
        let token = db.addDocumentChangeListener(withID: doc.id) { (change) in
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(self.db.document(withID: doc.id))
            purgeTime = Date().timeIntervalSince1970
            promise.fulfill()
        }
        
        // Set Expiry
        let begin = Date().timeIntervalSince1970
        let expiryDate = Date(timeIntervalSince1970: begin + 10.0)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        // Override
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate.addingTimeInterval(-9.0))
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
        
        // Validate
        XCTAssert(purgeTime - begin < 3.0)
        
        // Remove listener
        db.removeChangeListener(withToken: token);
    }
    
    func testRemoveExpirationDate() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Set expiry on db instance
        let expiryDate = Date().addingTimeInterval(1.0)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        // Remove expiry
        try db.setDocumentExpiration(withID: doc.id, expiration: nil)
    
        // Validate
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [unowned self] in
            XCTAssertNotNil(self.db.document(withID: doc.id))
            promise.fulfill()
        }
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
    }
    
    func testSetExpirationThenDeletionAfterwards() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        var count: Int = 0
        let token = db.addDocumentChangeListener(withID: doc.id) { (change) in
            count = count + 1
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(self.db.document(withID: doc.id))
            if count == 2 {
                promise.fulfill()
            }
        }
        
        // Set expiry
        let expiryDate = Date().addingTimeInterval(2.0)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        // Delete doc
        try db.deleteDocument(doc)
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
        
        // Remove listener
        db.removeChangeListener(withToken: token);
    }
    
    func testSetExpirationOnDeletedDocument() throws {
        let promise = expectation(description: "document expiry expectation")
        
        // Create doc
        let doc = try generateDocument(withID: nil)
        
        // Setup document change notification
        var count: Int = 0
        let token = db.addDocumentChangeListener(withID: doc.id) { (change) in
            count = count + 1
            XCTAssertEqual(doc.id, change.documentID)
            XCTAssertNil(self.db.document(withID: doc.id))
            if count == 2 {
                promise.fulfill()
            }
        }
        
        // Delete doc
        try db.deleteDocument(doc)
        
        // Set expiry
        let expiryDate = Date().addingTimeInterval(1.0)
        try db.setDocumentExpiration(withID: doc.id, expiration: expiryDate)
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
        
        // Remove listener
        db.removeChangeListener(withToken: token);
    }
}
