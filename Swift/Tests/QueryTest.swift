//
//  QueryTest.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift


class QueryTest: CBLTestCase {

    func testAllDocs() throws {
        try loadJSONResource(resourceName: "names_100")
        var n: UInt64 = 0;
        for doc in db.allDocuments {
            n += 1
            let expectedID = String(format: "doc-%03llu", n);
            XCTAssertEqual(doc.documentID, expectedID);
            XCTAssertEqual(doc.sequence, n);
        }
        XCTAssertEqual(n, 100);
    }

    func testNoWhereQuery() throws {
        try loadJSONResource(resourceName: "names_100")

        let query = db.createQueryWhere(nil)
        let n = try verifyQuery(query) { (n, row) in
            let expectedID = String(format: "doc-%03llu", n);
            XCTAssertEqual(row.documentID, expectedID);
            XCTAssertEqual(row.sequence, n);
            let doc = row.document;
            XCTAssertEqual(doc.documentID, expectedID);
            XCTAssertEqual(doc.sequence, n);
        }
        XCTAssertEqual(n, 100);
    }

    func testPropertyQuery() throws {
        try loadJSONResource(resourceName: "names_100")

        for _ in 0...1 {
            let query = db.createQueryWhere("name.first == $FIRSTNAME")
            print("Query = \(try query.explain())")
            query.parameters = ["FIRSTNAME": "Claude"]
            let n = try verifyQuery(query) { (n, row) in
                XCTAssertEqual(row.documentID, "doc-009");
                XCTAssertEqual(row.sequence, 9);
                let doc = row.document;
                XCTAssertEqual(doc.documentID, "doc-009");
                XCTAssertEqual(doc.sequence, 9);
            }
            XCTAssertEqual(n, 1);

            try db.createIndex([NSExpression(forKeyPath: "name.first")])
        }
    }


    func verifyQuery(_ query: Query, block: (UInt64, QueryRow) throws ->Void) throws -> UInt64 {
        var n: UInt64 = 0
        for row in try query.run() {
            n += 1
            try block(n, row)
        }
        return n
    }

}
