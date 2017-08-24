//
//  QueryTest.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift


class PredicateQueryTest: CBLTestCase {
    func testAllDocs() throws {
        try loadJSONResource(name: "names_100")
        var n: UInt64 = 0;
        for doc in db.allDocuments {
            n += 1
            let expectedID = String(format: "doc-%03llu", n);
            XCTAssertEqual(doc.id, expectedID);
            XCTAssertEqual(doc.sequence, n);
        }
        XCTAssertEqual(n, 100);
    }

    func testNoWhereQuery() throws {
        try loadJSONResource(name: "names_100")

        let query = db.createQuery()
        let n = try verifyQuery(query) { (n, row) in
            let expectedID = String(format: "doc-%03llu", n);
            XCTAssertEqual(row.documentID, expectedID);
            XCTAssertEqual(row.sequence, n);
            let doc = row.document;
            XCTAssertEqual(doc.id, expectedID);
            XCTAssertEqual(doc.sequence, n);
        }
        XCTAssertEqual(n, 100);
    }

    func testPropertyQuery() throws {
        try loadJSONResource(name: "names_100")

        for _ in 0...1 {
            let query = db.createQuery(where: "name.first == $FIRSTNAME")
            print("Query = \(try query.explain())")
            query.parameters = ["FIRSTNAME": "Claude"]
            let n = try verifyQuery(query) { (n, row) in
                XCTAssertEqual(row.documentID, "doc-009");
                XCTAssertEqual(row.sequence, 9);
                let doc = row.document;
                XCTAssertEqual(doc.id, "doc-009");
                XCTAssertEqual(doc.sequence, 9);
            }
            XCTAssertEqual(n, 1);
            
            let item = ValueIndexItem.expression(Expression.property("name.first"))
            let index = Index.valueIndex().on(item)
            try db.createIndex(index, forName: "name.first")
        }
    }

    func testProjection() throws {
        let expectedDocs = ["doc-076", "doc-008", "doc-014"]
        let expectedZips = ["55587", "56307", "56308"]
        let expectedEmails = [ ["monte.mihlfeld@nosql-matters.org"],
                               ["jennefer.menning@nosql-matters.org", "jennefer@nosql-matters.org"],
                               ["stephen.jakovac@nosql-matters.org"] ]

        try loadJSONResource(name: "names_100")
        let query = db.createQuery(where: "contact.address.state == $STATE",
                                   returning: ["contact.address.zip", "contact.email"],
                                   orderBy: ["contact.address.zip"])
        query.parameters = ["STATE": "MN"]
        let numRows = try verifyQuery(query) {(n: UInt64, row) in
            let i = Int(n - UInt64(1))
            XCTAssertEqual(row.documentID, expectedDocs[i])
            let zip: String? = row[0]
            let emails = row.value(at: 1) as? [String]
            XCTAssertEqual(zip, expectedZips[i])
            XCTAssertEqual(emails!, expectedEmails[i])
        }
        XCTAssertEqual(numRows, 3)
    }

    func verifyQuery(_ query: PredicateQuery, block: (UInt64, QueryRow) throws ->Void) throws -> UInt64 {
        var n: UInt64 = 0
        for row in try query.run() {
            n += 1
            try block(n, row)
        }
        return n
    }
}
