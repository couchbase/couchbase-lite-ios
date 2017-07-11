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
    
    @discardableResult  func createDoc(numbered i: (Int), of number: (Int)) throws -> Document {
        let doc = createDocument("doc\(i)")
        doc.set(i, forKey: "number1")
        doc.set(number - i, forKey: "number2")
        try saveDocument(doc)
        return doc
    }
    
    @discardableResult func loadNumbers(_ num: Int) throws -> [[String: Any]] {
        var numbers:[[String: Any]] = []
        try db.inBatch {
            for i in 1...num {
                let doc = try createDoc(numbered: i, of: num)
                numbers.append(doc.toDictionary())
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
                let props = row.document.toDictionary()
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
        try loadJSONResource(name: "names_100")
        
        let q = Query.select().from(DataSource.database(db))
        let numRows = try verifyQuery(q) { (n, row) in
            let expectedID = String(format: "doc-%03llu", n);
            XCTAssertEqual(row.documentID, expectedID);
            XCTAssertEqual(row.sequence, n);
            let doc = row.document;
            XCTAssertEqual(doc.id, expectedID);
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
        let doc1 = createDocument("doc1")
        doc1.set("Scott", forKey: "name")
        doc1.set(NSNull(), forKey: "address")
        try saveDocument(doc1)
        
        let doc2 = createDocument("doc1")
        doc2.set("Tiger", forKey: "name")
        doc2.set("address", forKey: "123 1st ave.")
        try saveDocument(doc2)
        
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
                    XCTAssertEqual(doc.id, row.documentID)
                }
            })
            XCTAssertEqual(Int(numRows), expectedDocs.count);
        }
    }
    
    
    func testWhereIs() throws {
        let doc1 = Document()
        doc1.set("string", forKey: "string")
        try saveDocument(doc1)
        
        var q = Query.select().from(DataSource.database(db)).where(
            Expression.property("string").is("string"))
        var numRows = try verifyQuery(q) { (n, row) in
            let doc = row.document
            XCTAssertEqual(doc.id, doc1.id);
            XCTAssertEqual(doc.string(forKey: "string")!, "string");
        }
        XCTAssertEqual(numRows, 1);
        
        q = Query.select().from(DataSource.database(db)).where(
            Expression.property("string").isNot("string1"))
        numRows = try verifyQuery(q) { (n, row) in
            let doc = row.document
            XCTAssertEqual(doc.id, doc1.id);
            XCTAssertEqual(doc.string(forKey: "string")!, "string");
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
        try loadJSONResource(name: "names_100")
        
        let w = Expression.property("name.first").like("%Mar%")
        let q = Query
            .select()
            .from(DataSource.database(db))
            .where(w)
            .orderBy(Ordering.property("name.first").ascending())
        
        var firstNames: [String] = []
        let numRows = try verifyQuery(q, block: { (n, row) in
            let doc = row.document
            let v: String? = doc.dictionary(forKey: "name")?.string(forKey: "first")
            if let firstName = v {
                firstNames.append(firstName)
            }
        })
        XCTAssertEqual(numRows, 5);
        XCTAssertEqual(firstNames.count, 5);
    }
    
    
    func testWhereIn() throws {
        try loadJSONResource(name: "names_100")
        let expected = ["Marcy", "Margaretta", "Margrett", "Marlen", "Maryjo"]
        let w = Expression.property("name.first").in(expected)
        let o = Ordering.property("name.first")
        let q = Query.select().from(DataSource.database(db)).where(w).orderBy(o)
        let numRows = try verifyQuery(q, block: { (n, row) in
            let firstName = expected[Int(n)-1]
            XCTAssertEqual(row.document.dictionary(forKey: "name")!.string(forKey: "first")!, firstName)
        })
        XCTAssertEqual(Int(numRows), expected.count);
    }
    
    
    func failingTestWhereRegex() throws {
        // https://github.com/couchbase/couchbase-lite-ios/issues/1668
        try loadJSONResource(name: "names_100")
        
        let w = Expression.property("name.first").regex("^Mar.*")
        let q = Query
            .select()
            .from(DataSource.database(db))
            .where(w)
            .orderBy(Ordering.property("name.first").ascending())
        
        var firstNames: [String] = []
        let numRows = try verifyQuery(q, block: { (n, row) in
            let doc = row.document
            let v: String? = doc.dictionary(forKey: "name")?.string(forKey: "first")
            if let firstName = v {
                firstNames.append(firstName)
            }
        })
        XCTAssertEqual(numRows, 5);
        XCTAssertEqual(firstNames.count, 5);
    }
    
    
    func testWhereMatch() throws {
        try loadJSONResource(name: "sentences")
        
        try db.createIndex(["sentence"], options:
            IndexOptions.fullTextIndex(language: nil, ignoreDiacritics: false))
        
        let w = Expression.property("sentence").match("'Dummie woman'")
        let o = Ordering.expression(Expression.property("rank(sentence)")).descending()
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
        try loadJSONResource(name: "names_100")
        
        for ascending in [true, false] {
            var o: Ordering;
            if (ascending) {
                o = Ordering.expression(Expression.property("name.first")).ascending()
            } else {
                o = Ordering.expression(Expression.property("name.first")).descending()
            }
            
            let q = Query.select().from(DataSource.database(db)).orderBy(o)
            var firstNames: [String] = []
            let numRows = try verifyQuery(q, block: { (n, row) in
                let doc = row.document
                if let firstName = doc.dictionary(forKey: "name")?.string(forKey: "first") {
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
        let doc1 = Document()
        doc1.set(1, forKey: "number")
        try saveDocument(doc1)
        
        let doc2 = Document()
        doc2.set(1, forKey: "number")
        try saveDocument(doc2)
        
        let q = Query.selectDistinct().from(DataSource.database(db))
        let numRow = try verifyQuery(q, block: { (n, row) in
            XCTAssertEqual(row.documentID, doc1.id)
        })
        XCTAssertEqual(numRow, 1)
    }
    
    
    func testJoin() throws {
        try loadNumbers(100)
        
        let doc = createDocument("joinme")
        doc.set(42, forKey: "theone")
        try saveDocument(doc)
        
        let q = Query
            .select()
            .from(DataSource.database(db).as("main"))
            .join(
                Join.join(DataSource.database(db).as("secondary"))
                    .on(Expression.property("number1").from("main")
                        .equalTo(Expression.property("theone").from("secondary"))))
        
        let numRow = try verifyQuery(q, block: { (n, row) in
            XCTAssertEqual(row.document.int(forKey: "number1"), 42)
        })
        XCTAssertEqual(numRow, 1)
    }
    
    
    func testAggregateFunctions() throws {
        try loadNumbers(100)
        
        let AVG = SelectResult.expression(Function.avg(Expression.property("number1")))
        let CNT = SelectResult.expression(Function.count(Expression.property("number1")))
        let MIN = SelectResult.expression(Function.min(Expression.property("number1")))
        let MAX = SelectResult.expression(Function.max(Expression.property("number1")))
        let SUM = SelectResult.expression(Function.sum(Expression.property("number1")))
        
        let q = Query
            .select(AVG, CNT, MIN, MAX, SUM)
            .from(DataSource.database(db))
        
        let numRow = try verifyQuery(q, block: { (n, row) in
            XCTAssertEqual(row.value(at: 0) as! Double, 50.5)
            XCTAssertEqual(row.value(at: 1) as! Int, 100)
            XCTAssertEqual(row.value(at: 2) as! Int , 1)
            XCTAssertEqual(row.value(at: 3) as! Int, 100)
            XCTAssertEqual(row.value(at: 4) as! Int, 5050)
        })
        XCTAssertEqual(numRow, 1)
    }
    
    
    func testGroupBy() throws {
        var expectedStates  = ["AL",    "CA",    "CO",    "FL",    "IA"]
        var expectedCounts  = [1,       6,       1,       1,       3]
        var expectedMaxZips = ["35243", "94153", "81223", "33612", "50801"]
        
        try loadJSONResource(name: "names_100")
        
        let STATE  = Expression.property("contact.address.state");
        let COUNT  = Function.count(1)
        let MAXZIP = Function.max(Expression.property("contact.address.zip"))
        let GENDER = Expression.property("gender")
        
        let RES_STATE  = SelectResult.expression(STATE)
        let RES_COUNT  = SelectResult.expression(COUNT)
        let RES_MAXZIP = SelectResult.expression(MAXZIP)
        
        var q = Query
            .select(RES_STATE, RES_COUNT, RES_MAXZIP)
            .from(DataSource.database(db))
            .where(GENDER.equalTo("female"))
            .groupBy(STATE)
            .orderBy(Ordering.expression(STATE))
        
        var numRow = try verifyQuery(q, block: { (n, row) in
            let state = row.value(at: 0) as! String
            let count = row.value(at: 1) as! Int
            let maxzip = row.value(at: 2) as! String
            
            let i: Int = Int(n-1)
            if i < expectedStates.count {
                XCTAssertEqual(state, expectedStates[i])
                XCTAssertEqual(count, expectedCounts[i])
                XCTAssertEqual(maxzip, expectedMaxZips[i])
            }
        })
        XCTAssertEqual(numRow, 31)
        
        // With Having
        expectedStates  = ["CA",    "IA",    "IN"]
        expectedCounts  = [6,       3,       2]
        expectedMaxZips = ["94153", "50801", "47952"]
        
        q = Query
            .select(RES_STATE, RES_COUNT, RES_MAXZIP)
            .from(DataSource.database(db))
            .where(GENDER.equalTo("female"))
            .groupBy(STATE)
            .having(COUNT.greaterThan(1))
            .orderBy(Ordering.expression(STATE))
        
        numRow = try verifyQuery(q, block: { (n, row) in
            let state = row.value(at: 0) as! String
            let count = row.value(at: 1) as! Int
            let maxzip = row.value(at: 2) as! String
            
            let i: Int = Int(n-1)
            if i < expectedStates.count {
                XCTAssertEqual(state, expectedStates[i])
                XCTAssertEqual(count, expectedCounts[i])
                XCTAssertEqual(maxzip, expectedMaxZips[i])
            }
        })
        XCTAssertEqual(numRow, 15)
    }
    
    
    func testParameters() throws {
        try loadNumbers(10)
        
        let NUMBER1  = Expression.property("number1")
        let PARAM_N1 = Expression.parameter("num1")
        let PARAM_N2 = Expression.parameter("num2")
        
        let q = Query
            .select(SelectResult.expression(NUMBER1))
            .from(DataSource.database(db))
            .where(NUMBER1.between(PARAM_N1, and: PARAM_N2))
            .orderBy(Ordering.expression(NUMBER1))
        
        q.parameters.set(2, forName: "num1")
        q.parameters.set(5, forName: "num2")
        
        let expectedNumbers = [2, 3, 4, 5]
        let numRow = try verifyQuery(q, block: { (n, row) in
            let number = row.value(at: 0) as! Int
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 4)
    }
    
    
    func testMeta() throws {
        try loadNumbers(5)
        
        let DOC_ID  = Expression.meta().documentID
        let DOC_SEQ = Expression.meta().sequence
        let NUMBER1 = Expression.property("number1")
        
        let RES_DOC_ID  = SelectResult.expression(DOC_ID)
        let RES_DOC_SEQ = SelectResult.expression(DOC_SEQ)
        let RES_NUMBER1 = SelectResult.expression(NUMBER1)
        
        let q = Query
            .select(RES_DOC_ID, RES_DOC_SEQ, RES_NUMBER1)
            .from(DataSource.database(db))
            .orderBy(Ordering.expression(DOC_SEQ))
        
        let expectedDocIDs  = ["doc1", "doc2", "doc3", "doc4", "doc5"]
        let expectedSeqs    = [1, 2, 3, 4, 5]
        let expectedNumbers = [1, 2, 3, 4, 5]
        
        let numRow = try verifyQuery(q, block: { (n, row) in
            let docID = row.value(at: 0) as! String
            let seq = row.value(at: 1) as! Int
            let number = row.value(at: 2) as! Int
            XCTAssertEqual(docID, expectedDocIDs[Int(n-1)])
            XCTAssertEqual(seq, expectedSeqs[Int(n-1)])
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 5)
    }
    
    
    func testLimit() throws {
        try loadNumbers(10)
        
        let NUMBER1  = Expression.property("number1")
        
        var q = Query
            .select(SelectResult.expression(NUMBER1))
            .from(DataSource.database(db))
            .orderBy(Ordering.expression(NUMBER1))
            .limit(5)
        
        var expectedNumbers = [1, 2, 3, 4, 5]
        var numRow = try verifyQuery(q, block: { (n, row) in
            let number = row.value(at: 0) as! Int
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 5)
        
        q = Query
            .select(SelectResult.expression(NUMBER1))
            .from(DataSource.database(db))
            .orderBy(Ordering.expression(NUMBER1))
            .limit(Expression.parameter("LIMIT_NUM"))
        q.parameters.set(3, forName: "LIMIT_NUM")
        
        expectedNumbers = [1, 2, 3]
        numRow = try verifyQuery(q, block: { (n, row) in
            let number = row.value(at: 0) as! Int
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 3)
    }
    
    
    func testLimitOffset() throws {
        try loadNumbers(10)
        
        let NUMBER1  = Expression.property("number1")
        
        var q = Query
            .select(SelectResult.expression(NUMBER1))
            .from(DataSource.database(db))
            .orderBy(Ordering.expression(NUMBER1))
            .limit(5, offset: 3)
        
        var expectedNumbers = [4, 5, 6, 7, 8]
        var numRow = try verifyQuery(q, block: { (n, row) in
            let number = row.value(at: 0) as! Int
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 5)
        
        q = Query
            .select(SelectResult.expression(NUMBER1))
            .from(DataSource.database(db))
            .orderBy(Ordering.expression(NUMBER1))
            .limit(Expression.parameter("LIMIT_NUM"), offset: Expression.parameter("OFFSET_NUM"))
        q.parameters.set(3, forName: "LIMIT_NUM")
        q.parameters.set(5, forName: "OFFSET_NUM")
        
        expectedNumbers = [6, 7, 8]
        numRow = try verifyQuery(q, block: { (n, row) in
            let number = row.value(at: 0) as! Int
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 3)
    }
    
    
    func testLiveQuery() throws {
        try loadNumbers(100)
        var count = 0;
        let q = Query
            .select()
            .from(DataSource.database(db))
            .where(Expression.property("number1").lessThan(10))
            .orderBy(Ordering.property("number1"))
            .toLive()
        
        let x = expectation(description: "changes")
        
        let listener = q.addChangeListener { (change) in
            count = count + 1
            XCTAssertNotNil(change.query)
            XCTAssertNil(change.error)
            let rows =  Array(change.rows!)
            if count == 1 {
                XCTAssertEqual(rows.count, 9)
            } else {
                XCTAssertEqual(rows.count, 10)
                x.fulfill()
            }
        }
        
        q.start()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try! self.createDoc(numbered: -1, of: 100)
        }
        
        waitForExpectations(timeout: 2.0) { (error) in }
        
        q.removeChangeListener(listener)
        q.stop()
    }
    
    
    func testLiveQueryNoUpdate() throws {
        try loadNumbers(100);
        var count = 0;
        let q = Query
            .select()
            .from(DataSource.database(db))
            .where(Expression.property("number1").lessThan(10))
            .orderBy(Ordering.property("number1"))
            .toLive()
        
        let listener = q.addChangeListener { (change) in
            count = count + 1
            XCTAssertNotNil(change.query)
            XCTAssertNil(change.error)
            let rows =  Array(change.rows!)
            if count == 1 {
                XCTAssertEqual(rows.count, 9)
            } else {
                XCTFail("Unexpected update from LiveQuery")
            }
        }
        
        q.start()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try! self.createDoc(numbered: 111, of: 100)
        }
        
        let x = expectation(description: "timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            x.fulfill()
        }
        
        waitForExpectations(timeout: 5.0) { (error) in }
        
        XCTAssertEqual(count, 1)
        
        q.removeChangeListener(listener)
        q.stop()
    }
    
}
