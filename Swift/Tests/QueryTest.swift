//
//  QueryTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift

class QueryTest: CBLTestCase {
    
    func verifyQuery(_ query: Query, block: (UInt64, QueryRow) throws ->Void) throws -> UInt64 {
        var n: UInt64 = 0
        for row in try query.run() {
            n += 1
            try block(n, row)
        }
        return n
    }
    
    func loadNumbers(_ num: Int) throws -> [[String: Any]] {
        var numbers:[[String: Any]] = []
        try db.inBatch {
            for i in 1...num {
                let doc = db["doc\(i)"]
                doc["number1"] = i
                doc["number2"] = num - i
                try doc.save()
                numbers.append(doc.properties!)
            }
        }
        return numbers
    }
    
    func runTestWithNumbers(_ numbers: [[String: Any]], cases: [[Any]]) throws {
        for c in cases {
            let pred = NSPredicate(format: c[1] as! String)
            var result = numbers.filter { pred.evaluate(with: $0) };
            let total = result.count
            
            let w = c[0] as! Expression
            let q = Query.select().from(DataSource.database(db)).where(w)
            let rows = try verifyQuery(q, block: { (n, row) in
                let props = row.document.properties!
                let number1 = props["number1"] as! Int
                if let index = result.index(where: {($0["number1"] as! Int) == number1}) {
                    result.remove(at: index)
                }
            })
            XCTAssertEqual(result.count, 0);
            XCTAssertEqual(Int(rows), total);
        }
    }
    
    func testNoWhereQuery() throws {
        try loadJSONResource(resourceName: "names_100")
        
        let q = Query.select().from(DataSource.database(db))
        let numRows = try verifyQuery(q) { (n, row) in
            let expectedID = String(format: "doc-%03llu", n);
            XCTAssertEqual(row.documentID, expectedID);
            XCTAssertEqual(row.sequence, n);
            let doc = row.document;
            XCTAssertEqual(doc.documentID, expectedID);
            XCTAssertEqual(doc.sequence, n);
        }
        XCTAssertEqual(numRows, 100);
    }
    
    func testWhereComparison() throws {
        let n1 = Expression.property("number1")
        let cases = [
            [n1.lessThan(3), "number1 < 3"],
            [n1.notLessThan(3), "number1 >= 3"],
            [n1.lessThanOrEqualTo(3), "number1 <= 3"],
            [n1.notLessThanOrEqualTo(3), "number1 > 3"],
            [n1.greaterThan(6), "number1 > 6"],
            [n1.notGreaterThan(6), "number1 <= 6"],
            [n1.greaterThanOrEqualTo(6), "number1 >= 6"],
            [n1.notGreaterThanOrEqualTo(6), "number1 < 6"],
            [n1.equalTo(7), "number1 == 7"],
            [n1.notEqualTo(7), "number1 != 7"],
        ]
        let numbers = try loadNumbers(10)
        try runTestWithNumbers(numbers, cases: cases)
    }
    
    func testWhereArithmetic() throws {
        let n1 = Expression.property("number1")
        let n2 = Expression.property("number2")
        let cases = [
            [n1.multiply(2).greaterThan(8), "(number1 * 2) > 8"],
            [n1.divide(2).greaterThan(3), "(number1 / 2) > 3"],
            [n1.modulo(2).equalTo(0), "modulus:by:(number1, 2) == 0"],
            [n1.add(5).greaterThan(10), "(number1 + 5) > 10"],
            [n1.subtract(5).greaterThan(0), "(number1 - 5) > 0"],
            [n1.multiply(n2).greaterThan(10), "(number1 * number2) > 10"],
            [n2.divide(n1).greaterThan(3), "(number2 / number1) > 3"],
            [n2.modulo(n1).equalTo(0), "modulus:by:(number2, number1) == 0"],
            [n1.add(n2).equalTo(10), "(number1 + number2) == 10"],
            [n1.subtract(n2).greaterThan(0), "(number1 - number2) > 0"]
        ]
        let numbers = try loadNumbers(10)
        try runTestWithNumbers(numbers, cases: cases)
    }
    
    func testWhereAndOr() throws {
        let n1 = Expression.property("number1")
        let n2 = Expression.property("number2")
        let cases = [
            [n1.greaterThan(3).and(n2.greaterThan(3)), "number1 > 3 AND number2 > 3"],
            [n1.lessThan(3).or(n2.lessThan(3)), "number1 < 3 OR number2 < 3"]
        ]
        let numbers = try loadNumbers(10)
        try runTestWithNumbers(numbers, cases: cases)
    }
    
    func failingTestWhereCheckNull() throws {
        // https://github.com/couchbase/couchbase-lite-ios/issues/1670
        let doc1 = db.document(withID: "doc1")
        doc1["name"] = "Scott"
        doc1["address"] = NSNull()
        try doc1.save()
        
        let doc2 = db.document(withID: "doc2")
        doc2["name"] = "Tiger"
        doc2["address"] = "123 1st ave."
        try doc2.save()
        
        let name = Expression.property("name")
        let address = Expression.property("address")
        let age = Expression.property("age")
        let work = Expression.property("work")
        
        let tests: [[Any]] = [
            [name.notNull(), [doc1, doc2]],
            [name.isNull(), []],
            [address.notNull(), [doc2]],
            [address.isNull(), [doc1]],
            [age.notNull(), [doc2]],
            [age.isNull(), [doc1]],
            [work.notNull(), []],
            [work.isNull(), [doc1, doc2]]
        ]
        
        for test in tests {
            let exp = test[0] as! Expression
            let expectedDocs = test[1] as! [Document]
            let q = Query.select().from(DataSource.database(db)).where(exp)
            let numRows = try verifyQuery(q, block: { (n, row) in
                if (Int(n) <= expectedDocs.count) {
                    let doc = expectedDocs[Int(n)-1]
                    XCTAssertEqual(doc.documentID, row.documentID)
                }
            })
            XCTAssertEqual(Int(numRows), expectedDocs.count);
        }
    }
    
    func testWhereIs() throws {
        let doc1 = db.document()
        doc1["string"] = "string"
        try doc1.save()
        
        var q = Query.select().from(DataSource.database(db)).where(
            Expression.property("string").is("string"))
        var numRows = try verifyQuery(q) { (n, row) in
            let doc = row.document
            XCTAssertEqual(doc.documentID, doc1.documentID);
            XCTAssertEqual(doc["string"], "string");
        }
        XCTAssertEqual(numRows, 1);
        
        q = Query.select().from(DataSource.database(db)).where(
            Expression.property("string").isNot("string1"))
        numRows = try verifyQuery(q) { (n, row) in
            let doc = row.document
            XCTAssertEqual(doc.documentID, doc1.documentID);
            XCTAssertEqual(doc["string"], "string");
        }
        XCTAssertEqual(numRows, 1);
    }
    
    func testWhereBetween() throws {
        let n1 = Expression.property("number1")
        let cases = [
            [n1.between(3, and: 7), "number1 BETWEEN {3, 7}"]
        ]
        let numbers = try loadNumbers(10)
        try runTestWithNumbers(numbers, cases: cases)
    }
    
    func failingTestWhereLike() throws {
        // https://github.com/couchbase/couchbase-lite-ios/issues/1667
        try loadJSONResource(resourceName: "names_100")
        
        let w = Expression.property("name.first").like("%Mar%")
        let q = Query
            .select()
            .from(DataSource.database(db))
            .where(w)
            .orderBy(OrderBy.property("name.first").ascending())
        
        var firstNames: [String] = []
        let numRows = try verifyQuery(q, block: { (n, row) in
            let doc = row.document
            let v: String? = doc["name"]?["first"]
            if let firstName = v {
                firstNames.append(firstName)
            }
        })
        XCTAssertEqual(numRows, 5);
        XCTAssertEqual(firstNames.count, 5);
    }
    
    func testWhereIn() throws {
        try loadJSONResource(resourceName: "names_100")
        let expected = ["Marcy", "Margaretta", "Margrett", "Marlen", "Maryjo"]
        let w = Expression.property("name.first").in(expected)
        let o = OrderBy.property("name.first")
        let q = Query.select().from(DataSource.database(db)).where(w).orderBy(o)
        let numRows = try verifyQuery(q, block: { (n, row) in
            let firstName = expected[Int(n)-1]
            XCTAssertEqual(row.document["name"]!["first"], firstName)
        })
        XCTAssertEqual(Int(numRows), expected.count);
    }
    
    func failingTestWhereRegex() throws {
        // https://github.com/couchbase/couchbase-lite-ios/issues/1668
        try loadJSONResource(resourceName: "names_100")
        
        let w = Expression.property("name.first").regex("^Mar.*")
        let q = Query
            .select()
            .from(DataSource.database(db))
            .where(w)
            .orderBy(OrderBy.property("name.first").ascending())
        
        var firstNames: [String] = []
        let numRows = try verifyQuery(q, block: { (n, row) in
            let doc = row.document
            let v: String? = doc["name"]?["first"]
            if let firstName = v {
                firstNames.append(firstName)
            }
        })
        XCTAssertEqual(numRows, 5);
        XCTAssertEqual(firstNames.count, 5);
    }
    
    func testWhereMatch() throws {
        try loadJSONResource(resourceName: "sentences")
        
        try db.createIndex(["sentence"], options:
            IndexOptions.fullTextIndex(language: nil, ignoreDiacritics: false))
        
        let w = Expression.property("sentence").match("'Dummie woman'")
        let o = OrderBy.expression(Expression.property("rank(sentence)")).descending()
        let q = Query.select().from(DataSource.database(db)).where(w).orderBy(o)
        let numRows = try verifyQuery(q) { (n, row) in
            let ftsRow = row as! FullTextQueryRow
            let text = ftsRow.fullTextMatched
            XCTAssert(text != nil)
            XCTAssert(text!.contains("Dummie"))
            XCTAssert(text!.contains("woman"))
            XCTAssertEqual(ftsRow.matchCount, 2)
        }
        XCTAssertEqual(numRows, 2)
    }

    func testOrderBy() throws {
        try loadJSONResource(resourceName: "names_100")
        
        for ascending in [true, false] {
            var o: OrderBy;
            if (ascending) {
                o = OrderBy.expression(Expression.property("name.first")).ascending()
            } else {
                o = OrderBy.expression(Expression.property("name.first")).descending()
            }
            
            let q = Query.select().from(DataSource.database(db)).orderBy(o)
            var firstNames: [String] = []
            let numRows = try verifyQuery(q, block: { (n, row) in
                let doc = row.document
                if let firstName: String = doc["name"]?["first"] {
                    firstNames.append(firstName)
                }
            })
            
            XCTAssertEqual(numRows, 100)
            XCTAssertEqual(Int(numRows), firstNames.count)
            
            let sorted = firstNames.sorted(by: { s1, s2 in return ascending ?  s1 < s2 : s1 > s2 })
            XCTAssertEqual(firstNames, sorted);
        }
    }
    
    func failingTestSelectDistinct() throws {
        // https://github.com/couchbase/couchbase-lite-ios/issues/1669
        let doc1 = db.document()
        doc1["number"] = 1
        try doc1.save()
        
        let doc2 = db.document()
        doc2["number"] = 1
        try doc1.save()
        
        let q = Query.selectDistinct().from(DataSource.database(db))
        let numRow = try verifyQuery(q, block: { (n, row) in
            XCTAssertEqual(row.documentID, doc1.documentID)
        })
        XCTAssertEqual(numRow, 1)
    }
}
