//
//  DictionaryTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


import XCTest
import CouchbaseLiteSwift


class DictionaryTest: CBLTestCase {
    func testCreateDictionary() throws {
        let address = DictionaryObject()
        XCTAssertEqual(address.count, 0)
        XCTAssert(address.toDictionary() == [:] as [String: Any])
        
        let doc = createDocument("doc1")
        doc.set(address, forKey: "address")
        XCTAssert(doc.getDictionary("address")! === address)
        
        try saveDocument(doc) { (d) in
            XCTAssert(doc.getDictionary("address")!.toDictionary() == [:] as [String: Any])
        }
    }
    
    
    func testCreateDictionaryWithSwiftDictionary() throws {
        let dict: [String: Any] = ["street": "1 Main street",
                                   "city": "Mountain View",
                                   "state": "CA"];
        let address = DictionaryObject(dictionary: dict)
        XCTAssertEqual(address.getString("street"), "1 Main street")
        XCTAssertEqual(address.getString("city"), "Mountain View")
        XCTAssertEqual(address.getString("state"), "CA")
        XCTAssert(address.toDictionary() == dict)
        
        let doc = createDocument("doc1")
        doc.set(address, forKey: "address")
        XCTAssert(doc.getDictionary("address")! === address)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssert(doc.getDictionary("address")!.toDictionary() == dict)
        })
    }
    
    
    func testGetValueFromNewEmptyDictionary() throws {
        let doc = createDocument("doc1")
        doc.set(DictionaryObject(), forKey: "dict")
        
        try saveDocument(doc, eval: { (d) in
            let dict = d.getDictionary("dict")!
            XCTAssertEqual(dict.getInt("key"), 0)
            XCTAssertEqual(dict.getFloat("key"), 0.0)
            XCTAssertEqual(dict.getDouble("key"), 0.0)
            XCTAssertEqual(dict.getBoolean("key"), false)
            XCTAssertNil(dict.getBlob("key"))
            XCTAssertNil(dict.getDate("key"))
            XCTAssertNil(dict.getString("key"))
            XCTAssertNil(dict.getValue("key"))
            XCTAssertNil(dict.getDictionary("key"))
            XCTAssertNil(dict.getArray("key"))
        })
    }
    
    
    func testSetNestedDictionaries() throws {
        let doc = createDocument("doc1")
        
        let level1 = DictionaryObject()
        level1.set("n1", forKey: "name")
        doc.set(level1, forKey: "level1")
        
        let level2 = DictionaryObject()
        level2.set("n2", forKey: "name")
        level1.set(level2, forKey: "level2")
        
        let level3 = DictionaryObject()
        level3.set("n3", forKey: "name")
        level2.set(level3, forKey: "level3")
        
        XCTAssert(doc.getDictionary("level1")! === level1)
        XCTAssert(level1.getDictionary("level2")! === level2)
        XCTAssert(level2.getDictionary("level3")! === level3)
        let dict: [String: Any] = ["level1": ["name": "n1",
                                              "level2": ["name": "n2",
                                                         "level3": ["name": "n3"]]]]
        try saveDocument(doc, eval: { (d) in
            XCTAssert(doc.toDictionary() == dict)
        })
    }
}
