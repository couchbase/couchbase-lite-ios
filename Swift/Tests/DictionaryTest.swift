//
//  DictionaryTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//


import XCTest
import CouchbaseLiteSwift


class DictionaryTest: CBLTestCase {
    
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
        let address = MutableDictionaryObject(dictionary: dict)
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
    
    
    func testSetNestedDictionaries() throws {
        let doc = createDocument("doc1")
        
        let level1 = MutableDictionaryObject()
        level1.setValue("n1", forKey: "name")
        doc.setValue(level1, forKey: "level1")
        
        let level2 = MutableDictionaryObject()
        level2.setValue("n2", forKey: "name")
        level1.setValue(level2, forKey: "level2")
        
        let level3 = MutableDictionaryObject()
        level3.setValue("n3", forKey: "name")
        level2.setValue(level3, forKey: "level3")
        
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
        doc.remove(forKey: "profile")
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
        dict.remove(forKey: "key2")
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
    
}
