//
//  QueryLegacyTest.swift
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

/// Minimal smoke tests for the deprecated Query APIs :
/// `DataSource.database(_:)`/`.as(_:)`, `Expression.isNullOrMissing()`/`notNullOrMissing()`,
/// `FullTextFunction.rank(_:)` (String) / `match(indexName:query:)`, `FullTextExpression`,
/// and the `SortOrder` typealias.
///
/// The goal is only to touch each deprecated entry point and confirm its basic behavior,
/// NOT to re-cover the full query test suites. The class is marked deprecated so calls to
/// the deprecated APIs below don't emit warnings.
@available(*, deprecated)
class QueryLegacyTest: CBLTestCase {

    // Local copy of QueryTest's helper (we subclass CBLTestCase, not the concrete QueryTest,
    // to avoid re-running the entire QueryTest suite via inheritance).
    let kDOCID = SelectResult.expression(Meta.id)

    // MARK: - DataSource.database(_:) / .as(_:)

    func testDataSourceDatabaseAndAlias() throws {
        let doc1 = createDocument("doc1")
        doc1.setValue("Scott", forKey: "name")
        try defaultCollection!.save(document: doc1)

        let doc2 = createDocument("doc2")
        doc2.setValue("Tiger", forKey: "name")
        try defaultCollection!.save(document: doc2)

        // DataSource.database(_:)
        let q = QueryBuilder.select(kDOCID).from(DataSource.database(db))
        var numRows = try verifyQuery(q) { (n, r) in }
        XCTAssertEqual(numRows, 2)

        // DataSource.database(_:).as(_:)
        let aliased = QueryBuilder.select(kDOCID).from(DataSource.database(db).as("main"))
        numRows = try verifyQuery(aliased) { (n, r) in }
        XCTAssertEqual(numRows, 2)
    }

    // MARK: - Expression.isNullOrMissing() / notNullOrMissing()

    func testIsNullOrMissing() throws {
        let doc1 = createDocument("doc1")
        doc1.setValue("Scott", forKey: "name")
        try defaultCollection!.save(document: doc1)

        let doc2 = createDocument("doc2")
        doc2.setValue("Tiger", forKey: "name")
        doc2.setValue("123 1st ave.", forKey: "address")
        try defaultCollection!.save(document: doc2)

        let name = Expression.property("name")
        let address = Expression.property("address")

        let tests: [(ExpressionProtocol, Int)] = [
            (name.isNullOrMissing(),     0),
            (name.notNullOrMissing(),    2),
            (address.isNullOrMissing(),  1),
            (address.notNullOrMissing(), 1),
        ]

        for (exp, expected) in tests {
            let q = QueryBuilder.select(kDOCID)
                .from(DataSource.collection(defaultCollection!))
                .where(exp)
            let numRows = try verifyQuery(q) { (n, r) in }
            XCTAssertEqual(Int(numRows), expected, "Failed case: \(exp)")
        }
    }

    // MARK: - FullTextFunction.rank(_:) (String) / match(indexName:query:)

    func testFullTextFunctionDeprecatedRankAndMatch() throws {
        try loadJSONResource(name: "sentences")

        let index = IndexBuilder.fullTextIndex(items: FullTextIndexItem.property("sentence"))
            .language(nil)
            .ignoreAccents(false)
        try defaultCollection!.createIndex(index, name: "sentence")

        let order = Ordering.expression(FullTextFunction.rank("sentence")).descending()
        let q = QueryBuilder
            .select([SelectResult.expression(Meta.id), SelectResult.property("sentence")])
            .from(DataSource.collection(defaultCollection!))
            .where(FullTextFunction.match(indexName: "sentence", query: "'Dummie woman'"))
            .orderBy([order])
        let numRows = try verifyQuery(q) { (n, r) in }
        XCTAssertEqual(numRows, 2)
    }

    // MARK: - FullTextExpression.index(_:).match(_:)

    func testFullTextExpression() throws {
        try loadJSONResource(name: "sentences")

        let index = IndexBuilder.fullTextIndex(items: FullTextIndexItem.property("sentence"))
            .language(nil)
            .ignoreAccents(false)
        try defaultCollection!.createIndex(index, name: "sentence")

        let sentence = FullTextExpression.index("sentence")
        let q = QueryBuilder
            .select([SelectResult.expression(Meta.id), SelectResult.property("sentence")])
            .from(DataSource.collection(defaultCollection!))
            .where(sentence.match("'Dummie woman'"))
        let numRows = try verifyQuery(q) { (n, r) in }
        XCTAssertEqual(numRows, 2)
    }

    // MARK: - SortOrder typealias

    func testSortOrderTypealias() throws {
        let doc1 = createDocument("doc1")
        doc1.setValue("Scott", forKey: "name")
        try defaultCollection!.save(document: doc1)

        let doc2 = createDocument("doc2")
        doc2.setValue("Tiger", forKey: "name")
        try defaultCollection!.save(document: doc2)

        // `SortOrder` is a deprecated public typealias for `QuerySortOrder`. It must be
        // module-qualified because it is ambiguous with Foundation.SortOrder.
        let order: CouchbaseLiteSwift.SortOrder = Ordering.property("name")
        let q = QueryBuilder.select(kDOCID)
            .from(DataSource.collection(defaultCollection!))
            .orderBy([order.ascending()])
        let numRows = try verifyQuery(q) { (n, r) in }
        XCTAssertEqual(numRows, 2)
    }

    // MARK: - Query.removeChangeListener(withToken:)

    func testRemoveQueryChangeListenerWithToken() throws {
        let q = QueryBuilder.select(kDOCID).from(DataSource.collection(defaultCollection!))

        let x = expectation(description: "query change")
        x.assertForOverFulfill = false
        let token = q.addChangeListener { (change) in
            XCTAssertNil(change.error)
            x.fulfill()
        }
        wait(for: [x], timeout: 5.0)

        // Remove using the deprecated API; should not crash.
        q.removeChangeListener(withToken: token)
    }
}
