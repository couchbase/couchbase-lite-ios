//
//  QueryTest.swift
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

@testable import CouchbaseLiteSwift

class QueryTest: CBLTestCase {
    
    let kDOCID = SelectResult.expression(Meta.id)
    
    let kSEQUENCE = SelectResult.expression(Meta.sequence)
    
    let kTestDate = "2017-01-01T00:00:00.000Z"
    
    let kTestBlob = "i'm blob"
    
    @discardableResult  func createDoc(numbered i: (Int), of number: (Int)) throws -> Document {
        let doc = createDocument("doc\(i)")
        doc.setValue(i, forKey: "number1")
        doc.setValue(number - i, forKey: "number2")
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
            
            let w = c[0] as! ExpressionProtocol
            let q = QueryBuilder.select(kDOCID).from(DataSource.collection(defaultCollection!)).where(w)
            let rows = try verifyQuery(q, block: { (n, r) in
                let doc = try defaultCollection!.document(id: r.string(at: 0)!)!
                let props = doc.toDictionary()
                let number1 = props["number1"] as! Int
                if let index = result.firstIndex(where: {($0["number1"] as! Int) == number1}) {
                    result.remove(at: index)
                }
            })
            XCTAssertEqual(result.count, 0);
            XCTAssertEqual(Int(rows), total);
        }
    }
    
    func testQuerySelectItemsMax() throws {
        let doc = MutableDocument(id: "docID").setString("value", forKey: "key")
        try! self.defaultCollection!.save(document: doc)
        
        /**
         Add one more query item, e.g., '`32`' before `key`, will fail to return the
            - `r.string(forKey:)`
            - `r.value(forKey:)`
            - `r.toJSON()` // empty
         */
        let query =
"""
            select
                `1`,`2`,`3`,`4`,`5`,`6`,`7`,`8`,`9`,`10`,`11`,`12`,
                `13`,`14`,`15`,`16`,`17`,`18`,`19`,`20`,`21`,`22`,`23`,`24`,
                `25`,`26`,`27`,`28`,`29`,`30`,`31`,`32`,
                `1`,`2`,`3`,`4`,`5`,`6`,`7`,`8`,`9`,`10`,`11`,`12`,
                `13`,`14`,`15`,`16`,`17`,`18`,`19`,`20`,`21`,`22`,`23`,`24`,
                `25`,`26`,`27`,`28`,`29`,`30`,`31`, `key` from _ limit 1
"""
        let q = try self.db.createQuery(query)
        let rs: ResultSet = try q.execute()
        guard let r = rs.allResults().first else {
            XCTFail("No result!")
            return
        }
        
        XCTAssertEqual(r.toJSON(), "{\"key\":\"value\"}")
        XCTAssertEqual(r.string(forKey: "key"), "value")
        XCTAssertEqual(r.string(at: 63), "value")
        XCTAssertEqual(r.value(at: 63) as! String, "value")
        XCTAssertEqual(r.value(forKey: "key") as! String, "value")
    }
    
    func testNoWhereQuery() throws {
        try loadJSONResource(name: "names_100")
        
        let q = QueryBuilder.select(kDOCID).from(DataSource.collection(defaultCollection!))
        let numRows = try verifyQuery(q) { (n, r) in
            let doc = try defaultCollection!.document(id: r.string(at: 0)!)!
            let expectedID = String(format: "doc-%03llu", n);
            XCTAssertEqual(doc.id, expectedID);
            XCTAssertEqual(doc.sequence, n);
            XCTAssertEqual(doc.id, expectedID);
            XCTAssertEqual(doc.sequence, n);
        }
        XCTAssertEqual(numRows, 100);
    }
    
    func testWhereComparison() throws {
        let n1 = Expression.property("number1")
        let cases = [
            [n1.lessThan(Expression.int(3)), "number1 < 3"],
            [n1.lessThanOrEqualTo(Expression.int(3)), "number1 <= 3"],
            [n1.greaterThan(Expression.int(6)), "number1 > 6"],
            [n1.greaterThanOrEqualTo(Expression.int(6)), "number1 >= 6"],
            [n1.equalTo(Expression.int(7)), "number1 == 7"],
            [n1.notEqualTo(Expression.int(7)), "number1 != 7"],
        ]
        let numbers = try loadNumbers(10)
        try runTestWithNumbers(numbers, cases: cases)
    }
    
    func testWhereArithmetic() throws {
        let n1 = Expression.property("number1")
        let n2 = Expression.property("number2")
        let cases = [
            [n1.multiply(Expression.int(2)).greaterThan(Expression.int(8)), "(number1 * 2) > 8"],
            [n1.divide(Expression.int(2)).greaterThan(Expression.int(3)), "(number1 / 2) > 3"],
            [n1.modulo(Expression.int(2)).equalTo(Expression.int(0)), "modulus:by:(number1, 2) == 0"],
            [n1.add(Expression.int(5)).greaterThan(Expression.int(10)), "(number1 + 5) > 10"],
            [n1.subtract(Expression.int(5)).greaterThan(Expression.int(0)), "(number1 - 5) > 0"],
            [n1.multiply(n2).greaterThan(Expression.int(10)), "(number1 * number2) > 10"],
            [n2.divide(n1).greaterThan(Expression.int(3)), "(number2 / number1) > 3"],
            [n2.modulo(n1).equalTo(Expression.int(0)), "modulus:by:(number2, number1) == 0"],
            [n1.add(n2).equalTo(Expression.int(10)), "(number1 + number2) == 10"],
            [n1.subtract(n2).greaterThan(Expression.int(0)), "(number1 - number2) > 0"]
        ]
        let numbers = try loadNumbers(10)
        try runTestWithNumbers(numbers, cases: cases)
    }
    
    func testWhereAndOr() throws {
        let n1 = Expression.property("number1")
        let n2 = Expression.property("number2")
        let cases = [
            [n1.greaterThan(Expression.int(3)).and(n2.greaterThan(Expression.int(3))), "number1 > 3 AND number2 > 3"],
            [n1.lessThan(Expression.int(3)).or(n2.lessThan(Expression.int(3))), "number1 < 3 OR number2 < 3"]
        ]
        let numbers = try loadNumbers(10)
        try runTestWithNumbers(numbers, cases: cases)
    }
    
    func testWhereNullOrMissing() throws {
        let doc1 = createDocument("doc1")
        doc1.setValue("Scott", forKey: "name")
        doc1.setValue(nil, forKey: "address")
        try saveDocument(doc1)
        
        let doc2 = createDocument("doc2")
        doc2.setValue("Tiger", forKey: "name")
        doc2.setValue("123 1st ave", forKey: "address")
        doc2.setValue(20, forKey: "age")
        try saveDocument(doc2)
        
        let name = Expression.property("name")
        let address = Expression.property("address")
        let age = Expression.property("age")
        let work = Expression.property("work")
        
        
        let tests: [[Any]] = [
            [name.isNotValued(), []],
            [name.isValued(), [doc1, doc2]],
            [address.isNotValued(), [doc1]],
            [address.isValued(), [doc2]],
            [age.isNotValued(), [doc1]],
            [age.isValued(), [doc2]],
            [work.isNotValued(), [doc1, doc2]],
            [work.isValued(), []]
        ]
        
        for test in tests {
            let exp = test[0] as! ExpressionProtocol
            let expectedDocs = test[1] as! [Document]
            let q = QueryBuilder.select(kDOCID).from(DataSource.collection(defaultCollection!)).where(exp)
            let numRows = try verifyQuery(q, block: { (n, r) in
                if (Int(n) <= expectedDocs.count) {
                    let docID = r.string(at: 0)!
                    XCTAssertEqual(docID, expectedDocs[Int(n)-1].id)
                }
            })
            XCTAssertEqual(Int(numRows), expectedDocs.count);
        }
    }
    
    func testWhereIs() throws {
        let doc1 = MutableDocument()
        doc1.setValue("string", forKey: "string")
        try saveDocument(doc1)
        
        var q = QueryBuilder.select(kDOCID).from(DataSource.collection(defaultCollection!)).where(
            Expression.property("string").is(Expression.string("string")))
        var numRows = try verifyQuery(q) { (n, r) in
            let doc = try defaultCollection!.document(id: r.string(at: 0)!)!
            XCTAssertEqual(doc.id, doc1.id);
            XCTAssertEqual(doc.string(forKey: "string")!, "string");
        }
        XCTAssertEqual(numRows, 1);
        
        q = QueryBuilder.select(kDOCID).from(DataSource.collection(defaultCollection!)).where(
            Expression.property("string").isNot(Expression.string("string1")))
        numRows = try verifyQuery(q) { (n, r) in
            let doc = try defaultCollection!.document(id: r.string(at: 0)!)!
            XCTAssertEqual(doc.id, doc1.id);
            XCTAssertEqual(doc.string(forKey: "string")!, "string");
        }
        XCTAssertEqual(numRows, 1);
    }
    
    func testWhereBetween() throws {
        let n1 = Expression.property("number1")
        let cases = [
            [n1.between(Expression.int(3), and: Expression.int(7)), "number1 BETWEEN {3, 7}"]
        ]
        let numbers = try loadNumbers(10)
        try runTestWithNumbers(numbers, cases: cases)
    }
    
    func testWhereLike() throws {
        try loadJSONResource(name: "names_100")
        
        let w = Expression.property("name.first").like(Expression.string("%Mar%"))
        let q = QueryBuilder
            .select(kDOCID)
            .from(DataSource.collection(defaultCollection!))
            .where(w)
            .orderBy(Ordering.property("name.first").ascending())
        
        var firstNames: [String] = []
        let numRows = try verifyQuery(q, block: { (n, r) in
            let doc = try defaultCollection!.document(id: r.string(at: 0)!)!
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
        let names = expected.map() { Expression.string($0) }
        let w = Expression.property("name.first").in(names)
        let o = Ordering.property("name.first")
        let q = QueryBuilder.select(kDOCID).from(DataSource.collection(defaultCollection!)).where(w).orderBy(o)
        let numRows = try verifyQuery(q, block: { (n, r) in
            let doc = try defaultCollection!.document(id: r.string(at: 0)!)!
            let firstName = expected[Int(n)-1]
            XCTAssertEqual(doc.dictionary(forKey: "name")!.string(forKey: "first")!, firstName)
        })
        XCTAssertEqual(Int(numRows), expected.count);
    }
    
    func testWhereRegex() throws {
        // https://github.com/couchbase/couchbase-lite-ios/issues/1668
        try loadJSONResource(name: "names_100")
        
        let w = Expression.property("name.first").regex(Expression.string("^Mar.*"))
        let q = QueryBuilder
            .select(kDOCID)
            .from(DataSource.collection(defaultCollection!))
            .where(w)
            .orderBy(Ordering.property("name.first").ascending())
        
        var firstNames: [String] = []
        let numRows = try verifyQuery(q, block: { (n, r) in
            let doc = try defaultCollection!.document(id: r.string(at: 0)!)!
            let v: String? = doc.dictionary(forKey: "name")?.string(forKey: "first")
            if let firstName = v {
                firstNames.append(firstName)
            }
        })
        XCTAssertEqual(numRows, 5);
        XCTAssertEqual(firstNames.count, 5);
    }
    
    // https://issues.couchbase.com/browse/CBL-2036
    func testFTSQueryOnDBNameWithHyphen() throws {
        try Database.delete(withName: "cbl-test")
        let db2 = try Database(name: "cbl-test")
        
        let doc = MutableDocument()
        doc.setValue("Dummie woman", forKey: "sentence")
        try db2.defaultCollection().save(document: doc)
        
        let doc2 = MutableDocument()
        doc2.setValue("Dummie man", forKey: "sentence")
        try db2.defaultCollection().save(document:doc2)
        
        let fts_s = FullTextIndexItem.property("sentence")
        let index = IndexBuilder.fullTextIndex(items: fts_s)
            .language(nil)
            .ignoreAccents(false)
        try db2.defaultCollection().createIndex(index, name: "sentence")
        
        let plainIndex = Expression.fullTextIndex("sentence")
        let q = QueryBuilder.select([SelectResult.expression(Meta.id)])
            .from(DataSource.collection(try db2.defaultCollection()))
            .where(FullTextFunction.match(plainIndex, query: "'woman'"))
        let numRows = try verifyQuery(q) { (n, r) in }
        XCTAssertEqual(numRows, 1)
    }
    
    func testFTSMatch() throws {
        let doc = MutableDocument()
        doc.setValue("Dummie woman", forKey: "sentence")
        try defaultCollection!.save(document: doc)
        
        let doc2 = MutableDocument()
        doc2.setValue("Dummie man", forKey: "sentence")
        try defaultCollection!.save(document: doc2)
        
        let fts_s = FullTextIndexItem.property("sentence")
        let index = IndexBuilder.fullTextIndex(items: fts_s)
            .language(nil)
            .ignoreAccents(false)
        try defaultCollection!.createIndex(index, name: "sentence")

        // JSON Query
        let plainIndex = Expression.fullTextIndex("sentence")
        var q = QueryBuilder.select([SelectResult.expression(Meta.id)])
            .from(DataSource.collection(defaultCollection!))
            .where(FullTextFunction.match(plainIndex, query: "'woman'"))
        var numRows = try verifyQuery(q) { (n, r) in }
        XCTAssertEqual(numRows, 1)
        
        q = QueryBuilder.select([SelectResult.expression(Meta.id)])
            .from(DataSource.collection(defaultCollection!))
            .where(FullTextFunction.match(plainIndex, query: "\"woman\""))
        numRows = try verifyQuery(q) { (n, r) in }
        XCTAssertEqual(numRows, 1)
        
        // N1QL Query
        var q2 = try db.createQuery("SELECT _id FROM `\(db.name)` WHERE MATCH(sentence, 'woman')")
        numRows = try verifyQuery(q2) { (n, r) in }
        XCTAssertEqual(numRows, 1)
        
        q2 = try db.createQuery("SELECT _id FROM `\(db.name)` WHERE MATCH(sentence, \"woman\")")
        numRows = try verifyQuery(q2) { (n, r) in }
        XCTAssertEqual(numRows, 1)
    }
    
    func testWhereMatch() throws {
        try loadJSONResource(name: "sentences")
        
        let fts_s = FullTextIndexItem.property("sentence")
        let index = IndexBuilder.fullTextIndex(items: fts_s)
            .language(nil)
            .ignoreAccents(false)
        try defaultCollection!.createIndex(index, name: "sentence")

        try checkFullTextMatchQuery([kDOCID, SelectResult.property("sentence")],
                              ds: DataSource.collection(defaultCollection!))
        
        var s = Expression.property("sentence").from("db")
        s = Expression.property("sentence").from("db")
        try checkFullTextMatchQuery([kDOCID, SelectResult.expression(s)],
                              ds: DataSource.collection(defaultCollection!).as("db"))
        
    }
    
    func checkFullTextMatchQuery(_ select: [SelectResultProtocol],
                           ds: DataSourceProtocol) throws {
        let plainIndex = Expression.fullTextIndex("sentence")
        let sentence = FullTextFunction.match(plainIndex, query: "'Dummie woman'")
        let o = Ordering.expression(FullTextFunction.rank(plainIndex)).descending()
        let q = QueryBuilder.select(select)
            .from(ds)
            .where(sentence)
            .orderBy(o)
        let numRows = try verifyQuery(q) { (n, r) in }
        XCTAssertEqual(numRows, 2)
    }

    func testOrderBy() throws {
        try loadJSONResource(name: "names_100")
        
        for ascending in [true, false] {
            var o: OrderingProtocol;
            if (ascending) {
                o = Ordering.expression(Expression.property("name.first")).ascending()
            } else {
                o = Ordering.expression(Expression.property("name.first")).descending()
            }
            
            let q = QueryBuilder.select(kDOCID).from(DataSource.collection(defaultCollection!)).orderBy(o)
            var firstNames: [String] = []
            let numRows = try verifyQuery(q, block: { (n, r) in
                let doc = try defaultCollection!.document(id: r.string(at: 0)!)!
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
    
    func testSelectDistinct() throws {
        let doc1 = MutableDocument()
        doc1.setValue(20, forKey: "number")
        try saveDocument(doc1)
        
        let doc2 = MutableDocument()
        doc2.setValue(20, forKey: "number")
        try saveDocument(doc2)
        
        let NUMBER  = Expression.property("number")
        
        let q = QueryBuilder.selectDistinct(SelectResult.expression(NUMBER)).from(DataSource.collection(defaultCollection!))
        let numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.int(at: 0), 20)
        })
        XCTAssertEqual(numRow, 1)
    }
    
    func testJoin() throws {
        try loadNumbers(100)
        
        let doc = createDocument("joinme")
        doc.setValue(42, forKey: "theone")
        try saveDocument(doc)
        
        let DOCID = SelectResult.expression(Meta.id.from("main"))
        
        let q = QueryBuilder
            .select(DOCID)
            .from(DataSource.collection(defaultCollection!).as("main"))
            .join(
                Join.join(DataSource.collection(defaultCollection!).as("secondary"))
                    .on(Expression.property("number1").from("main")
                        .equalTo(Expression.property("theone").from("secondary"))))
        
        let numRow = try verifyQuery(q, block: { (n, r) in
            let doc = try defaultCollection!.document(id: r.string(at: 0)!)!
            XCTAssertEqual(doc.int(forKey: "number1"), 42)
        })
        XCTAssertEqual(numRow, 1)
    }
    
    func testLeftJoin() throws {
        try loadNumbers(100)
        
        let doc = createDocument("joinme")
        doc.setValue(42, forKey: "theone")
        try saveDocument(doc)
        
        let NUMBER1 = Expression.property("number2").from("main")
        let NUMBER2 = Expression.property("theone").from("secondary")
        
        let join = Join.leftJoin(DataSource.collection(defaultCollection!).as("secondary"))
            .on(Expression.property("number1").from("main")
                .equalTo(Expression.property("theone").from("secondary")))
        
        let q = QueryBuilder
            .select(SelectResult.expression(NUMBER1),SelectResult.expression(NUMBER2))
            .from(DataSource.collection(defaultCollection!).as("main"))
            .join(join)
        
        let numRow = try verifyQuery(q, block: { (n, r) in
            
            if (n == 41) {
                XCTAssertEqual(r.int(at: 0) , 59)
                XCTAssertNil(r.value(at: 1));
            }
            if (n == 42) {
                XCTAssertEqual(r.int(at: 0) , 58)
                XCTAssertEqual(r.int(at: 1) , 42)
            }
        })
        XCTAssertEqual(numRow, 101)
    }
    
    func testCrossJoin() throws {
        try loadNumbers(10)
        
        
        let NUMBER1 = Expression.property("number1").from("main")
        let NUMBER2 = Expression.property("number2").from("secondary")
        
        let join = Join.crossJoin(DataSource.collection(defaultCollection!).as("secondary"))
        
        let q = QueryBuilder
            .select(SelectResult.expression(NUMBER1),SelectResult.expression(NUMBER2))
            .from(DataSource.collection(defaultCollection!).as("main"))
            .join(join).orderBy(Ordering.expression(NUMBER2))
        
        let numRow = try verifyQuery(q, block: { (n, r) in
            
            let num1 = r.int(at: 0)
            let num2 = r.int(at: 1)

            XCTAssertEqual ((num1 - 1)%10,Int((n - 1) % 10) )
            XCTAssertEqual (num2 ,Int((n - 1)/10) )
            
        })
        XCTAssertEqual(numRow, 100)
    }
    
    func testJoinByDocID() throws {
        try loadNumbers(100)
        
        let doc = MutableDocument(id: "joinme")
        doc.setInt(42, forKey: "theone")
        doc.setString("doc1", forKey: "numberID")
        try defaultCollection!.save(document: doc)
        
        let mainDS = DataSource.collection(defaultCollection!).as("main")
        let secondaryDS = DataSource.collection(defaultCollection!).as("secondary")
        
        let mainPropExpr = Meta.id.from("main")
        let secondaryExpr = Expression.property("numberID").from("secondary")
        let joinExpr = mainPropExpr.equalTo(secondaryExpr)
        let join = Join.innerJoin(secondaryDS).on(joinExpr)
        
        let mainDocID = SelectResult.expression(mainPropExpr).as("mainDocID")
        let secondaryDocID = SelectResult.expression(Meta.id.from("secondary")).as("secondaryDocID")
        let secondaryTheOne = SelectResult.expression(Expression.property("theone").from("secondary"))
        
        let q = QueryBuilder
            .select(mainDocID, secondaryDocID, secondaryTheOne)
            .from(mainDS)
            .join(join)
        let numRows = try verifyQuery(q) { (n, row) in
            XCTAssertEqual(n, 1)
            
            guard
                let docID = row.string(forKey: "mainDocID"),
                let doc = try defaultCollection!.document(id: docID)
                else {
                    assertionFailure()
                    return
            }
            
            XCTAssertEqual(doc.int(forKey: "number1"), 1)
            XCTAssertEqual(doc.int(forKey: "number2"), 99)
            
            XCTAssertEqual(row.string(forKey: "secondaryDocID"), "joinme")
            XCTAssertEqual(row.int(forKey: "theone"), 42)
        }
        
        XCTAssertEqual(numRows, 1)
    }
    
    func testGroupBy() throws {
        var expectedStates  = ["AL",    "CA",    "CO",    "FL",    "IA"]
        var expectedCounts  = [1,       6,       1,       1,       3]
        var expectedMaxZips = ["35243", "94153", "81223", "33612", "50801"]
        
        try loadJSONResource(name: "names_100")
        
        let STATE  = Expression.property("contact.address.state");
        let COUNT  = Function.count(Expression.int(1))
        let MAXZIP = Function.max(Expression.property("contact.address.zip"))
        let GENDER = Expression.property("gender")
        
        let S_STATE  = SelectResult.expression(STATE)
        let S_COUNT  = SelectResult.expression(COUNT)
        let S_MAXZIP = SelectResult.expression(MAXZIP)
        
        var q = QueryBuilder
            .select(S_STATE, S_COUNT, S_MAXZIP)
            .from(DataSource.collection(defaultCollection!))
            .where(GENDER.equalTo(Expression.string("female")))
            .groupBy(STATE)
            .orderBy(Ordering.expression(STATE))
        
        var numRow = try verifyQuery(q, block: { (n, r) in
            let state = r.string(at: 0)!
            let count = r.int(at: 1)
            let maxzip = r.string(at: 2)!
            
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
        
        q = QueryBuilder
            .select(S_STATE, S_COUNT, S_MAXZIP)
            .from(DataSource.collection(defaultCollection!))
            .where(GENDER.equalTo(Expression.string("female")))
            .groupBy(STATE)
            .having(COUNT.greaterThan(Expression.int(1)))
            .orderBy(Ordering.expression(STATE))
        
        numRow = try verifyQuery(q, block: { (n, r) in
            let state = r.string(at: 0)!
            let count = r.int(at: 1)
            let maxzip = r.string(at: 2)!
            
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
        
        let q = QueryBuilder
            .select([SelectResult.expression(NUMBER1),
                     SelectResult.expression(Expression.parameter("string")),
                     SelectResult.expression(Expression.parameter("maxInt")),
                     SelectResult.expression(Expression.parameter("minInt")),
                     SelectResult.expression(Expression.parameter("maxInt64")),
                     SelectResult.expression(Expression.parameter("minInt64")),
                     SelectResult.expression(Expression.parameter("maxFloat")),
                     SelectResult.expression(Expression.parameter("minFloat")),
                     SelectResult.expression(Expression.parameter("maxDouble")),
                     SelectResult.expression(Expression.parameter("minDouble")),
                     SelectResult.expression(Expression.parameter("bool")),
                     SelectResult.expression(Expression.parameter("date")),
                     SelectResult.expression(Expression.parameter("blob")),
                     SelectResult.expression(Expression.parameter("array")),
                     SelectResult.expression(Expression.parameter("dict"))])
            .from(DataSource.collection(defaultCollection!))
            .where(NUMBER1.between(PARAM_N1, and: PARAM_N2))
            .orderBy(Ordering.expression(NUMBER1))
        
        let blob = Blob(contentType: "text/plain", data: kTestBlob.data(using: .utf8)!)
        let subarray = MutableArrayObject(data: ["a", "b"])
        let dict = MutableDictionaryObject(data: ["a": "aa", "b": "bb"])
        q.parameters = Parameters()
            .setValue(2, forName: "num1")
            .setValue(5, forName: "num2")
            .setString("someString", forName: "string")
            .setInt(Int.max, forName: "maxInt")
            .setInt(Int.min, forName: "minInt")
            .setInt64(Int64.max, forName: "maxInt64")
            .setInt64(Int64.min, forName: "minInt64")
            .setFloat(Float.greatestFiniteMagnitude, forName: "maxFloat")
            .setFloat(Float.leastNormalMagnitude, forName: "minFloat")
            .setDouble(Double.greatestFiniteMagnitude, forName: "maxDouble")
            .setDouble(Double.leastNormalMagnitude, forName: "minDouble")
            .setBoolean(true, forName: "bool")
            .setDate(dateFromJson(kTestDate), forName: "date")
            .setBlob(blob, forName: "blob")
            .setArray(subarray, forName: "array")
            .setDictionary(dict, forName: "dict")
        
        XCTAssertEqual(q.parameters!.value(forName: "string") as? String, "someString")
        XCTAssertEqual(q.parameters!.value(forName: "maxInt") as! Int, Int.max)
        XCTAssertEqual(q.parameters!.value(forName: "minInt") as! Int, Int.min)
        XCTAssertEqual(q.parameters!.value(forName: "maxInt64") as! Int64, Int64.max)
        XCTAssertEqual(q.parameters!.value(forName: "minInt64") as! Int64, Int64.min)
        XCTAssertEqual(q.parameters!.value(forName: "maxFloat") as! Float, Float.greatestFiniteMagnitude)
        XCTAssertEqual(q.parameters!.value(forName: "minFloat") as! Float, Float.leastNormalMagnitude)
        XCTAssertEqual(q.parameters!.value(forName: "maxDouble") as! Double, Double.greatestFiniteMagnitude)
        XCTAssertEqual(q.parameters!.value(forName: "minDouble") as! Double, Double.leastNormalMagnitude)
        XCTAssertEqual(q.parameters!.value(forName: "bool") as! Bool, true)
        XCTAssert((q.parameters!.value(forName: "date") as! Date).timeIntervalSince(dateFromJson(kTestDate)) < 1)
        XCTAssertEqual((q.parameters!.value(forName: "blob") as! Blob).content, blob.content)
        XCTAssertEqual(q.parameters!.value(forName: "array") as! MutableArrayObject, subarray)
        XCTAssertEqual(q.parameters!.value(forName: "dict") as! MutableDictionaryObject, dict)
        
        let expectedNumbers = [2, 3, 4, 5]
        let numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.int(at: 0), expectedNumbers[Int(n-1)])
            XCTAssertEqual(r.string(at: 1) , "someString")
            XCTAssertEqual(r.int(at: 2), Int.max)
            XCTAssertEqual(r.int(at: 3), Int.min)
            XCTAssertEqual(r.int64(at: 4), Int64.max)
            XCTAssertEqual(r.int64(at: 5), Int64.min)
            XCTAssertEqual(r.float(at: 6), Float.greatestFiniteMagnitude)
            XCTAssertEqual(r.float(at: 7), Float.leastNormalMagnitude)
            XCTAssertEqual(r.double(at: 8), Double.greatestFiniteMagnitude)
            XCTAssertEqual(r.double(at: 9), Double.leastNormalMagnitude)
            XCTAssertEqual(r.boolean(at: 10), true)
            XCTAssert(r.date(at: 11)!.timeIntervalSince(dateFromJson(kTestDate)) < 1)
            XCTAssertEqual(r.blob(at: 12)!.content, blob.content)
            XCTAssertEqual(r.array(at: 13), subarray)
            XCTAssertEqual(r.dictionary(at: 14), dict)
        })
        XCTAssertEqual(numRow, 4)
    }
    
    func testMeta() throws {
        try loadNumbers(5)
        
        let DOC_ID  = Meta.id
        let REV_ID = Meta.revisionID
        let DOC_SEQ = Meta.sequence
        let NUMBER1 = Expression.property("number1")
        
        let S_DOC_ID  = SelectResult.expression(DOC_ID)
        let S_REV_ID  = SelectResult.expression(REV_ID)
        let S_DOC_SEQ = SelectResult.expression(DOC_SEQ)
        let S_NUMBER1 = SelectResult.expression(NUMBER1)
        
        let q = QueryBuilder
            .select(S_DOC_ID, S_REV_ID, S_DOC_SEQ, S_NUMBER1)
            .from(DataSource.collection(defaultCollection!))
            .orderBy(Ordering.expression(DOC_SEQ))
        
        let expectedDocIDs  = ["doc1", "doc2", "doc3", "doc4", "doc5"]
        let expectedSeqs    = [1, 2, 3, 4, 5]
        let expectedNumbers = [1, 2, 3, 4, 5]
        
        let numRow = try verifyQuery(q, block: { (n, r) in
            let id1 = r.string(at: 0)!
            let id2 = r.string(forKey: "id")
            
            let revID1 = r.string(at: 1)!
            let revID2 = r.string(forKey: "revisionID")
            
            let sequence1 = r.int(at: 2)
            let sequence2 = r.int(forKey: "sequence")
            
            let number = r.int(at: 3)
            
            XCTAssertEqual(id1, id2)
            XCTAssertEqual(id1, expectedDocIDs[Int(n-1)])
            
            XCTAssertEqual(revID1, revID2)
            XCTAssertEqual(revID1, try defaultCollection!.document(id: id1)!.revisionID)
            
            XCTAssertEqual(sequence1, sequence2)
            XCTAssertEqual(sequence1, expectedSeqs[Int(n-1)])
            
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 5)
    }
    
    func testLimit() throws {
        try loadNumbers(10)
        
        let NUMBER1  = Expression.property("number1")
        
        var q = QueryBuilder
            .select(SelectResult.expression(NUMBER1))
            .from(DataSource.collection(defaultCollection!))
            .orderBy(Ordering.expression(NUMBER1))
            .limit(Expression.int(5))
        
        var expectedNumbers = [1, 2, 3, 4, 5]
        var numRow = try verifyQuery(q, block: { (n, row) in
            let number = row.value(at: 0) as! Int
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 5)
        
        q = QueryBuilder
            .select(SelectResult.expression(NUMBER1))
            .from(DataSource.collection(defaultCollection!))
            .orderBy(Ordering.expression(NUMBER1))
            .limit(Expression.parameter("LIMIT_NUM"))
        
        q.parameters = Parameters().setValue(3, forName: "LIMIT_NUM")
        
        expectedNumbers = [1, 2, 3]
        numRow = try verifyQuery(q, block: { (n, r) in
            let number = r.int(at: 0)
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 3)
    }
    
    func testLimitOffset() throws {
        try loadNumbers(10)
        
        let NUMBER1  = Expression.property("number1")
        
        var q = QueryBuilder
            .select(SelectResult.expression(NUMBER1))
            .from(DataSource.collection(defaultCollection!))
            .orderBy(Ordering.expression(NUMBER1))
            .limit(Expression.int(5), offset: Expression.int(3))
        
        var expectedNumbers = [4, 5, 6, 7, 8]
        var numRow = try verifyQuery(q, block: { (n, row) in
            let number = row.value(at: 0) as! Int
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 5)
        
        q = QueryBuilder
            .select(SelectResult.expression(NUMBER1))
            .from(DataSource.collection(defaultCollection!))
            .orderBy(Ordering.expression(NUMBER1))
            .limit(Expression.parameter("LIMIT_NUM"), offset: Expression.parameter("OFFSET_NUM"))
        
        q.parameters = Parameters()
            .setValue(3, forName: "LIMIT_NUM")
            .setValue(5, forName: "OFFSET_NUM")
        
        expectedNumbers = [6, 7, 8]
        numRow = try verifyQuery(q, block: { (n, r) in
            let number = r.int(at: 0)
            XCTAssertEqual(number, expectedNumbers[Int(n-1)])
        })
        XCTAssertEqual(numRow, 3)
    }
    
    func testQueryResult() throws {
        try loadJSONResource(name: "names_100")
        
        let FNAME = Expression.property("name.first")
        let LNAME = Expression.property("name.last")
        let GENDER = Expression.property("gender")
        let CITY = Expression.property("contact.address.city")
        
        let S_FNAME  = SelectResult.expression(FNAME).as("firstname")
        let S_LNAME  = SelectResult.expression(LNAME).as("lastname")
        let S_GENDER  = SelectResult.expression(GENDER)
        let S_CITY  = SelectResult.expression(CITY)
        
        let q = QueryBuilder
            .select(S_FNAME, S_LNAME, S_GENDER, S_CITY)
            .from(DataSource.collection(defaultCollection!))
        
        let numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.count, 4)
            XCTAssertEqual(r.value(forKey: "firstname") as! String, r.value(at: 0) as! String)
            XCTAssertEqual(r.value(forKey: "lastname") as! String, r.value(at: 1) as! String)
            XCTAssertEqual(r.value(forKey: "gender") as! String, r.value(at: 2) as! String)
            XCTAssertEqual(r.value(forKey: "city") as! String, r.value(at: 3) as! String)
        })
        XCTAssertEqual(numRow, 100)
    }
    
    func testQueryProjectingKeys() throws {
        try loadNumbers(100)
        
        let AVG = SelectResult.expression(Function.avg(Expression.property("number1")))
        let CNT = SelectResult.expression(Function.count(Expression.property("number1")))
        let MIN = SelectResult.expression(Function.min(Expression.property("number1")))
        let MAX = SelectResult.expression(Function.max(Expression.property("number1")))
        let SUM = SelectResult.expression(Function.sum(Expression.property("number1")))
        
        let q = QueryBuilder
            .select(AVG, CNT, MIN.as("min"), MAX, SUM.as("sum"))
            .from(DataSource.collection(defaultCollection!))
        
        let numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.count, 5)
            XCTAssertEqual(r.double(forKey: "$1"), r.double(at: 0))
            XCTAssertEqual(r.int(forKey: "$2"), r.int(at: 1))
            XCTAssertEqual(r.int(forKey: "min"), r.int(at: 2))
            XCTAssertEqual(r.int(forKey: "$3"), r.int(at: 3))
            XCTAssertEqual(r.int(forKey: "sum"), r.int(at: 4))
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
        
        let q = QueryBuilder
            .select(AVG, CNT, MIN, MAX, SUM)
            .from(DataSource.collection(defaultCollection!))
        
        let numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.double(at: 0), 50.5)
            XCTAssertEqual(r.int(at: 1), 100)
            XCTAssertEqual(r.int(at: 2), 1)
            XCTAssertEqual(r.int(at: 3), 100)
            XCTAssertEqual(r.int(at: 4), 5050)
        })
        XCTAssertEqual(numRow, 1)
    }
    
    func testArrayFunctions() throws {
        let doc = MutableDocument(id: "doc1")
        let array = MutableArrayObject()
        array.addValue("650-123-0001")
        array.addValue("650-123-0002")
        doc.setValue(array, forKey: "array")
        try self.defaultCollection!.save(document: doc)
        
        let ARRAY_LENGTH = ArrayFunction.length(Expression.property("array"))
        var q = QueryBuilder
            .select(SelectResult.expression(ARRAY_LENGTH))
            .from(DataSource.collection(defaultCollection!))
        
        var numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.int(at: 0), 2)
        })
        XCTAssertEqual(numRow, 1)
        
        let ARRAY_CONTAINS1 = ArrayFunction.contains(Expression.property("array"), value: Expression.string("650-123-0001"))
        let ARRAY_CONTAINS2 = ArrayFunction.contains(Expression.property("array"), value: Expression.string("650-123-0003"))
        q = QueryBuilder
            .select(SelectResult.expression(ARRAY_CONTAINS1), SelectResult.expression(ARRAY_CONTAINS2))
            .from(DataSource.collection(defaultCollection!))
        
        numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.boolean(at: 0), true)
            XCTAssertEqual(r.boolean(at: 1), false)
        })
        XCTAssertEqual(numRow, 1)
    }
    
    func testMathFunctions() throws {
        let num = 0.6
        let doc = MutableDocument(id: "doc1")
        doc.setValue(num, forKey: "number")
        try defaultCollection!.save(document: doc)
        
        let expectedValues = [0.6,
                              acos(num),
                              asin(num),
                              atan(num),
                              atan2(90.0, num),
                              ceil(num),
                              cos(num),
                              num * 180.0 / Double.pi,
                              exp(num),
                              floor(num),
                              log(num),
                              log10(num),
                              pow(num, 2),
                              num * Double.pi / 180.0,
                              round(num),
                              round(num * 10.0) / 10.0,
                              1, sin(num),
                              sqrt(num),
                              tan(num),
                              trunc(num),
                              trunc(num * 10.0) / 10.0,
                              M_E,
                              Double.pi]
        
        let p = Expression.property("number")
        let functions = [Function.abs(p),
                         Function.acos(p),
                         Function.asin(p),
                         Function.atan(p),
                         Function.atan2(y: Expression.int(90), x: p),
                         Function.ceil(p),
                         Function.cos(p),
                         Function.degrees(p),
                         Function.exp(p),
                         Function.floor(p),
                         Function.ln(p),
                         Function.log(p),
                         Function.power(base: p, exponent: Expression.int(2)),
                         Function.radians(p),
                         Function.round(p),
                         Function.round(p, digits: Expression.int(1)),
                         Function.sign(p),
                         Function.sin(p),
                         Function.sqrt(p),
                         Function.tan(p),
                         Function.trunc(p),
                         Function.trunc(p, digits: Expression.int(1)),
                         Function.e(),
                         Function.pi()]
        
        var index = 0
        for f in functions {
            let q = QueryBuilder
                .select(SelectResult.expression(f))
                .from(DataSource.collection(defaultCollection!))
            let numRow = try verifyQuery(q, block: { (n, r) in
                let expected = expectedValues[index]
                XCTAssertEqual(r.double(at: 0), expected, "Failure with \(f)")
            })
            XCTAssertEqual(numRow, 1)
            index = index + 1
        }
    }
    
    func testDivisionFunctionPrecision() throws {
        let doc = MutableDocument()
            .setDouble(5.0, forKey: "key1")
            .setDouble(15.0, forKey: "key2")
            .setDouble(5.5, forKey: "key3")
            .setDouble(16.5, forKey: "key4")
        try saveDocument(doc)
        
        let withoutPrecision = Expression.property("key1").divide(Expression.property("key2"))
        let withPrecision = Expression.property("key3").divide(Expression.property("key4"))
        let q = QueryBuilder
            .select(SelectResult.expression(withoutPrecision).as("withoutPrecision"),
                    SelectResult.expression(withPrecision).as("withPrecision"))
            .from(DataSource.collection(defaultCollection!))
        
        let numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssert(0.33333 - r.double(forKey: "withoutPrecision") < 0.0000)
            XCTAssert(0.33333 - r.double(forKey: "withPrecision") < 0.0000)
        })
        XCTAssertEqual(numRow, 1)
    }
    
    func testStringFunctions() throws {
        let str = "  See you 18r  "
        let doc = MutableDocument(id: "doc1")
        doc.setValue(str, forKey: "greeting")
        try defaultCollection!.save(document: doc)
        
        let p = Expression.property("greeting")
        
        // Contains:
        let CONTAINS1 = Function.contains(p, substring: Expression.string("8"))
        let CONTAINS2 = Function.contains(p, substring: Expression.string("9"))
        var q = QueryBuilder
            .select(SelectResult.expression(CONTAINS1), SelectResult.expression(CONTAINS2))
            .from(DataSource.collection(defaultCollection!))
        
        var numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.boolean(at: 0), true)
            XCTAssertEqual(r.boolean(at: 1), false)
        })
        XCTAssertEqual(numRow, 1)
        
        // Length:
        let LENGTH = Function.length(p)
        q = QueryBuilder
            .select(SelectResult.expression(LENGTH))
            .from(DataSource.collection(defaultCollection!))
        
        numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.int(at: 0), str.count)
        })
        XCTAssertEqual(numRow, 1)
     
        // Lower, Ltrim, Rtrim, Trim, Upper
        let LOWER = Function.lower(p)
        let LTRIM = Function.ltrim(p)
        let RTRIM = Function.rtrim(p)
        let TRIM = Function.trim(p)
        let UPPER = Function.upper(p)
        
        q = QueryBuilder
            .select(SelectResult.expression(LOWER),
                    SelectResult.expression(LTRIM),
                    SelectResult.expression(RTRIM),
                    SelectResult.expression(TRIM),
                    SelectResult.expression(UPPER))
            .from(DataSource.collection(defaultCollection!))
        
        numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.string(at: 0), str.lowercased())
            XCTAssertEqual(r.string(at: 1), "See you 18r  ")
            XCTAssertEqual(r.string(at: 2), "  See you 18r")
            XCTAssertEqual(r.string(at: 3), "See you 18r")
            XCTAssertEqual(r.string(at: 4), str.uppercased())
        })
        XCTAssertEqual(numRow, 1)
    }
    
    func testQuantifiedOperators() throws {
        try loadJSONResource(name: "names_100")
        
        let DOC_ID  = Meta.id
        let S_DOC_ID  = SelectResult.expression(DOC_ID)
        
        let LIKES = Expression.property("likes")
        let LIKE = ArrayExpression.variable("LIKE")
        
        // ANY:
        var q = QueryBuilder
            .select(S_DOC_ID)
            .from(DataSource.collection(defaultCollection!))
            .where(ArrayExpression.any(LIKE).in(LIKES).satisfies(LIKE.equalTo(Expression.string("climbing"))))
        
        let expected = ["doc-017", "doc-021", "doc-023", "doc-045", "doc-060"]
        var numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.string(at: 0), expected[Int(n)-1])
        })
        XCTAssertEqual(numRow, UInt64(expected.count))
        
        // EVERY:
        q = QueryBuilder
            .select(S_DOC_ID)
            .from(DataSource.collection(defaultCollection!))
            .where(ArrayExpression.every(LIKE).in(LIKES).satisfies(LIKE.equalTo(Expression.string("taxes"))))
        
        numRow = try verifyQuery(q, block: { (n, r) in
            if n == 1 {
                XCTAssertEqual(r.string(at: 0), "doc-007")
            }
        })
        XCTAssertEqual(numRow, 42)
        
        // ANY AND EVERY:
        q = QueryBuilder
            .select(S_DOC_ID)
            .from(DataSource.collection(defaultCollection!))
            .where(ArrayExpression.anyAndEvery(LIKE).in(LIKES).satisfies(LIKE.equalTo(Expression.string("taxes"))))
        
        numRow = try verifyQuery(q, block: { (n, r) in })
        XCTAssertEqual(numRow, 0)
    }
    
    func testSelectAll() throws {
        try loadNumbers(100)
        
        let NUMBER1 = Expression.property("number1")
        let S_STAR = SelectResult.all()
        let S_NUMBER1 = SelectResult.expression(NUMBER1)
        
        let TESTDB_NUMBER1 = Expression.property("number1").from("testdb")
        let S_TESTDB_STAR = SelectResult.all().from("testdb")
        let S_TESTDB_NUMBER1 = SelectResult.expression(TESTDB_NUMBER1)
        
        // SELECT *
        var q = QueryBuilder
            .select(S_STAR)
            .from(DataSource.collection(defaultCollection!))
        
        var numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.count, 1)
            let a1 = r.dictionary(at: 0)!
            let a2 = r.dictionary(forKey: defaultCollection!.name)!
            XCTAssertEqual(a1.int(forKey: "number1"), Int(n))
            XCTAssertEqual(a1.int(forKey: "number2"), Int(100 - n))
            XCTAssertEqual(a2.int(forKey: "number1"), Int(n))
            XCTAssertEqual(a2.int(forKey: "number2"), Int(100 - n))
        })
        XCTAssertEqual(numRow, 100)
        
        // SELECT testdb.*
        q = QueryBuilder
            .select(S_TESTDB_STAR)
            .from(DataSource.collection(defaultCollection!).as("testdb"))
        
        numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.count, 1)
            let a1 = r.dictionary(at: 0)!
            let a2 = r.dictionary(forKey: "testdb")!
            XCTAssertEqual(a1.int(forKey: "number1"), Int(n))
            XCTAssertEqual(a1.int(forKey: "number2"), Int(100 - n))
            XCTAssertEqual(a2.int(forKey: "number1"), Int(n))
            XCTAssertEqual(a2.int(forKey: "number2"), Int(100 - n))
        })
        XCTAssertEqual(numRow, 100)
        
        // SELECT *, number1
        q = QueryBuilder
            .select(S_STAR, S_NUMBER1)
            .from(DataSource.collection(defaultCollection!))
        
        numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.count, 2)
            let a1 = r.dictionary(at: 0)!
            let a2 = r.dictionary(forKey: defaultCollection!.name)!
            XCTAssertEqual(a1.int(forKey: "number1"), Int(n))
            XCTAssertEqual(a1.int(forKey: "number2"), Int(100 - n))
            XCTAssertEqual(a2.int(forKey: "number1"), Int(n))
            XCTAssertEqual(a2.int(forKey: "number2"), Int(100 - n))
            XCTAssertEqual(r.int(at: 1), Int(n))
            XCTAssertEqual(r.int(forKey: "number1"), Int(n))
        })
        XCTAssertEqual(numRow, 100)
        
        // SELECT testdb.*, testdb.number1
        q = QueryBuilder
            .select(S_TESTDB_STAR, S_TESTDB_NUMBER1)
            .from(DataSource.collection(defaultCollection!).as("testdb"))
        
        numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.count, 2)
            let a1 = r.dictionary(at: 0)!
            let a2 = r.dictionary(forKey: "testdb")!
            XCTAssertEqual(a1.int(forKey: "number1"), Int(n))
            XCTAssertEqual(a1.int(forKey: "number2"), Int(100 - n))
            XCTAssertEqual(a2.int(forKey: "number1"), Int(n))
            XCTAssertEqual(a2.int(forKey: "number2"), Int(100 - n))
            XCTAssertEqual(r.int(at: 1), Int(n))
            XCTAssertEqual(r.int(forKey: "number1"), Int(n))
        })
        XCTAssertEqual(numRow, 100)
    }
    
    func testSelectAllWithDatabaseAliasWithMultipleSources() throws {
        try loadNumbers(100)
        
        let doc = createDocument()
        doc.setValue(42, forKey: "theOne")
        try saveDocument(doc)
        
        let q = QueryBuilder
            .selectDistinct([SelectResult.all().from("main"),
                             SelectResult.all().from("secondary")])
            .from(DataSource.collection(defaultCollection!).as("main"))
            .join(
                Join.join(DataSource.collection(defaultCollection!).as("secondary"))
                    .on(Expression.property("number1").from("main")
                        .equalTo(Expression.property("theOne").from("secondary"))))
        
        let numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.dictionary(at: 0), r.dictionary(forKey: "main"));
            XCTAssertEqual(r.dictionary(at: 1), r.dictionary(forKey: "secondary"));
        })
        XCTAssertEqual(numRow, 1)
    }
    
    func testUnicodeCollationWithLocale() throws {
        let letters = ["B", "A", "Z", "Å"]
        for letter in letters {
            let doc = createDocument()
            doc.setValue(letter, forKey: "string")
            try saveDocument(doc)
        }
        
        let STRING = Expression.property("string")
        let S_STRING = SelectResult.expression(STRING)
        
        // Without locale:
        let NO_LOCALE = Collation.unicode()
        var q = QueryBuilder
            .select(S_STRING)
            .from(DataSource.collection(defaultCollection!))
            .orderBy(Ordering.expression(STRING.collate(NO_LOCALE)))
        
        var expected = ["A", "Å", "B", "Z"]
        var numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.string(at: 0), expected[Int(n)-1])
        })
        XCTAssertEqual(numRow, UInt64(expected.count))
        
        // With locale
        let WITH_LOCALE = Collation.unicode().locale("se")
        q = QueryBuilder
            .select(S_STRING)
            .from(DataSource.collection(defaultCollection!))
            .orderBy(Ordering.expression(STRING.collate(WITH_LOCALE)))
        
        expected = ["A", "B", "Z", "Å"]
        numRow = try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.string(at: 0), expected[Int(n)-1])
        })
        XCTAssertEqual(numRow, UInt64(expected.count))
    }
    
    func testCompareWithUnicodeCollation() throws {
        let bothSensitive = Collation.unicode()
        let caseInsensitive = Collation.unicode().ignoreCase(true)
        let accentInsensitive = Collation.unicode().ignoreAccents(true)
        let noSensitive = Collation.unicode().ignoreCase(true).ignoreAccents(true)
        
        let testCases = [
            // Edge cases: empty and 1-char strings:
            ("", "", true, bothSensitive),
            ("", "a", false, bothSensitive),
            ("a", "a", true, bothSensitive),
            
            // Case sensitive: lowercase come first by unicode rules:
            ("a", "A", false, bothSensitive),
            ("abc", "abc", true, bothSensitive),
            ("Aaa", "abc", false, bothSensitive),
            ("abc", "abC", false, bothSensitive),
            ("AB", "abc", false, bothSensitive),
            
            // Case insensitive:
            ("ABCDEF", "ZYXWVU", false, caseInsensitive),
            ("ABCDEF", "Z", false, caseInsensitive),
            
            ("a", "A", true, caseInsensitive),
            ("abc", "ABC", true, caseInsensitive),
            ("ABA", "abc", false, caseInsensitive),
            
            ("commonprefix1", "commonprefix2", false, caseInsensitive),
            ("commonPrefix1", "commonprefix2", false, caseInsensitive),
            
            ("abcdef", "abcdefghijklm", false, caseInsensitive),
            ("abcdeF", "abcdefghijklm", false, caseInsensitive),
            
            // Now bring in non-ASCII characters:
            ("a", "á", false, caseInsensitive),
            ("", "á", false, caseInsensitive),
            ("á", "á", true, caseInsensitive),
            ("•a", "•A", true, caseInsensitive),
            
            ("test a", "test á", false, caseInsensitive),
            ("test á", "test b", false, caseInsensitive),
            ("test á", "test Á", true, caseInsensitive),
            ("test á1", "test Á2", false, caseInsensitive),
            
            // Case sensitive, diacritic sensitive:
            ("ABCDEF", "ZYXWVU", false, bothSensitive),
            ("ABCDEF", "Z", false, bothSensitive),
            ("a", "A", false, bothSensitive),
            ("abc", "ABC", false, bothSensitive),
            ("•a", "•A", false, bothSensitive),
            ("test a", "test á", false, bothSensitive),
            ("Ähnlichkeit", "apple", false, bothSensitive), // Because 'h'-vs-'p' beats 'Ä'-vs-'a'
            ("ax", "Äz", false, bothSensitive),
            ("test a", "test Á", false, bothSensitive),
            ("test Á", "test e", false, bothSensitive),
            ("test á", "test Á", false, bothSensitive),
            ("test á", "test b", false, bothSensitive),
            ("test u", "test Ü", false, bothSensitive),
            
            // Case sensitive, diacritic insensitive
            ("abc", "ABC", false, accentInsensitive),
            ("test á", "test a", true, accentInsensitive),
            ("test á", "test A", false, accentInsensitive),
            ("test á", "test b", false, accentInsensitive),
            ("test á", "test Á", false, accentInsensitive),
            
            // Case and diacritic insensitive
            ("test á", "test Á", true, noSensitive)
        ]
        
        for data in testCases {
            let doc = createDocument()
            doc.setValue(data.0, forKey: "value")
            try saveDocument(doc)
            
            let VALUE = Expression.property("value")
            let comparison = data.2 ?
                VALUE.collate(data.3).equalTo(Expression.string(data.1)) :
                VALUE.collate(data.3).lessThan(Expression.string(data.1))
            
            let q = QueryBuilder.select().from(DataSource.collection(defaultCollection!)).where(comparison)
            let numRow = try verifyQuery(q, block: { (n, r) in })
            XCTAssertEqual(numRow, 1)
            
            try defaultCollection!.delete(document: doc)
        }
    }
    
    func testCompareWithASCIICollation() throws {
        let ascii = Collation.ascii()
        let caseInsensitive = Collation.ascii().ignoreCase(true)
        
        let testCases = [
            // Edge cases: empty and 1-char strings:
            ("", "", true, ascii),
            ("", "a", false, ascii),
            ("a", "a", true, ascii),
            
            // Case sensitive:
            ("A", "a", false, ascii),
            ("abc", "abc", true, ascii),
            ("Aaa", "abc", false, ascii),
            ("abC", "abc", false, ascii),
            ("AB", "abc", false, ascii),
            
            
            // Case insenstive:
            ("ABCDEF", "ZYXWVU", false, caseInsensitive),
            ("ABCDEF", "Z", false, caseInsensitive),
            ("a", "A", true, caseInsensitive),
            ("ABC", "abc", true, caseInsensitive),
            ("ABA", "abc", false, caseInsensitive),
            
            ("commonprefix1", "commonprefix2", false, caseInsensitive),
            ("commonPrefix1", "commonprefix2", false, caseInsensitive),
            
            ("abcdef", "abcdefghijklm", false, caseInsensitive),
            ("abcdeF", "abcdefghijklm", false, caseInsensitive),
            ]
        
        for data in testCases {
            let doc = createDocument()
            doc.setValue(data.0, forKey: "value")
            try saveDocument(doc)
            
            let VALUE = Expression.property("value")
            let comparison = data.2 ?
                VALUE.collate(data.3).equalTo(Expression.string(data.1)) :
                VALUE.collate(data.3).lessThan(Expression.string(data.1))
            
            let q = QueryBuilder.select().from(DataSource.collection(defaultCollection!)).where(comparison)
            let numRow = try verifyQuery(q, block: { (n, r) in })
            XCTAssertEqual(numRow, 1)
            
            try defaultCollection!.delete(document: doc)
        }
    }
    
    func testResultSetEnumeration() throws {
        try loadNumbers(5)
        let q = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .orderBy(Ordering.property("number1"))
        
        // Enumeration
        var i = 0
        var rs = try q.execute()
        while let r = rs.next() {
            XCTAssertEqual(r.string(at: 0), "doc\(i+1)")
            i+=1
        }
        XCTAssertEqual(i, 5)
        XCTAssertNil(rs.next())
        XCTAssert(rs.allResults().isEmpty)
        
        // Fast enumeration:
        i = 0
        rs = try q.execute()
        for r in rs {
            XCTAssertEqual(r.string(at: 0), "doc\(i+1)")
            i+=1
        }
        XCTAssertEqual(i, 5)
        XCTAssertNil(rs.next())
        XCTAssert(rs.allResults().isEmpty)
    }
    
    func testGetAllResults() throws {
        try loadNumbers(5)
        let q = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .orderBy(Ordering.property("number1"))
        
        // Get all results:
        var i = 0
        var rs = try q.execute()
        var results = rs.allResults()
        for r in results {
            XCTAssertEqual(r.string(at: 0), "doc\(i+1)")
            i+=1
        }
        XCTAssertEqual(results.count, 5)
        XCTAssertNil(rs.next())
        XCTAssert(rs.allResults().isEmpty)
        
        // Partial enumerating then get all results:
        i = 0
        rs = try q.execute()
        XCTAssertNotNil(rs.next())
        XCTAssertNotNil(rs.next())
        results = rs.allResults()
        for r in results {
            XCTAssertEqual(r.string(at: 0), "doc\(i+3)")
            i+=1
        }
        XCTAssertEqual(results.count, 3)
        XCTAssertNil(rs.next())
        XCTAssert(rs.allResults().isEmpty)
    }
    
    func testMissingValue() throws {
        let doc1 = createDocument("doc1")
        doc1.setValue("Scott", forKey: "name")
        doc1.setValue(nil, forKey: "address")
        try saveDocument(doc1)
        
        let q = QueryBuilder
            .select(SelectResult.property("name"),
                    SelectResult.property("address"),
                    SelectResult.property("age"))
            .from(DataSource.collection(defaultCollection!))
        
        let rs = try q.execute()
        let r = rs.next()!
        
        // Array:
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.string(at: 0), "Scott")
        XCTAssertNil(r.value(at: 1))
        XCTAssertNil(r.value(at: 2))
        let array = r.toArray()
        XCTAssertEqual(array.count, 3)
        XCTAssertEqual(array[0] as! String, "Scott")
        XCTAssertEqual(array[1] as! NSNull, NSNull())
        XCTAssertEqual(array[2] as! NSNull, NSNull())
        
        // Dictionary:
        XCTAssertEqual(r.string(forKey: "name"), "Scott")
        XCTAssertNil(r.value(forKey: "address"))
        XCTAssertTrue(r.contains(key: "address"))
        XCTAssertNil(r.value(forKey: "age"))
        XCTAssertFalse(r.contains(key: "age"))
        let dict = r.toDictionary()
        XCTAssertEqual(dict.count, 2)
        XCTAssertEqual(dict["name"] as! String, "Scott")
        XCTAssertEqual(dict["address"] as! NSNull, NSNull())
    }

    func testJSONRepresentation() throws {
        let doc1 = MutableDocument()
        doc1.setValue("string", forKey: "string")
        try saveDocument(doc1)

        let q1 = QueryBuilder.select(kDOCID).from(DataSource.collection(defaultCollection!)).where(
            Expression.property("string").is(Expression.string("string")))
        let json = q1.JSONRepresentation

        let q = Query(database: db, JSONRepresentation: json)

        let numRows = try verifyQuery(q) { (n, r) in
            let doc = try defaultCollection!.document(id: r.string(at: 0)!)!
            XCTAssertEqual(doc.id, doc1.id);
            XCTAssertEqual(doc.string(forKey: "string")!, "string");
        }
        XCTAssertEqual(numRows, 1);
    }
    
    // MARK: META - isDeleted
    
    func testMetaIsDeletedEmpty() throws {
        try loadNumbers(5)
        
        let q = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .where(Meta.isDeleted)
        let rs = try q.execute()
        
        XCTAssertEqual(rs.allResults().count, 0)
    }
    
    func testIsDeletedWithSingleDocumentDeletion() throws {
        // create doc
        let doc = MutableDocument().setString("somevalue", forKey: "somekey")
        try defaultCollection!.save(document: doc)
        
        // check valid input
        let selectAllDBQuery = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
        var selectAllResultSet = try selectAllDBQuery.execute()
        XCTAssertEqual(selectAllResultSet.allResults().count, 1)
        let selectDeletedOnlyQuery = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .where(Meta.isDeleted)
        var selectDeletedOnlyResultSet = try selectDeletedOnlyQuery.execute()
        XCTAssertEqual(selectDeletedOnlyResultSet.allResults().count, 0)
        
        // delete action
        try defaultCollection!.delete(document: doc)
        
        // vertify result
        selectAllResultSet = try selectAllDBQuery.execute()
        XCTAssertEqual(selectAllResultSet.allResults().count, 0)
        selectDeletedOnlyResultSet = try selectDeletedOnlyQuery.execute()
        XCTAssertEqual(selectDeletedOnlyResultSet.allResults().count, 1)
    }
    
    func testIsDeletedWithMultipleDocumentsDeletion() throws {
        let documentsCount = 10
        var docs = [MutableDocument]()
        try db.inBatch {
            for _ in 0..<documentsCount {
                // create doc
                let doc = MutableDocument().setString("somevalue", forKey: "somekey")
                docs.append(doc)
                try defaultCollection!.save(document: doc)
            }
        }
        
        // check valid input
        let selectAllDBQuery = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
        var selectAllResultSet = try selectAllDBQuery.execute()
        XCTAssertEqual(selectAllResultSet.allResults().count, documentsCount)
        let selectDeletedOnlyQuery = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .where(Meta.isDeleted)
        var selectDeletedOnlyResultSet = try selectDeletedOnlyQuery.execute()
        XCTAssertEqual(selectDeletedOnlyResultSet.allResults().count, 0)
        
        // delete action
        try db.inBatch {
            for doc in docs {
                try defaultCollection!.delete(document: doc)
            }
        }
        
        // vertify result
        selectAllResultSet = try selectAllDBQuery.execute()
        XCTAssertEqual(selectAllResultSet.allResults().count, 0)
        selectDeletedOnlyResultSet = try selectDeletedOnlyQuery.execute()
        XCTAssertEqual(selectDeletedOnlyResultSet.allResults().count, documentsCount)
    }
    
    // MARK: META - expired
    
    func testMetaExpirationWithNoDocumentWithExpiration() throws {
        try loadNumbers(5)
        
        let q = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .where(Meta.expiration.greaterThan(Expression.int(0)))
        let rs = try q.execute()
        
        XCTAssertEqual(rs.allResults().count, 0)
    }
    
    func testMetaExpirationWithValidLessThan() throws {
        let doc = MutableDocument()
        try defaultCollection!.save(document: doc)
        let expiry = Date(timeIntervalSinceNow: 120)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiry)
        
        let q = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .where(Meta.expiration
                .lessThan(Expression.double(expiry.addingTimeInterval(1).timeIntervalSince1970 * 1000)))
        let rs = try q.execute()
        
        XCTAssertEqual(rs.allResults().count, 1)
    }
    
    func testMetaExpirationWithInvalidLessThan() throws {
        let doc = MutableDocument()
        try defaultCollection!.save(document: doc)
        let expiry = Date(timeIntervalSinceNow: 120)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiry)
        
        let q = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .where(Meta.expiration
                .lessThan(Expression.double(expiry.addingTimeInterval(-1).timeIntervalSince1970 * 1000)))
        let rs = try q.execute()
        
        XCTAssertEqual(rs.allResults().count, 0)
    }
    
    func testMetaExpirationWithValidGreaterThan() throws {
        let doc = MutableDocument()
        try defaultCollection!.save(document: doc)
        let expiry = Date(timeIntervalSinceNow: 120)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiry)
        
        let q = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .where(Meta.expiration
                .greaterThan(Expression
                    .double(expiry.addingTimeInterval(-1).timeIntervalSince1970 * 1000)))
        let rs = try q.execute()
        
        XCTAssertEqual(rs.allResults().count, 1)
    }
    
    func testMetaExpirationWithInvalidGreaterThan() throws {
        let doc = MutableDocument()
        try defaultCollection!.save(document: doc)
        let expiry = Date(timeIntervalSinceNow: 120)
        try defaultCollection!.setDocumentExpiration(id: doc.id, expiration: expiry)
        
        let q = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.collection(defaultCollection!))
            .where(Meta.expiration
                .greaterThan(Expression
                    .double(expiry.addingTimeInterval(1).timeIntervalSince1970 * 1000)))
        let rs = try q.execute()
        
        XCTAssertEqual(rs.allResults().count, 0)
    }
    
    // MARK: META - revisionID
    
    func testMetaRevisionID() throws {
        // Create doc:
        let doc = MutableDocument()
        try defaultCollection!.save(document: doc)
        
        var q = QueryBuilder
            .select(SelectResult.expression(Meta.revisionID))
            .from(DataSource.collection(defaultCollection!))
            .where(Meta.id.equalTo(Expression.string(doc.id)))
        
        try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.string(at: 0)!, doc.revisionID!)
        })
        
        // Update doc:
        doc.setValue("bar", forKey: "foo")
        try defaultCollection!.save(document: doc)
        
        try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.string(at: 0)!, doc.revisionID!)
        })
        
        // Use meta.revisionID in WHERE clause
        q = QueryBuilder
        .select(SelectResult.expression(Meta.id))
        .from(DataSource.collection(defaultCollection!))
        .where(Meta.revisionID.equalTo(Expression.string(doc.revisionID!)))
        
        try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.string(at: 0)!, doc.id)
        })
        
        // Delete doc:
        try defaultCollection!.delete(document: doc)
        
        q = QueryBuilder
        .select(SelectResult.expression(Meta.revisionID))
        .from(DataSource.collection(defaultCollection!))
        .where(Meta.isDeleted.equalTo(Expression.boolean(true)))
        
        try verifyQuery(q, block: { (n, r) in
            XCTAssertEqual(r.string(at: 0)!, doc.revisionID!)
        })
    }
    
    // MARK: toJSON
    
    func testQueryJSON() throws {
        let json = try getRickAndMortyJSON()
        let mDoc = try MutableDocument(id: "doc", json: json)
        try self.defaultCollection!.save(document: mDoc)
        
        let q = QueryBuilder.select([kDOCID,
                                     SelectResult.property("name"),
                                     SelectResult.property("isAlive"),
                                     SelectResult.property("species"),
                                     SelectResult.property("picture"),
                                     SelectResult.property("gender"),
                                     SelectResult.property("registered"),
                                     SelectResult.property("latitude"),
                                     SelectResult.property("longitude"),
                                     SelectResult.property("aka"),
                                     SelectResult.property("family"),
                                     SelectResult.property("origin")])
            .from(DataSource.collection(self.defaultCollection!))
        
        let rs = try q.execute()
        let r = rs.allResults().first!
        let jsonObj = r.toJSON().toJSONObj() as! [String: Any]
        XCTAssertEqual(jsonObj["id"] as! String, "doc")
        XCTAssertEqual(jsonObj["name"] as! String, "Rick Sanchez")
        XCTAssertEqual(jsonObj["isAlive"] as! Bool, true)
        XCTAssertEqual(jsonObj["longitude"] as! Double, -21.152958)
        XCTAssertEqual((jsonObj["aka"] as! Array<Any>)[0] as! String, "Rick C-137")
        XCTAssertEqual((jsonObj["aka"] as! Array<Any>)[3] as! String, "Rick the Alien")
        XCTAssertEqual((jsonObj["family"] as! Array<[String:Any]>)[0]["name"] as! String, "Morty Smith")
        XCTAssertEqual((jsonObj["family"] as! Array<[String:Any]>)[3]["name"] as! String, "Summer Smith")
    }
    
    // MARK: N1QL
    
    func testN1QLQuerySanity() throws {
        let doc1 = MutableDocument()
        doc1.setValue("Jerry", forKey: "firstName")
        doc1.setValue("Ice Cream", forKey: "lastName")
        try self.defaultCollection!.save(document: doc1)
        
        let doc2 = MutableDocument()
        doc2.setValue("Ben", forKey: "firstName")
        doc2.setValue("Ice Cream", forKey: "lastName")
        try self.defaultCollection!.save(document: doc2)
        
        let q = try self.db.createQuery("SELECT firstName, lastName FROM \(self.db.name)")
        let results = try q.execute().allResults()
        XCTAssertEqual(results[0].string(forKey: "firstName"), "Jerry")
        XCTAssertEqual(results[0].string(forKey: "lastName"), "Ice Cream")
        XCTAssertEqual(results[1].string(forKey: "firstName"), "Ben")
        XCTAssertEqual(results[1].string(forKey: "lastName"), "Ice Cream")
    }
    
    func testInvalidN1QL() throws {
        expectError(domain: CBLError.domain, code: CBLError.invalidQuery) {
            _ = try self.db.createQuery("SELECT firstName, lastName")
        }
    }
    
    func testN1QLQueryOffsetWithoutLimit() throws {
        let doc1 = MutableDocument()
        doc1.setValue("Jerry", forKey: "firstName")
        doc1.setValue("Ice Cream", forKey: "lastName")
        try self.defaultCollection!.save(document: doc1)
        
        let doc2 = MutableDocument()
        doc2.setValue("Ben", forKey: "firstName")
        doc2.setValue("Ice Cream", forKey: "lastName")
        try self.defaultCollection!.save(document: doc2)
        
        let q = try self.db.createQuery("SELECT firstName, lastName FROM \(self.db.name) offset 1")
        let results = try q.execute().allResults()
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: -- LiveQuery
    
    func testJSONLiveQuery() throws {
        let q = QueryBuilder
            .select()
            .from(DataSource.collection(defaultCollection!))
            .where(Expression.property("number1").lessThan(Expression.int(10)))
            .orderBy(Ordering.property("number1"))
        try testLiveQuery(query: q)
    }
    
    func testN1QLLiveQuery() throws {
        let q = try db.createQuery("SELECT * FROM testdb WHERE number1 < 10")
        try testLiveQuery(query: q)
    }
    
    // CBSE-15957 : Crash when creating multiple live queries concurrently
    func testCreateLiveQueriesConcurrently() throws {
        // Create 1000 docs:
        try loadNumbers(1000)
        
        // Create two live queries then remove them concurrently:
        let remExp = self.expectation(description: "Listener Removed")
        remExp.expectedFulfillmentCount = 2
        let queue = DispatchQueue(label: "query-queue", attributes: .concurrent)
        for i in 0..<2 {
            queue.async {
                let exp = self.expectation(description: "Change Received")
                let query = try! self.db.createQuery("select * from _ where number1 < \(i * 200)")
                let token = query.addChangeListener {
                    change in exp.fulfill()
                }
                self.wait(for: [exp], timeout: self.expTimeout)
                token.remove()
                remExp.fulfill()
            }
        }
        
        wait(for: [remExp], timeout: expTimeout)
    }
    
    func testLiveQuery(query: Query) throws {
        try loadNumbers(100)
        var count = 0;
        let x1 = expectation(description: "1st change")
        let x2 = expectation(description: "2nd change")
        
        let token = query.addChangeListener { (change) in
            count = count + 1
            XCTAssertNotNil(change.query)
            XCTAssertNil(change.error)
            let rows =  Array(change.results!)
            if count == 1 {
                XCTAssertEqual(rows.count, 9)
                x1.fulfill()
            } else {
                XCTAssertEqual(rows.count, 10)
                x2.fulfill()
            }
        }
        
        wait(for: [x1], timeout: expTimeout)
        try! self.createDoc(numbered: -1, of: 100)
        
        wait(for: [x2], timeout: expTimeout)
        query.removeChangeListener(withToken: token)
    }
    
    func testLiveQueryNoUpdate() throws {
        var count = 0;
        let q = QueryBuilder
            .select()
            .from(DataSource.collection(defaultCollection!))
        let x1 = expectation(description: "1st change")
        let token = q.addChangeListener { (change) in
            count = count + 1
            XCTAssertNotNil(change.query)
            XCTAssertNil(change.error)
            let rows =  Array(change.results!)
            XCTAssertEqual(rows.count, 0)
            x1.fulfill()
        }
        
        wait(for: [x1], timeout: expTimeout)
        XCTAssertEqual(count, 1)
        q.removeChangeListener(withToken: token)
    }
    
    // When adding a second listener after the first listener is notified, the second listener
    // should get the change (current result).
    func testLiveQuerySecondListenerReturnsResultsImmediately() throws {
        try createDoc(numbered: 7, of: 10)
        let query = QueryBuilder
            .select(SelectResult.property("number1"))
            .from(DataSource.collection(defaultCollection!))
            .where(Expression.property("number1").lessThan(Expression.int(10)))
            .orderBy(Ordering.property("number1"))
        
        // first listener
        let x1 = expectation(description: "1st change")
        var count = 0;
        let token = query.addChangeListener { (change) in
            count = count + 1
            let rows =  Array(change.results!)
            if count == 1 {
                XCTAssertEqual(rows.count, 1)
                XCTAssertEqual(rows[0].int(at: 0), 7)
                x1.fulfill()
            }
        }
        wait(for: [x1], timeout: expTimeout)
        XCTAssertEqual(count, 1)
        
        // adding a second listener should be returning the last results!
        let x2 = expectation(description: "1st change from 2nd listener")
        var count2 = 0
        let token2 = query.addChangeListener { (change) in
            count2 = count2 + 1
            let rows =  Array(change.results!)
            if count2 == 1 {
                XCTAssertEqual(rows.count, 1)
                XCTAssertEqual(rows[0].int(at: 0), 7)
                x2.fulfill()
            }
        }        
        
        wait(for: [x2], timeout: expTimeout)
        query.removeChangeListener(withToken: token)
        query.removeChangeListener(withToken: token2)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(count2, 1)
    }
    
    func testLiveQueryReturnsEmptyResultSet() throws {
        try loadNumbers(100)
        let query = QueryBuilder
            .select(SelectResult.property("number1"))
            .from(DataSource.collection(defaultCollection!))
            .where(Expression.property("number1").lessThan(Expression.int(10)))
            .orderBy(Ordering.property("number1"))
        
        let x1 = expectation(description: "wait-for-live-query-changes")
        var count = 0;
        let token = query.addChangeListener { (change) in
            count = count + 1
            let rows =  Array(change.results!)
            if count == 1 {
                // initial notification about already existing result set!
                XCTAssertEqual(rows.count, 9)
                XCTAssertEqual(rows[0].int(at: 0), 1)
            } else {
                // deleted the doc should return empty result set!
                XCTAssertEqual(rows.count, 8)
                x1.fulfill()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try! self.defaultCollection!.purge(id: "doc1")
        }
        wait(for: [x1], timeout: expTimeout)
        query.removeChangeListener(withToken: token)
        XCTAssertEqual(count, 2)
    }
    
    /// When having more than one listeners, each listener should have independent result sets.
    /// This means that both listeners should be able to iterate separately through the result
    /// correct when getting the same change notified.
    func testLiveQueryMultipleListenersReturnIndependentResultSet() throws {
        try loadNumbers(100)
        let query = QueryBuilder
            .select(SelectResult.property("number1"))
            .from(DataSource.collection(defaultCollection!))
            .where(Expression.property("number1").lessThan(Expression.int(10)))
            .orderBy(Ordering.property("number1"))
        
        let x1 = expectation(description: "1st change")
        let x2 = expectation(description: "2nd change")
        var count1 = 0;
        let token1 = query.addChangeListener { (change) in
            count1 = count1 + 1
            guard let results = change.results else {
                XCTFail("Results are empty")
                return
            }
            if count1 == 1 {
                var num = 0
                for result in results {
                    num = num + 1
                    XCTAssert(result.int(at: 0) < 10)
                }
                XCTAssertEqual(num, 9)
                x1.fulfill()
            } else if count1 == 2 {
                var num = 0
                for result in results {
                    num = num + 1
                    XCTAssert(result.int(at: 0) < 10)
                }
                XCTAssertEqual(num, 10)
                x2.fulfill()
            }
        }
        
        let y1 = expectation(description: "1st change - 2nd listener")
        let y2 = expectation(description: "2nd change - 2nd listener")
        var count2 = 0;
        let token2 = query.addChangeListener { (change) in
            count2 = count2 + 1
            guard let results = change.results else {
                XCTFail("Results are empty")
                return
            }
            
            if count2 == 1 {
                var num = 0
                for result in results {
                    num = num + 1
                    XCTAssert(result.int(at: 0) < 10)
                }
                XCTAssertEqual(num, 9)
                y1.fulfill()
            } else if count2 == 2 {
                var num = 0
                for result in results {
                    num = num + 1
                    XCTAssert(result.int(at: 0) < 10)
                }
                XCTAssertEqual(num, 10)
                y2.fulfill()
            }
        }
        wait(for: [x1, y1], timeout: expTimeout)
        try! self.createDoc(numbered: -1, of: 100)
        
        wait(for: [x2, y2], timeout: expTimeout)
        
        query.removeChangeListener(withToken: token1)
        query.removeChangeListener(withToken: token2)
        XCTAssertEqual(count1, 2)
        XCTAssertEqual(count2, 2)
    }
    
    func testLiveQueryUpdateQueryParam() throws {
        try loadNumbers(100)
        let x1 = expectation(description: "1st change")
        let x2 = expectation(description: "1st change")
        let query = QueryBuilder
            .select(SelectResult.property("number1"))
            .from(DataSource.collection(defaultCollection!))
            .where(Expression.property("number1").lessThan(Expression.parameter("param")))
            .orderBy(Ordering.property("number1"))
        
        // set the param
        query.parameters = Parameters().setInt(10, forName: "param")
        
        var count = 0;
        let token = query.addChangeListener { (change) in
            count = count + 1
            let rows =  Array(change.results!)
            if count == 1 {
                XCTAssertEqual(rows.count, 9)
                x1.fulfill()
            } else {
                XCTAssertEqual(rows.count, 4)
                x2.fulfill()
            }
        }
        wait(for: [x1], timeout: expTimeout)
        query.parameters = Parameters().setInt(5, forName: "param")
        
        wait(for: [x2], timeout: expTimeout)
        query.removeChangeListener(withToken: token)
        XCTAssertEqual(count, 2)
    }
}
