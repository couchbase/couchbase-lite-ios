//
//  PredictiveQueryTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc. All rights reserved.
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
import CouchbaseLiteSwift

class PredictiveQueryTest: CBLTestCase {
    
    override func setUp() {
        super.setUp()
        Database.prediction.unregisterModel(withName: AggregateModel.name)
        Database.prediction.unregisterModel(withName: TextModel.name)
    }
    
    @discardableResult
    func createDocument(withNumbers numbers: [Int]) -> MutableDocument {
        let doc = MutableDocument()
        doc.setValue(numbers, forKey: "numbers")
        try! db.saveDocument(doc)
        return doc
    }
    
    func testRegisterUnregisterModel() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        let q = QueryBuilder
            .select(SelectResult.property("numbers"), SelectResult.expression(prediction))
            .from(DataSource.database(db))
        
        // Query before registering the model:
        expectError(domain: "CouchbaseLite.SQLite", code: 1) {
            _ = try q.execute()
        }
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
            
            let pred = r.dictionary(at: 1)!
            XCTAssertEqual(pred.int(forKey: "sum"), numbers.value(forKeyPath: "@sum.self") as! Int)
            XCTAssertEqual(pred.int(forKey: "min"), numbers.value(forKeyPath: "@min.self") as! Int)
            XCTAssertEqual(pred.int(forKey: "max"), numbers.value(forKeyPath: "@max.self") as! Int)
            XCTAssertEqual(pred.int(forKey: "avg"), numbers.value(forKeyPath: "@avg.self") as! Int)
        }
        XCTAssertEqual(rows, 2);
        
        aggregateModel.unregisterModel()
        
        // Query after unregistering the model:
        expectError(domain: "CouchbaseLite.SQLite", code: 1) {
            _ = try q.execute()
        }
    }
    
    func testQueryDictionaryResult() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        let q = QueryBuilder
            .select(SelectResult.property("numbers"), SelectResult.expression(prediction))
            .from(DataSource.database(db))
        
        let rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
            
            let pred = r.dictionary(at: 1)!
            XCTAssertEqual(pred.int(forKey: "sum"), numbers.value(forKeyPath: "@sum.self") as! Int)
            XCTAssertEqual(pred.int(forKey: "min"), numbers.value(forKeyPath: "@min.self") as! Int)
            XCTAssertEqual(pred.int(forKey: "max"), numbers.value(forKeyPath: "@max.self") as! Int)
            XCTAssertEqual(pred.int(forKey: "avg"), numbers.value(forKeyPath: "@avg.self") as! Int)
        }
        XCTAssertEqual(rows, 2);
    }
    
    func testQueryValueFromDictionaryResult() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        let q = QueryBuilder
            .select(SelectResult.property("numbers"), SelectResult.expression(prediction.property("sum")).as("sum"))
            .from(DataSource.database(db))
        
        let rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
            
            let sum = r.int(at: 1)
            XCTAssertEqual(sum, numbers.value(forKeyPath: "@sum.self") as! Int)
        }
        XCTAssertEqual(rows, 2);
        
        aggregateModel.unregisterModel()
    }
    
    func testQueryWithBlobProperty() throws {
        let texts = [
            "Knox on fox in socks in box. Socks on Knox and Knox in box.",
            "Clocks on fox tick. Clocks on Knox tock. Six sick bricks tick. Six sick chicks tock."
        ]
        
        for text in texts {
            let doc = MutableDocument()
            doc.setBlob(blobForString(text), forKey: "text")
            try db.saveDocument(doc)
        }
        
        let textModel = TextModel()
        textModel.registerModel()
        
        let model = TextModel.name
        let input = Expression.dictionary(["text" : ["BLOB", ".text"]])
        let prediction = Function.prediction(model: model, input: input)
        
        let q = QueryBuilder
            .select(SelectResult.property("text"), SelectResult.expression(prediction.property("wc")).as("wc"))
            .from(DataSource.database(db))
            .where(prediction.property("wc").greaterThan(Expression.value(15)))
        
        let rows = try verifyQuery(q) { (n, r) in
            let blob = r.blob(forKey: "text")!
            let text = String(bytes: blob.content!, encoding: .utf8)!
            XCTAssertEqual(text, texts[1])
            XCTAssertEqual(r.int(forKey: "wc"), 16)
        }
        XCTAssertEqual(rows, 1);
        
        textModel.unregisterModel()
    }
    
    func testQueryWithBlobParameter() throws {
        try db.saveDocument(MutableDocument())
        
        let textModel = TextModel()
        textModel.registerModel()
        
        let model = TextModel.name
        let input = Expression.dictionary(["text" : Expression.parameter("text")])
        let prediction = Function.prediction(model: model, input: input)
        
        let q = QueryBuilder
            .select(SelectResult.expression(prediction.property("wc")).as("wc"))
            .from(DataSource.database(db))
        
        let params = Parameters()
        params.setBlob(blobForString("Knox on fox in socks in box. Socks on Knox and Knox in box."), forName: "text")
        q.parameters = params
        
        let rows = try verifyQuery(q) { (n, r) in
            XCTAssertEqual(r.int(at: 0), 14)
        }
        XCTAssertEqual(rows, 1);
        
        textModel.unregisterModel()
    }
    
    func testIndexPredictionValue() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        
        let index = IndexBuilder.valueIndex(items: ValueIndexItem.expression(prediction.property("sum")))
        try db.createIndex(index, withName: "SumIndex")
        
        let q = QueryBuilder
            .select(SelectResult.property("numbers"), SelectResult.expression(prediction.property("sum")).as("sum"))
            .from(DataSource.database(db))
            .where(prediction.property("sum").equalTo(Expression.value(15)))
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "USING INDEX SumIndex").location, NSNotFound)
        
        let rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
            
            let sum = r.int(at: 1)
            XCTAssertEqual(sum, numbers.value(forKeyPath: "@sum.self") as! Int)
        }
        XCTAssertEqual(rows, 1);
        XCTAssertEqual(aggregateModel.numberOfCalls, 2);
    }
    
    func testIndexMultiplePredictionValues() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        
        let sumIndex = IndexBuilder.valueIndex(items: ValueIndexItem.expression(prediction.property("sum")))
        try db.createIndex(sumIndex, withName: "SumIndex")
        
        let avgIndex = IndexBuilder.valueIndex(items: ValueIndexItem.expression(prediction.property("avg")))
        try db.createIndex(avgIndex, withName: "AvgIndex")
        
        let q = QueryBuilder
            .select(SelectResult.expression(prediction.property("sum")).as("sum"),
                    SelectResult.expression(prediction.property("avg")).as("avg"))
            .from(DataSource.database(db))
            .where(prediction.property("sum").lessThanOrEqualTo(Expression.value(15)).or(
                   prediction.property("avg").equalTo(Expression.value(8))))
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "USING INDEX SumIndex").location, NSNotFound)
        XCTAssertNotEqual(explain.range(of: "USING INDEX AvgIndex").location, NSNotFound)
        
        let rows = try verifyQuery(q) { (n, r) in
            XCTAssert(r.int(at: 0) == 15 || r.int(at: 1) == 8)
        }
        XCTAssertEqual(rows, 2);
    }
    
    func testIndexCompoundPredictiveValues() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        
        let index = IndexBuilder.valueIndex(items: ValueIndexItem.expression(prediction.property("sum")),
                                                   ValueIndexItem.expression(prediction.property("avg")))
        try db.createIndex(index, withName: "SumAvgIndex")
        
        let q = QueryBuilder
            .select(SelectResult.expression(prediction.property("sum")).as("sum"),
                    SelectResult.expression(prediction.property("avg")).as("avg"))
            .from(DataSource.database(db))
            .where(prediction.property("sum").equalTo(Expression.value(15)).and(
                   prediction.property("avg").equalTo(Expression.value(3))))
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "USING INDEX SumAvgIndex").location, NSNotFound)
        
        let rows = try verifyQuery(q) { (n, r) in
            XCTAssertEqual(r.int(at: 0), 15)
            XCTAssertEqual(r.int(at: 1), 3)
        }
        XCTAssertEqual(rows, 1);
        XCTAssertEqual(aggregateModel.numberOfCalls, 4);
    }
    
    func testEuclidientDistance() throws {
        let tests: [[Any]] = [
            [[10, 10], [13, 14], 5],
            [[1,2, 3], [1, 2, 3], 0],
            [[], [], 0],
            [[1, 2], [1, 2, 3], NSNull()],
            [[1, 2], "foo", NSNull()]
        ]
        
        for test in tests {
            let doc = MutableDocument()
            doc.setValue(test[0], forKey: "v1")
            doc.setValue(test[1], forKey: "v2")
            doc.setValue(test[2], forKey: "distance")
            try db.saveDocument(doc)
        }
        
        let distance = Function.euclideanDistance(between: Expression.property("v1"),
                                                      and: Expression.property("v2"))
        let q = QueryBuilder
            .select(SelectResult.expression(distance), SelectResult.property("distance"))
            .from(DataSource.database(db))
        
        
        let rows = try verifyQuery(q) { (n, r) in
            XCTAssertEqual(r.int(at: 0), r.int(at: 1))
        }
        XCTAssertEqual(Int(rows), tests.count);
    }
    
    func testSquaredEuclidientDistance() throws {
        let tests: [[Any]] = [
            [[10, 10], [13, 14], 25],
            [[1,2, 3], [1, 2, 3], 0],
            [[], [], 0],
            [[1, 2], [1, 2, 3], NSNull()],
            [[1, 2], "foo", NSNull()]
        ]
        
        for test in tests {
            let doc = MutableDocument()
            doc.setValue(test[0], forKey: "v1")
            doc.setValue(test[1], forKey: "v2")
            doc.setValue(test[2], forKey: "distance")
            try db.saveDocument(doc)
        }
        
        let distance = Function.squaredEuclideanDistance(between: Expression.property("v1"),
                                                             and: Expression.property("v2"))
        let q = QueryBuilder
            .select(SelectResult.expression(distance), SelectResult.property("distance"))
            .from(DataSource.database(db))
        
        
        let rows = try verifyQuery(q) { (n, r) in
            if r.value(at: 1) == nil {
                XCTAssertNil(r.value(at: 0))
            } else {
                XCTAssertEqual(r.double(at: 0), r.double(at: 1))
            }
        }
        XCTAssertEqual(Int(rows), tests.count);
    }
    
    func testCosineDistance() throws {
        let tests: [[Any]] = [
            [[10, 0], [0, 99], 1.0],
            [[1, 2, 3], [1, 2, 3], 0.0],
            [[1, 0, -1], [-1, -1, 0], 1.5],
            [[], [], NSNull()],
            [[1, 2], [1, 2, 3], NSNull()],
            [[1, 2], "foo", NSNull()]
        ]
        
        for test in tests {
            let doc = MutableDocument()
            doc.setValue(test[0], forKey: "v1")
            doc.setValue(test[1], forKey: "v2")
            doc.setValue(test[2], forKey: "distance")
            try db.saveDocument(doc)
        }
        
        let distance = Function.cosineDistance(between: Expression.property("v1"),
                                                   and: Expression.property("v2"))
        let q = QueryBuilder
            .select(SelectResult.expression(distance), SelectResult.property("distance"))
            .from(DataSource.database(db))
        
        let rows = try verifyQuery(q) { (n, r) in
            if r.value(at: 1) == nil {
                XCTAssertNil(r.value(at: 0))
            } else {
                XCTAssertEqual(r.double(at: 0), r.double(at: 1))
            }
        }
        XCTAssertEqual(Int(rows), tests.count);
    }
}

// MARK: Models

class TestPredictiveModel: PredictiveModel {
    
    class var name: String {
        return "Untitled"
    }
    
    var numberOfCalls = 0
    
    func prediction(input: DictionaryObject) -> DictionaryObject? {
        numberOfCalls = numberOfCalls + 1
        return self.predict(input: input)
    }

    func predict(input: DictionaryObject) -> DictionaryObject? {
        return nil
    }

    func registerModel() {
        Database.prediction.registerModel(self, withName: type(of: self).name)
    }

    func unregisterModel() {
        Database.prediction.unregisterModel(withName: type(of: self).name)
    }

    func reset() {
        numberOfCalls = 0
    }
}

class AggregateModel: TestPredictiveModel {
    
    override class var name: String {
        return "AggregateModel"
    }
    
    override func predict(input: DictionaryObject) -> DictionaryObject? {
        guard let numbers = input.array(forKey: "numbers")?.toArray() as NSArray? else {
            NSLog("WARNING: numbers is nil")
            return nil
        }
        
        let output = MutableDictionaryObject()
        output.setValue(numbers.value(forKeyPath: "@sum.self"), forKey: "sum")
        output.setValue(numbers.value(forKeyPath: "@min.self"), forKey: "min")
        output.setValue(numbers.value(forKeyPath: "@max.self"), forKey: "max")
        output.setValue(numbers.value(forKeyPath: "@avg.self"), forKey: "avg")
        return output
    }
    
}

class TextModel: TestPredictiveModel {
    
    override class var name: String {
        return "TextModel"
    }
    
    override func predict(input: DictionaryObject) -> DictionaryObject? {
        guard let blob = input.blob(forKey: "text") else {
            NSLog("WARNING: text is nil")
            return nil
        }
        
        let text =  String(bytes: blob.content!, encoding: .utf8)! as NSString
        
        var wc = 0
        var sc = 0
        var curSentLoc = NSNotFound
        text.enumerateLinguisticTags(in: NSRange(location: 0, length: text.length),
                                 scheme: NSLinguisticTagSchemeTokenType,
                                options: [], orthography: nil)
        { (tag, token, sent, stop) in
            if tag == NSLinguisticTagWord {
                wc = wc + 1
            }
            
            if sent.location != NSNotFound && curSentLoc != sent.location {
                curSentLoc = sent.location
                sc = sc + 1
            }
        }
        
        let output = MutableDictionaryObject()
        output.setInt(wc, forKey: "wc")
        output.setInt(sc, forKey: "sc")
        return output
    }
    
}
