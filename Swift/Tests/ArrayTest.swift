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
    func saveArray(_ array: MutableArrayObject, onDocument doc: MutableDocument,
                   forKey key: String, eval: (ArrayObject) -> Void) throws
    {
        eval(array)
        // Set and Save:
        doc.setValue(array, forKey: key)
        let savedDoc = try saveDocument(doc)
        let savedArray = savedDoc.array(forKey: key)!
        eval(savedArray)
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
        
        try saveArray(array, onDocument: doc, forKey: "array") { (a) in
            result = []
            for item in a {
                result.append(item)
            }
            XCTAssert(result == content)
        }
    }
}

