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
        
        let doc = try self.defaultCollection!.document(id: "doc1")!
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
    
    // MARK: toJSON
    
    func testUnsavedMutableArrayToJSON() throws {
        let json = "[{\"unsaved\":\"mutableDoc\"}]"
        var mArray = try MutableArrayObject(json: json)
        expectException(exception: .internalInconsistencyException) {
            let _ = mArray.toJSON()
        }
        
        let mDoc = MutableDocument(id: "doc")
        mDoc.setArray(mArray, forKey: "array")
        try saveDocument(mDoc)
        
        mArray = mDoc.array(forKey: "array")!
        expectException(exception: .internalInconsistencyException) {
            let _ = mArray.toJSON()
        }
    }
    
    func testArrayToJSON() throws {
        let json = "[\(try getRickAndMortyJSON()),\(try getRickAndMortyJSON())]"
        let mArray = try MutableArrayObject(json: json)
        let mDoc = MutableDocument(id: "doc")
        mDoc.setArray(mArray, forKey: "array")
        try self.defaultCollection!.save(document: mDoc)
        
        let doc = try self.defaultCollection!.document(id: "doc")
        guard let array = doc?.array(forKey: "array") else {
            XCTFail("Array not found in doc")
            return
        }
        
        let jsonArray = array.toJSON().toJSONObj() as! Array<[String: Any]>
        XCTAssertEqual(jsonArray[0]["id"] as! Int, 1)
        XCTAssertEqual(jsonArray[0]["name"] as! String, "Rick Sanchez")
        XCTAssertEqual(jsonArray[0]["isAlive"] as! Bool, true)
        XCTAssertEqual(jsonArray[0]["longitude"] as! Double, -21.152958)
        XCTAssertEqual((jsonArray[0]["aka"] as! Array<Any>)[2] as! String, "Albert Ein-douche")
        XCTAssertEqual((jsonArray[0]["family"] as! Array<[String: Any]>)[0]["name"] as! String, "Morty Smith")
        XCTAssertEqual((jsonArray[0]["family"] as! Array<[String: Any]>)[3]["name"] as! String, "Summer Smith")
    }
    
    func testGetBlobContentFromMutableObject() throws {
        let json = try getRickAndMortyJSON()
        let mDoc = try MutableDocument(id: "doc", json: json)
        var blob = mDoc.blob(forKey: "origin")
        
        // before save it should throw the exception
        expectException(exception: .internalInconsistencyException) {
            print("\(blob!.content?.count ?? 0)")
        }
        try self.defaultCollection!.save(document: mDoc)
        
        // after the save, it should return the content
        let doc = try self.defaultCollection!.document(id: "doc")
        blob = doc?.blob(forKey: "origin")
        XCTAssertNotNil(blob?.content)
    }
}
