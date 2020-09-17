//
//  ArrayTest.swift
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

class ArrayTest: CBLTestCase {
    
    let kTestDate = "2017-01-01T00:00:00.000Z"
    let kTestBlob = "i'm blob"
    
    func arrayOfAllTypes() -> [Any] {
        var array = [Any]()
        array.append(true)                              // 0
        array.append("string")                          // 1
        array.append(17)                                // 2
        array.append(23.0)                              // 3
        array.append(dateFromJson(kTestDate))           // 4
        
        var dict = [String:String]()
        dict["name"] = "Scott"
        array.append(dict)                              // 5
        
        var subarray = [String]()
        subarray.append("a")
        subarray.append("b")
        subarray.append("c")
        array.append(subarray)                          // 6
        
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        array.append(blob)                              // 7
        
        array.append(NSNull())                          // 8
        
        return array
    }
    
    func testEnumeratingArray() throws {
        let array = MutableArrayObject()
        for i in 0...19 {
            array.addValue(i)
        }
        var content = array.toArray()
        
        var result: [Any] = []
        for item in array {
            result.append(item)
        }
        XCTAssert(result == content)
        
        // Update:
        array.removeValue(at: 1)
        array.addValue(20)
        array.addValue(21)
        content = array.toArray()
        
        result = []
        for item in array {
            result.append(item)
        }
        XCTAssert(result == content)
        
        let doc = createDocument("doc1")
        doc.setValue(array, forKey: "array")
        
        try saveDocument(doc) { (d) in
            let a = d.array(forKey: "array")!
            result = []
            for item in a {
                result.append(item)
            }
            XCTAssert(result == content)
        }
    }
    
    func testToMutable() throws {
        let mArray1 = MutableArrayObject()
        mArray1.addValue("Scott")
        
        let mArray2 = mArray1.toMutable()
        XCTAssert(mArray1 !== mArray2)
        XCTAssert(mArray1.toArray() == mArray2.toArray())
        mArray2.addValue("Daniel")
        XCTAssert(mArray2.toArray() == (["Scott", "Daniel"]))
        
        let mDoc = createDocument("doc1")
        mDoc.setValue(mArray2, forKey: "array")
        try saveDocument(mDoc)
        
        let doc = self.db.document(withID: "doc1")!
        let array = doc.array(forKey: "array")!
        XCTAssert(array.toArray() == (["Scott", "Daniel"]))
        
        let mArray3 = array.toMutable()
        XCTAssert(mArray3.toArray() == (["Scott", "Daniel"]))
        mArray3.addValue("Thomas")
        XCTAssert(mArray3.toArray() == (["Scott", "Daniel", "Thomas"]))
    }
    
    func testAddMethodsIndividually() throws {
        let data = arrayOfAllTypes()
        let array = MutableArrayObject()
        array.addBoolean(data[0] as! Bool)
        array.addString(data[1] as? String)
        
        array.addInt(data[2] as! Int)
        array.addInt64(Int64(data[2] as! Int))
        array.addNumber(NSNumber(integerLiteral: (data[2] as! Int)))
        
        array.addDouble(data[3] as! Double)
        array.addFloat(Float(data[3] as! Double))
        
        array.addDate(data[4] as? Date)
        let dict = MutableDictionaryObject(data: data[5] as! [String: String])
        array.addDictionary(dict)
        let subarray = MutableArrayObject(data: data[6] as! [String])
        array.addArray(subarray)
        array.addBlob(data[7] as? Blob)
        array.addValue(data[8] as? NSNull)
        
        let doc = createDocument("doc1")
        doc.setArray(array, forKey: "array")
        try saveDocument(doc) { (d) in
            verifyResultsMethodsIndividually(d.array(forKey: "array")!, data: data)
        }
    }
    
    func testSetMethodsIndividually() throws {
        let data = arrayOfAllTypes()
        let array = MutableArrayObject()
        for _ in 0...11 {
            array.addValue(NSNull())
        }
        array.setBoolean(data[0] as! Bool, at: 0)
        array.setString(data[1] as? String, at: 1)
        
        array.setInt(data[2] as! Int, at: 2)
        array.setInt64(Int64(data[2] as! Int), at: 3)
        array.setNumber(NSNumber(integerLiteral: data[2] as! Int), at: 4)
        
        array.setDouble(data[3] as! Double, at: 5)
        array.setFloat(Float(data[3] as! Double), at: 6)
        
        array.setDate(data[4] as? Date, at: 7)
        
        let dict = MutableDictionaryObject(data: data[5] as! [String: String])
        array.setDictionary(dict, at: 8)
        
        let subarray = MutableArrayObject(data: data[6] as! [String])
        array.setArray(subarray, at: 9)
        array.setBlob(data[7] as? Blob, at: 10)
        array.setValue((data[8] as? NSNull), at: 11)
        
        let doc = createDocument("doc1")
        doc.setArray(array, forKey: "array")
        try saveDocument(doc) { (d) in
            verifyResultsMethodsIndividually(d.array(forKey: "array")!, data: data)
        }
    }
    
    func testInsertMethodsIndividually() throws {
        let data = arrayOfAllTypes()
        let array = MutableArrayObject()
        for _ in 0...11 {
            array.addValue(NSNull())
        }
        array.insertBoolean(data[0] as! Bool, at: 0)
        array.insertString(data[1] as? String, at: 1)
        
        array.insertInt(data[2] as! Int, at: 2)
        array.insertInt64(Int64(data[2] as! Int), at: 3)
        array.insertNumber(NSNumber(integerLiteral: data[2] as! Int), at: 4)
        
        array.insertDouble(data[3] as! Double, at: 5)
        array.insertFloat(Float(data[3] as! Double), at: 6)
        
        array.insertDate(data[4] as? Date, at: 7)
        
        let dict = MutableDictionaryObject(data: data[5] as! [String: String])
        array.insertDictionary(dict, at: 8)
        
        let subarray = MutableArrayObject(data: data[6] as! [String])
        array.insertArray(subarray, at: 9)
        array.insertBlob(data[7] as? Blob, at: 10)
        array.insertValue(data[8] as? NSNull, at: 11)
        
        let doc = createDocument("doc1")
        doc.setArray(array, forKey: "array")
        try saveDocument(doc) { (d) in
            verifyResultsMethodsIndividually(d.array(forKey: "array")!, data: data)
        }
    }
    
    // this method is tightly depended on the order of data which is inserted
    func verifyResultsMethodsIndividually(_ obj: ArrayObject, data: [Any]) {
        XCTAssertEqual(obj.boolean(at: 0), data[0] as! Bool)
        XCTAssertEqual(obj.string(at: 1), data[1] as? String)
        
        XCTAssertEqual(obj.int(at: 2), data[2] as! Int)
        XCTAssertEqual(obj.int64(at: 3), Int64(data[2] as! Int))
        XCTAssertEqual(obj.number(at: 4), NSNumber(integerLiteral: data[2] as! Int))
        
        XCTAssertEqual(obj.double(at: 5), data[3] as! Double)
        XCTAssertEqual(obj.float(at: 6), Float(data[3] as! Double))
        
        XCTAssert(obj.date(at: 7)!.timeIntervalSince((data[4] as! Date)) < 1.0)
        XCTAssertEqual(obj.dictionary(at: 8),
                       MutableDictionaryObject(data: data[5] as! [String: String]))
        XCTAssertEqual(obj.array(at: 9),
                       MutableArrayObject(data: data[6] as! [String]))
        let b = obj.blob(at: 10)
        XCTAssertEqual(b?.content, (data[7] as! Blob).content)
        XCTAssert(obj.value(at: 11) as! NSNull == (data[8] as! NSNull))
    }
}
