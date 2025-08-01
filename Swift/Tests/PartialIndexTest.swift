//
//  PartialIndexTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
@testable import CouchbaseLiteSwift

/// Test Spec v1.0.3:
/// https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0007-Partial-Index.md

class PartialIndexTest: CBLTestCase {
    
    /// 1. TestCreatePartialValueIndex
    /// Description
    ///     Test that a partial value index is successfully created.
    /// Steps
    ///     1. Create a partial value index named "numIndex" in the default collection.
    ///         - expression: "num"
    ///         - where: "type = 'number'"
    ///     2. Check that the index is successfully created.
    ///     3. Create a query object with an SQL++ string:
    ///         - SELECT *
    ///           FROM _
    ///           WHERE type = 'number' AND num > 1000
    ///     4. Get the query plan from the query object and check that the plan contains "USING INDEX numIndex" string.
    ///     5. Create a query object with an SQL++ string:
    ///         - SELECT *
    ///           FROM _
    ///           WHERE type = 'foo' AND num > 1000
    ///     6. Get the query plan from the query object and check that the plan doesn't contain "USING INDEX numIndex" string.
    func testCreatePartialValueIndex() throws {
        let collection = try db.defaultCollection()
        
        let config = ValueIndexConfiguration(["num"], where: "type='number'")
        try collection.createIndex(withName: "numIndex", config: config)

        var sql = "SELECT * FROM _ WHERE type = 'number' AND num > 1000"
        var q = try db.createQuery(sql)
        XCTAssert(try isUsingIndex(named: "numIndex", for: q))
        
        sql = "SELECT * FROM _ WHERE type = 'foo' AND num > 1000"
        q = try db.createQuery(sql)
        XCTAssertFalse(try isUsingIndex(named: "numIndex", for: q))
    }
    
    /// 2. TestCreatePartialFullTextIndex
    /// Description
    ///     Test that a partial full text index is successfully created.
    /// Steps
    ///     1. Create following two documents with the following bodies in the default collection.
    ///         - { "content" : "Couchbase Lite is a database." }
    ///         - { "content" : "Couchbase Lite is a NoSQL syncable database." }
    ///     2. Create a partial value index named "numIndex" in the default collection.
    ///         - expression: "content"
    ///         - where: "length(content) > 30"
    ///     3. Check that the index is successfully created.
    ///     4. Create a query object with an SQL++ string:
    ///         - SELECT content
    ///           FROM _
    ///           WHERE match(contentIndex, "database")
    ///     4.  Execute the query and check that:
    ///         - The query returns the second docume
    ///     5. Create a query object with an SQL++ string:
    ///         - There is one result returned
    ///         - The returned content is "Couchbase Lite is a NoSQL syncable database."
    func testCreatePartialFullTextIndex() throws {
        let collection = try db.defaultCollection()
        let json1 = "{\"content\":\"Couchbase Lite is a database.\"}"
        let json2 = "{\"content\":\"Couchbase Lite is a NoSQL syncable database.\"}"
        
        try collection.save(document: MutableDocument(json: json1))
        try collection.save(document: MutableDocument(json: json2))
        
        let config = FullTextIndexConfiguration(["content"], where: "length(content)>30")
        try collection.createIndex(withName: "contentIndex", config: config)

        let sql = "SELECT content FROM _ WHERE match(contentIndex, 'database')"
        let q = try db.createQuery(sql)
        let result = try q.execute().allResults()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].toJSON(), json2)
    }
}
