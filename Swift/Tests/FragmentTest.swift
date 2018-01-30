//
//  FragmentTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift


class FragmentTest: CBLTestCase {
    func testBasicGetFragmentValues() throws {
        let dict: [String: Any] = ["name": "Jason",
                                   "address": [
                                    "street": "1 Main Street",
                                    "phones": ["mobile": "650-123-4567"]
                                    ],
                                   "references": [["name": "Scott"], ["name": "Sam"]]]
        let doc = createDocument("doc1")
        doc.setData(dict)
        
        XCTAssertEqual(doc["name"].string!, "Jason")
        XCTAssertEqual(doc["address"]["street"].string!, "1 Main Street")
        XCTAssertEqual(doc["address"]["phones"]["mobile"].string!, "650-123-4567")
        XCTAssertEqual(doc["references"][0]["name"].string!, "Scott")
        XCTAssertEqual(doc["references"][1]["name"].string!, "Sam")
        
        XCTAssertNil(doc["references"][2]["name"].value)
        XCTAssertNil(doc["dummy"]["dummy"]["dummy"].value)
        XCTAssertNil(doc["dummy"]["dummy"][0]["dummy"].value)
    }
    
    
    func testBasicSetFragmentValues() throws {
        let doc = createDocument("doc1")
        doc["name"].value = "Jason"
        
        doc["address"].value = MutableDictionaryObject()
        doc["address"]["street"].value = "1 Main Street"
        doc["address"]["phones"].value = MutableDictionaryObject()
        doc["address"]["phones"]["mobile"].value = "650-123-4567"
        
        XCTAssertEqual(doc["name"].string!, "Jason")
        XCTAssertEqual(doc["address"]["street"].string!, "1 Main Street")
        XCTAssertEqual(doc["address"]["phones"]["mobile"].string!, "650-123-4567")
    }
    
    
    func testGetDocFragmentWithID() throws {
        let dict: [String: Any] = ["address": [
                                    "street": "1 Main street",
                                    "city": "Mountain View",
                                    "state": "CA"]]
        try saveDocument(createDocument("doc1", data: dict))
        
        let doc = db["doc1"]
        XCTAssertNotNil(doc)
        XCTAssertTrue(doc.exists)
        XCTAssertNotNil(doc.document)
        XCTAssertEqual(doc["address"]["street"].string!, "1 Main street")
        XCTAssertEqual(doc["address"]["city"].string!, "Mountain View")
        XCTAssertEqual(doc["address"]["state"].string!, "CA")
    }
    
    
    func testGetDocFragmentWithNonExistingID() throws {
        let doc = db["doc1"]
        XCTAssertNotNil(doc)
        XCTAssertFalse(doc.exists)
        XCTAssertNil(doc["address"]["street"].string)
        XCTAssertNil(doc["address"]["city"].string)
        XCTAssertNil(doc["address"]["state"].string)
    }
    
    
    func testGetFragmentFromDictionaryValue() throws {
        let dict: [String: Any] = ["address": [
                                    "street": "1 Main street",
                                    "city": "Mountain View",
                                    "state": "CA"]]
        let doc = createDocument("doc1", data: dict)
        try saveDocument(doc) { (d) in
            let fragment = d["address"]
            XCTAssertNotNil(fragment)
            XCTAssert(fragment.exists)
            XCTAssertNil(fragment.string)
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 0)
            XCTAssertEqual(fragment.float, 0.0)
            XCTAssertEqual(fragment.double, 0.0)
            XCTAssertTrue(fragment.boolean)
            XCTAssertNil(fragment.array)
            XCTAssertNil(fragment.array)
            XCTAssertNotNil(fragment.value)
            XCTAssertNotNil(fragment.dictionary)
            XCTAssert(fragment.dictionary! === fragment.value as! DictionaryObject)
            XCTAssert(fragment.dictionary!.toDictionary() == dict["address"] as! [String: Any])
        }
    }
    
    
    func testGetFragmentFromArrayValue() throws {
        let dict: [String: Any] = ["references": [["name": "Scott"], ["name": "Sam"]]]
        let doc = createDocument("doc1", data: dict)
        try saveDocument(doc, eval: { (d) in
            let fragment = d["references"]
            XCTAssertNotNil(fragment)
            XCTAssert(fragment.exists)
            XCTAssertNil(fragment.string)
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 0)
            XCTAssertEqual(fragment.float, 0.0)
            XCTAssertEqual(fragment.double, 0.0)
            XCTAssertTrue(fragment.boolean)
            XCTAssertNotNil(fragment.array)
            XCTAssertNotNil(fragment.value)
            XCTAssert(fragment.array! === fragment.value as! ArrayObject)
            XCTAssert(fragment.array!.toArray() == dict["references"] as! [Any])
            XCTAssertNil(fragment.dictionary)
        })
    }
    
    
    func testGetFragmentFromInteger() throws {
        let doc = createDocument("doc1")
        doc.setValue(10, forKey: "integer")
        try saveDocument(doc, eval: { (d) in
            let fragment = d["integer"]
            XCTAssertNotNil(fragment)
            XCTAssert(fragment.exists)
            XCTAssertNil(fragment.string)
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 10)
            XCTAssertEqual(fragment.float, 10.0)
            XCTAssertEqual(fragment.double, 10.0)
            XCTAssertTrue(fragment.boolean)
            XCTAssertNil(fragment.array)
            XCTAssertEqual(fragment.value as! Int, 10)
            XCTAssertNil(fragment.dictionary)
        })
    }
    
    
    func testGetFragmentFromFloat() throws {
        let doc = createDocument("doc1")
        doc.setValue(Float(100.10), forKey: "float")
        try saveDocument(doc, eval: { (d) in
            let fragment = d["float"]
            XCTAssertNotNil(fragment)
            XCTAssert(fragment.exists)
            XCTAssertNil(fragment.string)
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 100)
            XCTAssertEqual(fragment.float, 100.10)
            XCTAssertEqual(fragment.double, 100.10, accuracy: 0.1)
            XCTAssertTrue(fragment.boolean)
            XCTAssertNil(fragment.array)
            XCTAssertEqual(fragment.value as! Float, 100.10)
            XCTAssertNil(fragment.dictionary)
        })
    }
    
    
    func testGetFragmentFromDouble() throws {
        let doc = createDocument("doc1")
        doc.setValue(Double(99.99), forKey: "double")
        try saveDocument(doc, eval: { (d) in
            let fragment = d["double"]
            XCTAssertNotNil(fragment)
            XCTAssert(fragment.exists)
            XCTAssertNil(fragment.string)
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 99)
            XCTAssertEqual(fragment.float, 99.99)
            XCTAssertEqual(fragment.double, 99.99)
            XCTAssertTrue(fragment.boolean)
            XCTAssertNil(fragment.array)
            XCTAssertEqual(fragment.value as! Double, 99.99)
            XCTAssertNil(fragment.dictionary)
        })
    }
    
    
    func testGetFragmentFromBoolean() throws {
        let doc = createDocument("doc1")
        doc.setValue(true, forKey: "boolean")
        try saveDocument(doc, eval: { (d) in
            let fragment = d["boolean"]
            XCTAssertNotNil(fragment)
            XCTAssert(fragment.exists)
            XCTAssertNil(fragment.string)
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 1)
            XCTAssertEqual(fragment.float, 1.0)
            XCTAssertEqual(fragment.double, 1.0)
            XCTAssertTrue(fragment.boolean)
            XCTAssertNil(fragment.array)
            XCTAssertEqual(fragment.value as! Bool, true)
            XCTAssertNil(fragment.dictionary)
        })
    }
    
    
    func testGetFragmentFromDate() throws {
        let date = Date()
        let dateStr = jsonFromDate(date)
        let doc = createDocument("doc1")
        doc.setValue(date, forKey: "date")
        try saveDocument(doc, eval: { (d) in
            let fragment = d["date"]
            XCTAssertNotNil(fragment)
            XCTAssert(fragment.exists)
            XCTAssertEqual(fragment.string!, dateStr)
            XCTAssertEqual(jsonFromDate(fragment.date!), dateStr)
            XCTAssertEqual(fragment.int, 0)
            XCTAssertEqual(fragment.float, 0.0)
            XCTAssertEqual(fragment.double, 0.0)
            XCTAssert(fragment.boolean)
            XCTAssertNil(fragment.array)
            XCTAssertEqual(fragment.value as! String, dateStr)
            XCTAssertNil(fragment.dictionary)
        })
    }

    
    func testGetFragmentFromString() throws {
        let doc = createDocument("doc1")
        doc.setValue("hello world", forKey: "string")
        try saveDocument(doc, eval: { (d) in
            let fragment = d["string"]
            XCTAssertNotNil(fragment)
            XCTAssert(fragment.exists)
            XCTAssertEqual(fragment.string!, "hello world")
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 0)
            XCTAssertEqual(fragment.float, 0.0)
            XCTAssertEqual(fragment.double, 0.0)
            XCTAssert(fragment.boolean)
            XCTAssertNil(fragment.array)
            XCTAssertEqual(fragment.value as! String, "hello world")
            XCTAssertNil(fragment.dictionary)
        })
    }
    
    
    func testGetNestedDictionaryFragment() throws {
        let dict: [String: Any] = ["address": [
                                    "street": "1 Main street",
                                    "phones": ["mobile": "650-123-4567"]]]
        let doc = createDocument("doc1", data: dict)
        try saveDocument(doc, eval: { (d) in
            let fragment = d["address"]["phones"]
            XCTAssertNotNil(fragment)
            XCTAssert(fragment.exists)
            XCTAssertNil(fragment.string)
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 0)
            XCTAssertEqual(fragment.float, 0.0)
            XCTAssertEqual(fragment.double, 0.0)
            XCTAssertTrue(fragment.boolean)
            XCTAssertNil(fragment.array)
            XCTAssertNil(fragment.array)
            XCTAssertNotNil(fragment.value)
            XCTAssertNotNil(fragment.dictionary)
            XCTAssert(fragment.dictionary! === fragment.value as! DictionaryObject)
            XCTAssert(fragment.dictionary!.toDictionary() ==
                (dict["address"] as! [String:Any])["phones"] as! [String: Any])
        })
    }
    
    
    func testGetNestedNonExistingDictionaryFragment() throws {
        let dict: [String: Any] = ["address": [
                                    "street": "1 Main street",
                                    "phones": ["mobile": "650-123-4567"]]]
        let doc = createDocument("doc1", data: dict)
        try saveDocument(doc, eval: { (d) in
            let fragment = d["address"]["country"]
            XCTAssertNotNil(fragment)
            XCTAssertFalse(fragment.exists)
            XCTAssertNil(fragment.string)
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 0)
            XCTAssertEqual(fragment.float, 0.0)
            XCTAssertEqual(fragment.double, 0.0)
            XCTAssertFalse(fragment.boolean)
            XCTAssertNil(fragment.array)
            XCTAssertNil(fragment.array)
            XCTAssertNil(fragment.value)
            XCTAssertNil(fragment.dictionary)
        })
    }

    
    func testGetNestedArrayFragments() throws {
        let dict: [String: Any] = ["nested-array": [[1, 2, 3], [4, 5, 6]]]
        let doc = createDocument("doc1", data: dict)
        try saveDocument(doc, eval: { (d) in
            let fragment = d["nested-array"]
            XCTAssertNotNil(fragment)
            XCTAssert(fragment.exists)
            XCTAssertNil(fragment.string)
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 0)
            XCTAssertEqual(fragment.float, 0.0)
            XCTAssertEqual(fragment.double, 0.0)
            XCTAssertTrue(fragment.boolean)
            XCTAssertNotNil(fragment.array)
            XCTAssertNotNil(fragment.value)
            XCTAssert(fragment.array! === fragment.value as! ArrayObject)
            XCTAssert(fragment.array!.toArray() == dict["nested-array"] as! [Any])
            XCTAssertNil(fragment.dictionary)
        })
    }
    
    
    func testGetNestedNonExistingArrayFragments() throws {
        let dict: [String: Any] = ["nested-array": [[1, 2, 3], [4, 5, 6]]]
        let doc = createDocument("doc1", data: dict)
        try saveDocument(doc, eval: { (d) in
            let fragment = d["nested-array"][2]
            XCTAssertNotNil(fragment)
            XCTAssertFalse(fragment.exists)
            XCTAssertNil(fragment.string)
            XCTAssertNil(fragment.date)
            XCTAssertEqual(fragment.int, 0)
            XCTAssertEqual(fragment.float, 0.0)
            XCTAssertEqual(fragment.double, 0.0)
            XCTAssertFalse(fragment.boolean)
            XCTAssertNil(fragment.array)
            XCTAssertNil(fragment.array)
            XCTAssertNil(fragment.value)
            XCTAssertNil(fragment.dictionary)
        })
    }
    
    
    func testDictionaryFragmentSet() throws {
        let date = Date()
        let doc = createDocument("doc1")
        doc["string"].value = "value"
        doc["bool"].value = true
        doc["int"].value = 7
        doc["float"].value = Float(2.2)
        doc["double"].value = Double(2.2)
        doc["date"].value = date
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d["string"].string!, "value")
            XCTAssertEqual(d["bool"].boolean, true)
            XCTAssertEqual(d["int"].int, 7)
            XCTAssertEqual(d["float"].float, Float(2.2))
            XCTAssertEqual(d["double"].double, Double(2.2))
            XCTAssertEqual(jsonFromDate(d["date"].date!), jsonFromDate(date))
        })
    }
    
    
    func testDictionaryFragmentsetData() throws {
        let data: [String: Any] = ["name": "Jason",
                                   "address": [
                                    "street": "1 Main street",
                                    "phones": ["mobile": "650-123-4567"]]]
        let doc = createDocument("doc1")
        let dict = MutableDictionaryObject(data: data)
        doc["dict"].value = dict
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d["dict"]["name"].string!, "Jason")
            XCTAssertEqual(d["dict"]["address"]["street"].string!, "1 Main street")
            XCTAssertEqual(d["dict"]["address"]["phones"]["mobile"].string!, "650-123-4567")
        })
    }
 
    
    func testDictionaryFragmentSetArray() throws {
        let doc = createDocument("doc1")
        let array = MutableArrayObject(data: [0, 1, 2])
        doc["array"].value = array
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d["array"][0].int, 0)
            XCTAssertEqual(d["array"][1].int, 1)
            XCTAssertEqual(d["array"][2].int, 2)
            XCTAssertNil(d["array"][3].value)
            XCTAssertFalse(d["array"][3].exists)
            XCTAssertEqual(d["array"][3].int, 0)
        })
    }
    
    
    func testDictionaryFragmentSetSwiftDict() throws {
        let data: [String: Any] = ["name": "Jason",
                                   "address": [
                                    "street": "1 Main street",
                                    "phones": ["mobile": "650-123-4567"]]]
        let doc = createDocument("doc1")
        doc["dict"].value = data
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d["dict"]["name"].string!, "Jason")
            XCTAssertEqual(d["dict"]["address"]["street"].string!, "1 Main street")
            XCTAssertEqual(d["dict"]["address"]["phones"]["mobile"].string!, "650-123-4567")
        })
    }
    
    
    func testDictionaryFragmentSetSwiftArray() throws {
        let doc = createDocument("doc1")
        doc["dict"].value = [:]
        doc["dict"]["array"].value = [0, 1, 2]
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d["dict"]["array"][0].int, 0)
            XCTAssertEqual(d["dict"]["array"][1].int, 1)
            XCTAssertEqual(d["dict"]["array"][2].int, 2)
            XCTAssertNil(d["dict"]["array"][3].value)
            XCTAssertFalse(d["dict"]["array"][3].exists)
            XCTAssertEqual(d["dict"]["array"][3].int, 0)
        })
    }
    
    
    func testNonDictionaryFragmentsetValue() throws {
        let doc = createDocument("doc1")
        doc.setValue("value1", forKey: "string1")
        doc.setValue("value2", forKey: "string2")
        
        try saveDocument(doc, eval: { (d) in
            let mDoc = d.toMutable()
            mDoc["string1"].value = 10
            XCTAssertEqual(mDoc["string1"].value as! Int, 10)
            XCTAssertEqual(mDoc["string2"].value as! String, "value2")
        })
    }
    
    
    func testArrayFragmentsetData() throws {
        let data: [String: Any] = ["name": "Jason",
                                   "address": [
                                    "street": "1 Main street",
                                    "phones": ["mobile": "650-123-4567"]]]
        
        let doc = createDocument("doc1")
        doc["array"].value = []
        
        let dict = MutableDictionaryObject(data: data)
        doc["array"].array!.addValue(dict)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertNotNil(d["array"][0])
            XCTAssert(d["array"][0].exists)
            XCTAssertNotNil(d["array"][1])
            XCTAssertFalse(d["array"][1].exists)
            
            XCTAssertEqual(d["array"][0]["name"].string!, "Jason")
            XCTAssertEqual(d["array"][0]["address"]["street"].string!, "1 Main street")
            XCTAssertEqual(d["array"][0]["address"]["phones"]["mobile"].string!, "650-123-4567")
        })
    }
    
    
    func testArrayFragmentSetSwiftDictionary() throws {
        let data: [String: Any] = ["name": "Jason",
                                   "address": [
                                    "street": "1 Main street",
                                    "phones": ["mobile": "650-123-4567"]]]
        
        let doc = createDocument("doc1")
        doc["array"].value = []
        doc["array"].array!.addValue(data)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertNotNil(d["array"][0])
            XCTAssert(d["array"][0].exists)
            XCTAssertNotNil(d["array"][1])
            XCTAssertFalse(d["array"][1].exists)
            
            XCTAssertEqual(d["array"][0]["name"].string!, "Jason")
            XCTAssertEqual(d["array"][0]["address"]["street"].string!, "1 Main street")
            XCTAssertEqual(d["array"][0]["address"]["phones"]["mobile"].string!, "650-123-4567")
        })
    }
    
    
    func testArrayFragmentSetArrayObject() throws {
        let doc = createDocument("doc1")
        doc["array"].value = []
        let array = MutableArrayObject()
        array.addValue("Jason")
        array.addValue(5.5)
        array.addValue(true)
        doc["array"].array!.addValue(array)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d["array"][0][0].string!, "Jason")
            XCTAssertEqual(d["array"][0][1].float, 5.5)
            XCTAssertEqual(d["array"][0][2].boolean, true)
        })
    }
    
    
    func testArrayFragmentSetArray() throws {
        let doc = createDocument("doc1")
        doc["array"].value = []
        doc["array"].array!.addValue(["Jason", 5.5, true])
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d["array"][0][0].string!, "Jason")
            XCTAssertEqual(d["array"][0][1].float, 5.5)
            XCTAssertEqual(d["array"][0][2].boolean, true)
        })
    }
    
    
    func testNonExistingArrayFragmentsetValue() throws {
        let doc = createDocument("doc1")
        doc["array"][0][0].value = 1
        doc["array"][0][1].value = false
        doc["array"][0][2].value = "hello"
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d["array"][0][0].value)
            XCTAssertNil(d["array"][0][1].value)
            XCTAssertNil(d["array"][0][2].value)
            XCTAssert(d.toDictionary() == [:] as [String: Any])
        })
    }
    
    
    func testOutOfRangeArrayFragmentsetValue() throws {
        let doc = createDocument("doc1")
        doc["array"].value = []
        doc["array"].array?.addValue(["Jason", 5.5, true])
        doc["array"][0][3].value = 1
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertNotNil(d["array"][0][3])
            XCTAssertFalse(d["array"][0][3].exists)
        })
    }
}
