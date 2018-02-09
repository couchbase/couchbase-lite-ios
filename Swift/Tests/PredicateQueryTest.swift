//
//  PredicateQueryTest.swift
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
            let documentID :String? = row[0]
            let sequence :Int64 = row[1]
            XCTAssertEqual(documentID, expectedID);
            XCTAssertEqual(UInt64(sequence), n);
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
                let documentID :String? = row[0]
                let sequence :Int64 = row[1]
                XCTAssertEqual(documentID, "doc-009");
                XCTAssertEqual(sequence, 9);
            }
            XCTAssertEqual(n, 1);
            
            let item = ValueIndexItem.expression(Expression.property("name.first"))
            let index = Index.valueIndex().on(item)
            try db.createIndex(index, withName: "name.first")
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
