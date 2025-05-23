//
//  DictionaryTest.swift
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

class DictionaryTest: CBLTestCase {
    
    let kTestDate = "2017-01-01T00:00:00.000Z"
    
    func testCreateDictionary() throws {
        let address = MutableDictionaryObject()
        XCTAssertEqual(address.count, 0)
        XCTAssert(address.toDictionary() == [:] as [String: Any])
        
        let doc = createDocument("doc1")
        doc.setValue(address, forKey: "address")
        XCTAssert(doc.dictionary(forKey: "address")! === address)
        
        try saveDocument(doc) { (d) in
            XCTAssert(doc.dictionary(forKey: "address")!.toDictionary() == [:] as [String: Any])
        }
    }
    
    func testCreateDictionaryWithSwiftDictionary() throws {
        let dict: [String: Any] = ["street": "1 Main street",
                                   "city": "Mountain View",
                                   "state": "CA"];
        let address = MutableDictionaryObject(data: dict)
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
        XCTAssert(address.toDictionary() == dict)
        
        let doc = createDocument("doc1")
        doc.setValue(address, forKey: "address")
        XCTAssert(doc.dictionary(forKey: "address")! === address)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssert(doc.dictionary(forKey: "address")!.toDictionary() == dict)
        })
    }
    
    func testGetValueFromNewEmptyDictionary() throws {
        let doc = createDocument("doc1")
        doc.setValue(MutableDictionaryObject(), forKey: "dict")
        
        try saveDocument(doc, eval: { (d) in
            let dict = d.dictionary(forKey: "dict")!
            XCTAssertEqual(dict.int(forKey: "key"), 0)
            XCTAssertEqual(dict.float(forKey: "key"), 0.0)
            XCTAssertEqual(dict.double(forKey: "key"), 0.0)
            XCTAssertEqual(dict.boolean(forKey: "key"), false)
            XCTAssertNil(dict.blob(forKey: "key"))
            XCTAssertNil(dict.date(forKey: "key"))
            XCTAssertNil(dict.string(forKey: "key"))
            XCTAssertNil(dict.value(forKey: "key"))
            XCTAssertNil(dict.dictionary(forKey: "key"))
            XCTAssertNil(dict.array(forKey: "key"))
        })
    }
    
    func testSettersDictionary() throws {
        let dict = MutableDictionaryObject()
        dict.setValue("value", forKey: "key")
        XCTAssertEqual("value", dict.value(forKey: "key") as! String);
        
        dict.setValue(2, forKey: "key")
        XCTAssertEqual(2, dict.value(forKey: "key") as! Int64);
        
        dict.setString("string", forKey: "key")
        XCTAssertEqual("string", dict.string(forKey: "key"));
        
        dict.setNumber(2, forKey: "key")
        XCTAssertEqual(2, dict.number(forKey: "key"));
        
        dict.setInt(2, forKey: "key")
        XCTAssertEqual(2, dict.int(forKey: "key"));
        
        dict.setInt64(Int64("2")!, forKey: "key")
        XCTAssertEqual(2, dict.int64(forKey: "key"));
        
        let double = Double.random(in: -1.0...1.0)
        dict.setDouble(double, forKey: "key")
        XCTAssertEqual(double, dict.double(forKey: "key"));
        
        let float = Float.random(in: -1.0...1.0)
        dict.setFloat(float , forKey: "key")
        XCTAssertEqual(float, dict.float(forKey: "key"));
        
        dict.setBoolean(true, forKey: "key")
        XCTAssertEqual(true, dict.boolean(forKey: "key"));
        
        dict.setDate(dateFromJson(kTestDate), forKey: "key")
        XCTAssertEqual(dateFromJson(kTestDate), dict.date(forKey: "key"));
        
        let data1 = "data1".data(using: String.Encoding.utf8)!
        let blob = Blob.init(contentType: "text/plain", data: data1)
        dict.setBlob(blob, forKey: "key")
        XCTAssertEqual(blob, dict.blob(forKey: "key"));
        
        let array = MutableArrayObject()
        array.addString("a1")
        array.addDictionary(MutableDictionaryObject(data: ["name": "n1"]))
        dict.setArray(array, forKey: "key")
        XCTAssertEqual(array, dict.array(forKey: "key"));
    }
    
    func testSetNestedDictionaries() throws {
        let doc = createDocument("doc1")
        
        let level1 = MutableDictionaryObject()
        level1.setValue("n1", forKey: "name")
        doc.setDictionary(level1, forKey: "level1")
        
        let level2 = MutableDictionaryObject()
        level2.setValue("n2", forKey: "name")
        level1.setDictionary(level2, forKey: "level2")
        
        let level3 = MutableDictionaryObject()
        level3.setValue("n3", forKey: "name")
        level2.setDictionary(level3, forKey: "level3")
        
        XCTAssert(doc.dictionary(forKey: "level1")! === level1)
        XCTAssert(level1.dictionary(forKey: "level2")! === level2)
        XCTAssert(level2.dictionary(forKey: "level3")! === level3)
        let dict: [String: Any] = ["level1": ["name": "n1",
                                              "level2": ["name": "n2",
                                                         "level3": ["name": "n3"]]]]
        try saveDocument(doc, eval: { (d) in
            XCTAssert(d.toDictionary() == dict)
        })
    }
    
    func testRemoveDictionary() throws {
        let doc = createDocument("doc1")
        let profile1 = MutableDictionaryObject()
        profile1.setValue("Scott Tiger", forKey: "name")
        doc.setValue(profile1, forKey: "profile")
        XCTAssert(doc.dictionary(forKey: "profile") === profile1)
        
        // Remove profile
        doc.removeValue(forKey: "profile")
        XCTAssertNil(doc.value(forKey: "profile"))
        XCTAssertFalse(doc.contains("profile"))
        
        // Profile1 should be now detachd:
        profile1.setValue(20, forKey: "age")
        XCTAssertEqual(profile1.string(forKey: "name")!, "Scott Tiger")
        XCTAssertEqual(profile1.int(forKey: "age"), 20)
        
        // Check whether the profile value has no change:
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.value(forKey: "profile"))
            XCTAssertFalse(d.contains("profile"))
        })
    }
    
    func testEnumeratingKeys() throws {
        let dict = MutableDictionaryObject()
        for i in 0...19 {
            dict.setValue(i, forKey: "key\(i)")
        }
        var content = dict.toDictionary()
        
        var result: [String: Any] = [:]
        var count = 0
        for key in dict {
            result[key] = dict.int(forKey: key)
            count = count + 1
        }
        XCTAssert(result == content)
        XCTAssertEqual(count, content.count)
        
        // Update:
        dict.removeValue(forKey: "key2")
        dict.setValue(20, forKey: "key20")
        dict.setValue(22, forKey: "key21")
        content = dict.toDictionary()
        
        result = [:]
        count = 0
        for key in dict {
            result[key] = dict.int(forKey: key)
            count = count + 1
        }
        XCTAssert(result == content)
        XCTAssertEqual(count, content.count)
        
        let doc = createDocument("doc1")
        doc.setValue(dict, forKey: "dict")
        
        try saveDocument(doc) { (d) in
            result = [:]
            count = 0
            let savedDict = d.dictionary(forKey: "dict")!
            for key in savedDict {
                result[key] = savedDict.value(forKey: key)
                count = count + 1
            }
            XCTAssert(result == content)
            XCTAssertEqual(count, content.count)
        }
    }
    
    func testToMutable() throws {
        let mDict1 = MutableDictionaryObject()
        mDict1.setValue("Scott", forKey: "name")
        
        let mDict2 = mDict1.toMutable()
        XCTAssert(mDict1 !== mDict2)
        XCTAssert(mDict1.toDictionary() == mDict2.toDictionary())
        mDict2.setValue("Daniel", forKey: "name")
        XCTAssertEqual(mDict2.string(forKey: "name"), "Daniel")
        
        let mDoc = createDocument("doc1")
        mDoc.setValue(mDict2, forKey: "dict")
        try saveDocument(mDoc)
        
        let doc = try self.defaultCollection!.document(id: "doc1")!
        let dict = doc.dictionary(forKey: "dict")!
        XCTAssertEqual(dict.string(forKey: "name"), "Daniel")
        
        let mDict3 = dict.toMutable()
        XCTAssertEqual(mDict3.string(forKey: "name"), "Daniel")
        mDict3.setValue("Thomas", forKey: "name")
        XCTAssertEqual(mDict3.string(forKey: "name"), "Thomas")
    }
    
    // MARK: toJSON
    
    func testDictionaryToJSON() throws {
        let json = try getRickAndMortyJSON()
        var mDict = try MutableDictionaryObject(json: json)
        var mDoc = MutableDocument(id: "doc")
        mDoc.setDictionary(mDict, forKey: "dict")
        try self.defaultCollection!.save(document: mDoc)
        
        var doc = try self.defaultCollection!.document(id: "doc")
        var dict = doc?.dictionary(forKey: "dict")
        let jsonObj = dict!.toJSON().toJSONObj() as! [String: Any]
        XCTAssertEqual(jsonObj["name"] as! String, "Rick Sanchez")
        XCTAssertEqual(jsonObj["id"] as! Int, 1)
        XCTAssertEqual(jsonObj["isAlive"] as! Bool, true)
        XCTAssertEqual(jsonObj["longitude"] as! Double, -21.152958)
        XCTAssertEqual((jsonObj["aka"] as! Array<Any>)[2] as! String, "Albert Ein-douche")
        XCTAssertEqual((jsonObj["family"] as! Array<[String: Any]>)[0]["name"] as! String, "Morty Smith")
        XCTAssertEqual((jsonObj["family"] as! Array<[String: Any]>)[3]["name"] as! String, "Summer Smith")
        XCTAssertEqual((dict!.toJSON().toJSONObj() as! [String: Any]).count, 12)
        
        mDoc = doc!.toMutable()
        mDict = dict!.toMutable()
        mDict.setValue("newValueAppended", forKey: "newKeyAppended")
        expectException(exception: .internalInconsistencyException) {
            let _ = mDict.toJSON()
        }
        mDoc.setValue(mDict, forKey: "dict")
        try self.defaultCollection!.save(document: mDoc)
        
        doc = try self.defaultCollection!.document(id: "doc")
        dict = doc!.dictionary(forKey: "dict")
        XCTAssertEqual((dict!.toJSON().toJSONObj() as! [String: Any])["newKeyAppended"] as! String, "newValueAppended")
        XCTAssertEqual((dict!.toJSON().toJSONObj() as! [String: Any]).count, 13)
    }
    
    func testUnsavedMutableDictionaryToJSON() throws {
        let mDict = try MutableDictionaryObject(json: "{\"unsaved\":\"dict\"}")
        expectException(exception: .internalInconsistencyException) {
            let _ = mDict.toJSON()
        }
    }
}
