//
//  DatabaseTest.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import Foundation
import CouchbaseLiteSwift


class DatabaseTest: CBLTestCase {

    func testProperties() throws {
        XCTAssertEqual(db.name, kDatabaseName)
        XCTAssert(db.path!.contains(kDatabaseName))
        XCTAssert(Database.exists(kDatabaseName, inDirectory: kDirectory))
    }

    func testCreateUntitledDocument() throws {
        let doc = db.document()
        XCTAssertFalse(doc.documentID.isEmpty)
        XCTAssert(doc.database === db!)
        XCTAssertFalse(doc.exists)
        XCTAssertFalse(doc.isDeleted)
        XCTAssertNil(doc.properties)
    }

    func testCreateNamedDocument() throws {
        XCTAssertFalse(db.contains("doc1"))

        let doc = db.document(withID: "doc1")
        XCTAssertEqual(doc.documentID, "doc1")
        XCTAssert(doc.database === db!)
        XCTAssertFalse(doc.exists)
        XCTAssertFalse(doc.isDeleted)
        XCTAssertNil(doc.properties)

        XCTAssertFalse(db.contains("doc1"))
        try doc.save()

        XCTAssertTrue(db.contains("doc1"))
    }

    func testInBatch() throws {
        try db.inBatch {
            for i in 0...10 {
                let doc = db["doc\(i)"]
                try doc.save()
            }
        }
        for i in 0...10 {
            XCTAssert(db.contains("doc\(i)"))
        }
    }

}
