//
//  ArrayTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/14/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift


class ArrayTest: CBLTestCase {
    func saveArray(_ array: ArrayObject, onDocument doc: Document, forKey key: String,
                   eval: (ArrayObject) -> Void) throws
    {
        eval(array)
        
        // Set and Save:
        doc.setValue(array, forKey: key)
        try saveDocument(doc)
        
        // Re-get the document and the array:
        let nuDoc = db.getDocument(doc.id)!
        let nuArray = nuDoc.array(forKey: key)!
        
        eval(nuArray)
    }
    
    
    func testEnumeratingArray() throws {
        let array = ArrayObject()
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
        array.remove(at: 1)
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
        
        try saveArray(array, onDocument: doc, forKey: "array") { (a) in
            result = []
            for item in a {
                result.append(item)
            }
            XCTAssert(result == content)
        }
    }
}

