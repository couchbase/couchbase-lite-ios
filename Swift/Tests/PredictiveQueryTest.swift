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
        Database.prediction.unregisterModel(withName: EchoModel.name)
    }
    
    @discardableResult
    func createDocument(withNumbers numbers: [Int]) -> MutableDocument {
        let doc = MutableDocument()
        doc.setValue(numbers, forKey: "numbers")
        try! db.saveDocument(doc)
        return doc
    }
    
    func testRegisterAndUnregisterModel() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        let q = QueryBuilder
            .select(SelectResult.expression(prediction))
            .from(DataSource.database(db))
        
        // Query before registering the model:
        expectError(domain: "CouchbaseLite.SQLite", code: 1) {
            _ = try q.execute()
        }
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let rows = try verifyQuery(q) { (n, r) in
            let pred = r.dictionary(at: 0)!
            XCTAssertEqual(pred.int(forKey: "sum"), 15)
        }
        XCTAssertEqual(rows, 1);
        
        aggregateModel.unregisterModel()
        
        // Query after unregistering the model:
        expectError(domain: "CouchbaseLite.SQLite", code: 1) {
            _ = try q.execute()
        }
    }
    
    func testRegisterMultipleModelsWithSameName() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        
        let model = "TheModel"
        let aggregateModel = AggregateModel()
        Database.prediction.registerModel(aggregateModel, withName: model)
        
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        let q = QueryBuilder
            .select(SelectResult.expression(prediction))
            .from(DataSource.database(db))
        var rows = try verifyQuery(q) { (n, r) in
            let pred = r.dictionary(at: 0)!
            XCTAssertEqual(pred.int(forKey: "sum"), 15)
        }
        XCTAssertEqual(rows, 1);
        
        // Register a new model with the same name:
        let echoModel = EchoModel()
        Database.prediction.registerModel(echoModel, withName: model)
        
        // Query again should use the new model:
        rows = try verifyQuery(q) { (n, r) in
            let pred = r.dictionary(at: 0)!
            XCTAssertNil(pred.value(forKey: "sum"))
            XCTAssert(pred.array(forKey: "numbers")!.toArray() == [1, 2, 3, 4, 5])
        }
        XCTAssertEqual(rows, 1);
        
        Database.prediction.unregisterModel(withName: model)
    }
    
    func testPredictionInputOutput() throws {
        // Register echo model:
        let echoModel = EchoModel()
        echoModel.registerModel()
        
        // Create a doc:
        let doc = self.createDocument()
        doc.setString("Daniel", forKey: "name")
        doc.setInt(2, forKey: "number")
        try self.saveDocument(doc)
        
        // Create prediction function input:
        let date = Date()
        let dateStr = jsonFromDate(date)
        let power = Function.power(base: Expression.property("number"), exponent: Expression.value(2))
        let dict: [String: Any] = [
            // Literal:
            "number1": 10,
            "number2": 10.1,
            "boolean": true,
            "string": "hello",
            "date": date,
            "null": NSNull(),
            "dict": ["foo": "bar"],
            "array": ["1", "2", "3"],
            // Expression:
            "expr_property": Expression.property("name"),
            "expr_value_number1": Expression.value(20),
            "expr_value_number2": Expression.value(20.1),
            "expr_value_boolean": Expression.value(true),
            "expr_value_string": Expression.value("hi"),
            "expr_value_date": Expression.value(date),
            "expr_value_null": Expression.value(nil),
            "expr_value_dict": Expression.value(["ping": "pong"]),
            "expr_value_array": Expression.value(["4", "5", "6"]),
            "expr_power": power
        ]
        
        // Execute query and validate output:
        let input = Expression.value(dict)
        let model = EchoModel.name
        let prediction = Function.prediction(model: model, input: input)
        let q = QueryBuilder
            .select(SelectResult.expression(prediction))
            .from(DataSource.database(db))
        let rows = try verifyQuery(q) { (n, r) in
            let pred = r.dictionary(at: 0)!
            XCTAssertEqual(pred.count, dict.count)
            // Literal:
            XCTAssertEqual(pred.int(forKey: "number1"), 10)
            XCTAssertEqual(pred.double(forKey: "number2"), 10.1)
            XCTAssertEqual(pred.boolean(forKey: "boolean"), true)
            XCTAssertEqual(pred.string(forKey: "string"), "hello")
            XCTAssertEqual(jsonFromDate(pred.date(forKey: "date")!), dateStr)
            XCTAssertEqual(pred.value(forKey: "null") as! NSNull,  NSNull())
            XCTAssert(pred.dictionary(forKey: "dict")!.toDictionary() ==  ["foo": "bar"] as [String: Any])
            XCTAssert(pred.array(forKey: "array")!.toArray() == ["1", "2", "3"])
            // Expression:
            XCTAssertEqual(pred.string(forKey: "expr_property"), "Daniel")
            XCTAssertEqual(pred.int(forKey: "expr_value_number1"), 20)
            XCTAssertEqual(pred.double(forKey: "expr_value_number2"), 20.1)
            XCTAssertEqual(pred.boolean(forKey: "expr_value_boolean"), true)
            XCTAssertEqual(pred.string(forKey: "expr_value_string"), "hi")
            XCTAssertEqual(jsonFromDate(pred.date(forKey: "expr_value_date")!), dateStr)
            XCTAssertEqual(pred.value(forKey: "expr_value_null") as! NSNull,  NSNull())
            XCTAssert(pred.dictionary(forKey: "expr_value_dict")!.toDictionary() ==  ["ping": "pong"] as [String: Any])
            XCTAssert(pred.array(forKey: "expr_value_array")!.toArray() == ["4", "5", "6"])
            XCTAssertEqual(pred.int(forKey: "expr_power"), 4)
        }
        XCTAssertEqual(rows, 1);
        
        echoModel.unregisterModel()
    }
    
    func failing_testPredictionWithBlobPropertyInput() throws {
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
        let input = Expression.dictionary(["text" : Expression.property("text")])
        let prediction = Function.prediction(model: model, input: input)
        
        let q = QueryBuilder
            .select(SelectResult.property("text"),
                    SelectResult.expression(prediction.property("wc")).as("wc"))
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
    
    func testPredictionWithBlobParameterInput() throws {
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
        params.setBlob(blobForString("Knox on fox in socks in box. Socks on Knox and Knox in box."),
                       forName: "text")
        q.parameters = params
        
        let rows = try verifyQuery(q) { (n, r) in
            XCTAssertEqual(r.int(at: 0), 14)
        }
        XCTAssertEqual(rows, 1);
        
        textModel.unregisterModel()
    }
    
    func testPredictionWithNonSupportedInputTypes() throws {
        let echoModel = EchoModel()
        echoModel.registerModel()
        
        // Query with non dictionary input:
        let model = EchoModel.name
        let input = Expression.value("string")
        let prediction = Function.prediction(model: model, input: input)
        let q = QueryBuilder
            .select(SelectResult.expression(prediction))
            .from(DataSource.database(db))
        
        expectError(domain: "CouchbaseLite.SQLite", code: 1) {
            _ = try q.execute()
        }
        
        // Query with non-supported value type in dictionary input.
        // Note: The code below will crash the test as Swift cannot handle exception thrown by
        // Objective-C
        //
        // let input2 = Expression.value(["key": self])
        // let prediction2 = Function.prediction(model: model, input: input2)
        // let q2 = QueryBuilder
        //    .select(SelectResult.expression(prediction2))
        //    .from(DataSource.database(db))
        // try q2.execute()
        
        echoModel.unregisterModel()
    }
    
    func testQueryPredictionResultDictionary() throws {
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
        
        aggregateModel.unregisterModel()
    }
    
    func testQueryPredictionValues() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        let q = QueryBuilder
            .select(SelectResult.property("numbers"),
                    SelectResult.expression(prediction.property("sum")).as("sum"),
                    SelectResult.expression(prediction.property("min")).as("min"),
                    SelectResult.expression(prediction.property("max")).as("max"),
                    SelectResult.expression(prediction.property("avg")).as("avg"))
            .from(DataSource.database(db))
        
        let rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
            
            let sum = r.int(at: 1)
            let min = r.int(at: 2)
            let max = r.int(at: 3)
            let avg = r.int(at: 4)
            
            XCTAssertEqual(sum, r.int(forKey: "sum"))
            XCTAssertEqual(min, r.int(forKey: "min"))
            XCTAssertEqual(max, r.int(forKey: "max"))
            XCTAssertEqual(avg, r.int(forKey: "avg"))
            
            XCTAssertEqual(sum, numbers.value(forKeyPath: "@sum.self") as! Int)
            XCTAssertEqual(min, numbers.value(forKeyPath: "@min.self") as! Int)
            XCTAssertEqual(max, numbers.value(forKeyPath: "@max.self") as! Int)
            XCTAssertEqual(avg, numbers.value(forKeyPath: "@avg.self") as! Int)
        }
        XCTAssertEqual(rows, 2);
        
        aggregateModel.unregisterModel()
    }
    
    func testWhereUsingPredictionValues() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        let q = QueryBuilder
            .select(SelectResult.property("numbers"),
                    SelectResult.expression(prediction.property("sum")).as("sum"),
                    SelectResult.expression(prediction.property("min")).as("min"),
                    SelectResult.expression(prediction.property("max")).as("max"),
                    SelectResult.expression(prediction.property("avg")).as("avg"))
            .from(DataSource.database(db))
            .where(prediction.property("sum").equalTo(Expression.value(15)))
        
        let rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
            
            let sum = r.int(at: 1)
            XCTAssertEqual(sum, 15)
            
            let min = r.int(at: 2)
            let max = r.int(at: 3)
            let avg = r.int(at: 4)
            
            XCTAssertEqual(sum, r.int(forKey: "sum"))
            XCTAssertEqual(min, r.int(forKey: "min"))
            XCTAssertEqual(max, r.int(forKey: "max"))
            XCTAssertEqual(avg, r.int(forKey: "avg"))
            
            XCTAssertEqual(sum, numbers.value(forKeyPath: "@sum.self") as! Int)
            XCTAssertEqual(min, numbers.value(forKeyPath: "@min.self") as! Int)
            XCTAssertEqual(max, numbers.value(forKeyPath: "@max.self") as! Int)
            XCTAssertEqual(avg, numbers.value(forKeyPath: "@avg.self") as! Int)
        }
        XCTAssertEqual(rows, 1);
        
        aggregateModel.unregisterModel()
    }
    
    func testOrderByUsingPredictionValues() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        let q = QueryBuilder
            .select(SelectResult.expression(prediction.property("sum")).as("sum"))
            .from(DataSource.database(db))
            .where(prediction.property("sum").greaterThan(Expression.value(1)))
            .orderBy(Ordering.expression(prediction.property("sum")).descending())
        
        var sums: [Int] = []
        let rows = try verifyQuery(q) { (n, r) in
            sums.append(r.int(at: 0))
        }
        XCTAssertEqual(rows, 2);
        XCTAssertEqual(sums, [40, 15])
        
        aggregateModel.unregisterModel()
    }
    
    func testPredictiveModelReturningNull() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        
        let doc = createDocument()
        doc.setString("Knox on fox in socks in box. Socks on Knox and Knox in box.", forKey: "text")
        try saveDocument(doc)
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        var q: Query = QueryBuilder
            .select(SelectResult.expression(prediction),
                    SelectResult.expression(prediction.property("sum")).as("sum"))
            .from(DataSource.database(db))
        
        var rows = try verifyQuery(q) { (n, r) in
            if n == 1 {
                XCTAssertNotNil(r.dictionary(at: 0))
                XCTAssertEqual(r.int(at: 1), 15)
            } else {
                XCTAssertNil(r.value(at: 0))
                XCTAssertNil(r.value(at: 1))
            }
        }
        XCTAssertEqual(rows, 2);
        
        // Evaluate with nullOrMissing:
        q = QueryBuilder
            .select(SelectResult.expression(prediction),
                    SelectResult.expression(prediction.property("sum")).as("sum"))
            .from(DataSource.database(db))
            .where(prediction.notNullOrMissing())
        
        rows = try verifyQuery(q) { (n, r) in
            XCTAssertNotNil(r.dictionary(at: 0))
            XCTAssertEqual(r.int(at: 1), 15)
        }
        XCTAssertEqual(rows, 1);
    }
    
    func testIndexPredictionValueUsingValueIndex() throws {
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
    
    func testIndexMultiplePredictionValuesUsingValueIndex() throws {
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
    
    func testIndexCompoundPredictiveValuesUsingValueIndex() throws {
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
    
    func testIndexPredictionResultUsingPredictiveIndex() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        
        let index = IndexBuilder.predictiveIndex(model: model, input: input)
        try db.createIndex(index, withName: "AggIndex")
        
        let q = QueryBuilder
            .select(SelectResult.property("numbers"),
                    SelectResult.expression(prediction.property("sum")).as("sum"))
            .from(DataSource.database(db))
            .where(prediction.property("sum").equalTo(Expression.value(15)))
        
        let explain = try q.explain() as NSString
        XCTAssertEqual(explain.range(of: "USING INDEX AggIndex").location, NSNotFound)
        
        let rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
            
            let sum = r.int(at: 1)
            XCTAssertEqual(sum, numbers.value(forKeyPath: "@sum.self") as! Int)
        }
        XCTAssertEqual(rows, 1);
        XCTAssertEqual(aggregateModel.numberOfCalls, 2);
        
        aggregateModel.unregisterModel()
    }
    
    func testIndexPredictionValueUsingPredictiveIndex() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        
        let index = IndexBuilder.predictiveIndex(model: model, input: input, properties: ["sum"])
        try db.createIndex(index, withName: "SumIndex")
        
        let q = QueryBuilder
            .select(SelectResult.property("numbers"),
                    SelectResult.expression(prediction.property("sum")).as("sum"))
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
        
        aggregateModel.unregisterModel()
    }
    
    func testIndexMultiplePredictionValuesUsingPredictiveIndex() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        
        let sumIndex = IndexBuilder.predictiveIndex(model: model, input: input, properties: ["sum"])
        try db.createIndex(sumIndex, withName: "SumIndex")
        
        let avgIndex = IndexBuilder.predictiveIndex(model: model, input: input, properties: ["avg"])
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
        XCTAssertEqual(aggregateModel.numberOfCalls, 2);
        
        aggregateModel.unregisterModel()
    }
    
    func testIndexCompoundPredictiveValuesUsingPredictiveIndex() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        
        let index = IndexBuilder.predictiveIndex(model: model, input: input, properties: ["sum", "avg"])
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
        XCTAssertEqual(aggregateModel.numberOfCalls, 2);
        
        aggregateModel.unregisterModel()
    }
    
    func testDeletePredictiveIndex() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        
        // Index:
        let index = IndexBuilder.predictiveIndex(model: model, input: input, properties: ["sum"])
        try db.createIndex(index, withName: "SumIndex")
        
        // Query with index:
        var q: Query = QueryBuilder
            .select(SelectResult.property("numbers"))
            .from(DataSource.database(db))
            .where(prediction.property("sum").equalTo(Expression.value(15)))
        var explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "USING INDEX SumIndex").location, NSNotFound)
        
        var rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
        }
        XCTAssertEqual(rows, 1);
        XCTAssertEqual(aggregateModel.numberOfCalls, 2);
        
        // Delete SumIndex:
        try db.deleteIndex(forName: "SumIndex")
        
        // Query again:
        aggregateModel.reset()
        q = QueryBuilder
            .select(SelectResult.property("numbers"))
            .from(DataSource.database(db))
            .where(prediction.property("sum").equalTo(Expression.value(15)))
        explain = try q.explain() as NSString
        XCTAssertEqual(explain.range(of: "USING INDEX SumIndex").location, NSNotFound)
        
        rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
        }
        XCTAssertEqual(rows, 1);
        XCTAssertEqual(aggregateModel.numberOfCalls, 2);
        
        aggregateModel.unregisterModel()
    }
    
    func testDeletePredictiveIndexesSharingSameCacheTable() throws {
        createDocument(withNumbers: [1, 2, 3, 4, 5])
        createDocument(withNumbers: [6, 7, 8, 9, 10])
        
        let aggregateModel = AggregateModel()
        aggregateModel.registerModel()
        
        let model = AggregateModel.name
        let input = Expression.value(["numbers": Expression.property("numbers")])
        let prediction = Function.prediction(model: model, input: input)
        
        // Create agg index:
        let aggIndex = IndexBuilder.predictiveIndex(model: model, input: input)
        try db.createIndex(aggIndex, withName: "AggIndex")
        
        // Create sum index:
        let sumIndex = IndexBuilder.predictiveIndex(model: model, input: input, properties: ["sum"])
        try db.createIndex(sumIndex, withName: "SumIndex")
        
        // Create avg index:
        let avgIndex = IndexBuilder.predictiveIndex(model: model, input: input, properties: ["avg"])
        try db.createIndex(avgIndex, withName: "AvgIndex")
        
        // Query:
        var q: Query = QueryBuilder
            .select(SelectResult.property("numbers"))
            .from(DataSource.database(db))
            .where(prediction.property("sum").lessThanOrEqualTo(Expression.value(15)).or(
                   prediction.property("avg").equalTo(Expression.value(8))))
        var explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "USING INDEX SumIndex").location, NSNotFound)
        XCTAssertNotEqual(explain.range(of: "USING INDEX AvgIndex").location, NSNotFound)
        
        var rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
        }
        XCTAssertEqual(rows, 2);
        XCTAssertEqual(aggregateModel.numberOfCalls, 2);
        
        // Delete SumIndex:
        try db.deleteIndex(forName: "SumIndex")
        
        // Note: when having only one index, SQLite optimizer doesn't utilize the index
        //       when using OR expr. Hence explicity test each index with two queries:
        aggregateModel.reset()
        q = QueryBuilder
        .select(SelectResult.property("numbers"))
        .from(DataSource.database(db))
        .where(prediction.property("sum").equalTo(Expression.value(15)))
        
        explain = try q.explain() as NSString
        XCTAssertEqual(explain.range(of: "USING INDEX SumIndex").location, NSNotFound)
        
        rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
        }
        XCTAssertEqual(rows, 1);
        XCTAssertEqual(aggregateModel.numberOfCalls, 0);
        
        aggregateModel.reset()
        q = QueryBuilder
            .select(SelectResult.property("numbers"))
            .from(DataSource.database(db))
            .where(prediction.property("avg").equalTo(Expression.value(8)))
        explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "USING INDEX AvgIndex").location, NSNotFound)
        
        rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
        }
        XCTAssertEqual(rows, 1);
        XCTAssertEqual(aggregateModel.numberOfCalls, 0);
        
        // Delete AvgIndex
        try db.deleteIndex(forName: "AvgIndex")
        
        aggregateModel.reset()
        q = QueryBuilder
            .select(SelectResult.property("numbers"))
            .from(DataSource.database(db))
            .where(prediction.property("avg").equalTo(Expression.value(8)))
        explain = try q.explain() as NSString
        XCTAssertEqual(explain.range(of: "USING INDEX AvgIndex").location, NSNotFound)
        
        rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
        }
        XCTAssertEqual(rows, 1);
        XCTAssertEqual(aggregateModel.numberOfCalls, 0);
        
        // Delete AggIndex
        try db.deleteIndex(forName: "AggIndex")
        
        aggregateModel.reset()
        q = QueryBuilder
            .select(SelectResult.property("numbers"))
            .from(DataSource.database(db))
            .where(prediction.property("sum").lessThanOrEqualTo(Expression.value(15)).or(
                prediction.property("avg").equalTo(Expression.value(8))))
        explain = try q.explain() as NSString
        XCTAssertEqual(explain.range(of: "USING INDEX SumIndex").location, NSNotFound)
        XCTAssertEqual(explain.range(of: "USING INDEX AvgIndex").location, NSNotFound)
        
        rows = try verifyQuery(q) { (n, r) in
            let numbers = r.array(at: 0)!.toArray() as NSArray
            XCTAssert(numbers.count > 0)
        }
        XCTAssertEqual(rows, 2);
        XCTAssert(aggregateModel.numberOfCalls > 0);
        
        aggregateModel.unregisterModel()
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
    
    func predict(input: DictionaryObject) -> DictionaryObject? {
        numberOfCalls = numberOfCalls + 1
        return self.doPredict(input: input)
    }

    func doPredict(input: DictionaryObject) -> DictionaryObject? {
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

class EchoModel: TestPredictiveModel {
    
    override class var name: String {
        return "EchoModel"
    }
    
    override func doPredict(input: DictionaryObject) -> DictionaryObject? {
        return input;
    }
    
}

class AggregateModel: TestPredictiveModel {
    
    override class var name: String {
        return "AggregateModel"
    }
    
    override func doPredict(input: DictionaryObject) -> DictionaryObject? {
        guard let numbers = input.array(forKey: "numbers")?.toArray() as NSArray? else {
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
    
    override func doPredict(input: DictionaryObject) -> DictionaryObject? {
        guard let blob = input.blob(forKey: "text") else {
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
