//
//  DatabaseLegacyTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2026 Couchbase, Inc All rights reserved.
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

/// Minimal smoke tests for the deprecated `Database` APIs. The goal is only to touch each
/// restored deprecated entry point and confirm its basic functionality (delegation to the
/// default collection), NOT to re-cover the full behavior the collection tests already do.
///
/// The class is marked deprecated so calls to the deprecated APIs below don't emit warnings.
@available(*, deprecated)
class DatabaseLegacyTest: CBLTestCase {

    // MARK: - Count / Get

    func testCount() throws {
        try db.saveDocument(createDocument("doc1"))
        try db.saveDocument(createDocument("doc2"))
        XCTAssertEqual(db.count, 2)
    }

    func testDocumentWithIDAndSubscript() throws {
        let doc = createDocument("doc1")
        doc.setString("value", forKey: "key")
        try db.saveDocument(doc)

        let saved = db.document(withID: "doc1")
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.string(forKey: "key"), "value")
        XCTAssertNil(db.document(withID: "missing"))

        // Subscript returns a document fragment:
        XCTAssertTrue(db["doc1"].exists)
        XCTAssertFalse(db["missing"].exists)
    }

    // MARK: - Save / Delete / Purge

    func testSaveVariants() throws {
        // saveDocument(_:)
        try db.saveDocument(createDocument("doc1"))

        // saveDocument(_:concurrencyControl:)
        try db.saveDocument(createDocument("doc2"), concurrencyControl: .lastWriteWins)

        // saveDocument(_:conflictHandler:) (no conflict for a new doc, handler not invoked)
        try db.saveDocument(createDocument("doc3"), conflictHandler: { (cur, old) in return true })

        XCTAssertEqual(db.count, 3)
    }

    func testDeleteVariants() throws {
        try db.saveDocument(createDocument("doc1"))
        try db.saveDocument(createDocument("doc2"))

        // deleteDocument(_:)
        try db.deleteDocument(db.document(withID: "doc1")!)

        // deleteDocument(_:concurrencyControl:)
        try db.deleteDocument(db.document(withID: "doc2")!, concurrencyControl: .lastWriteWins)

        XCTAssertEqual(db.count, 0)
    }

    func testPurge() throws {
        // purgeDocument(_:)
        try db.saveDocument(createDocument("doc1"))
        try db.purgeDocument(db.document(withID: "doc1")!)
        XCTAssertNil(db.document(withID: "doc1"))

        // purgeDocument(withID:)
        try db.saveDocument(createDocument("doc2"))
        try db.purgeDocument(withID: "doc2")
        XCTAssertNil(db.document(withID: "doc2"))
    }

    // MARK: - Document Expiration

    func testDocumentExpiration() throws {
        try db.saveDocument(createDocument("doc1"))

        let expiry = Date(timeIntervalSinceNow: 120)
        try db.setDocumentExpiration(withID: "doc1", expiration: expiry)

        let got = db.getDocumentExpiration(withID: "doc1")
        XCTAssertNotNil(got)
        XCTAssertEqual(got!.timeIntervalSinceReferenceDate, expiry.timeIntervalSinceReferenceDate, accuracy: 1.0)

        // Reset expiration with a nil date:
        try db.setDocumentExpiration(withID: "doc1", expiration: nil)
        XCTAssertNil(db.getDocumentExpiration(withID: "doc1"))
    }

    // MARK: - Change Listeners

    func testDatabaseChangeListener() throws {
        // addChangeListener(_:)  (+ DatabaseChange) and removeChangeListener(withToken:)
        let x1 = expectation(description: "db change")
        let token1 = db.addChangeListener { (change) in
            XCTAssertTrue(change.documentIDs.contains("doc1"))
            XCTAssertTrue(change.database === self.db)
            x1.fulfill()
        }
        try db.saveDocument(createDocument("doc1"))
        waitForExpectations(timeout: expTimeout, handler: nil)
        db.removeChangeListener(withToken: token1)

        // addChangeListener(withQueue:listener:)  and token-based removal
        let x2 = expectation(description: "db change on queue")
        let token2 = db.addChangeListener(withQueue: .main) { (change) in
            XCTAssertTrue(change.documentIDs.contains("doc2"))
            x2.fulfill()
        }
        try db.saveDocument(createDocument("doc2"))
        waitForExpectations(timeout: expTimeout, handler: nil)
        token2.remove()
    }

    func testDocumentChangeListener() throws {
        try db.saveDocument(createDocument("doc1"))

        // addDocumentChangeListener(withID:listener:)  (+ deprecated DocumentChange.database)
        let x1 = expectation(description: "doc change")
        let token1 = db.addDocumentChangeListener(withID: "doc1") { (change) in
            XCTAssertEqual(change.documentID, "doc1")
            XCTAssertTrue(change.database === self.db)
            x1.fulfill()
        }
        let update1 = db.document(withID: "doc1")!.toMutable()
        update1.setString("v1", forKey: "k")
        try db.saveDocument(update1)
        waitForExpectations(timeout: expTimeout, handler: nil)
        token1.remove()

        // addDocumentChangeListener(withID:queue:listener:)
        let x2 = expectation(description: "doc change on queue")
        let token2 = db.addDocumentChangeListener(withID: "doc1", queue: .main) { (change) in
            XCTAssertEqual(change.documentID, "doc1")
            x2.fulfill()
        }
        let update2 = db.document(withID: "doc1")!.toMutable()
        update2.setString("v2", forKey: "k")
        try db.saveDocument(update2)
        waitForExpectations(timeout: expTimeout, handler: nil)
        token2.remove()
    }

    // MARK: - Index

    func testIndexes() throws {
        // createIndex(_:withName:) (ValueIndex)
        let index = IndexBuilder.valueIndex(items: ValueIndexItem.property("name"))
        try db.createIndex(index, withName: "nameIndex")
        XCTAssertTrue(db.indexes.contains("nameIndex"))

        // createIndex(_:name:) (ValueIndexConfiguration)
        let config = ValueIndexConfiguration(["age"])
        try db.createIndex(config, name: "ageIndex")
        XCTAssertTrue(db.indexes.contains("ageIndex"))
        XCTAssertEqual(db.indexes.count, 2)

        // deleteIndex(forName:)
        try db.deleteIndex(forName: "nameIndex")
        XCTAssertFalse(db.indexes.contains("nameIndex"))
        XCTAssertEqual(db.indexes.count, 1)
    }
}
