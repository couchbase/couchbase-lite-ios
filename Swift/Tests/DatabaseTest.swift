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
            for i in 0...10 {
                let doc = Document("doc\(i)")
                try db.save(doc)
            }
        }
        for i in 0...10 {
            XCTAssert(db.contains("doc\(i)"))
        }
    }

}
