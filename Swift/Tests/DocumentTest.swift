//
//  DocumentTest.swift
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

class DocumentTest: CBLTestCase {
    
    let kTestDate = "2017-01-01T00:00:00.000Z"
    
    let kTestBlob = "i'm blob"
    
    func populateData(_ doc: MutableDocument) {
        doc.setValue(true, forKey: "true")
        doc.setValue(false, forKey: "false")
        doc.setValue("string", forKey: "string")
        doc.setValue(0, forKey: "zero")
        doc.setValue(1, forKey: "one")
        doc.setValue(-1, forKey: "minus_one")
        doc.setValue(1.1, forKey: "one_dot_one")
        doc.setValue(dateFromJson(kTestDate), forKey: "date")
        doc.setValue(NSNull(), forKey: "null")
        
        // Dictionary:
        let dict = MutableDictionaryObject()
        dict.setValue("1 Main street", forKey: "street")
        dict.setValue("Mountain View", forKey: "city")
        dict.setValue("CA", forKey: "state")
        doc.setValue(dict, forKey: "dict")
        
        // Array:
        let array = MutableArrayObject()
        array.addValue("650-123-0001")
        array.addValue("650-123-0002")
        doc.setValue(array, forKey: "array")
        
        // Blob
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        doc.setValue(blob, forKey: "blob")
    }
    
    func testCreateDoc() throws {
        let doc1a = MutableDocument()
        XCTAssertNotNil(doc1a)
        XCTAssertTrue(doc1a.id.count > 0)
        XCTAssertEqual(doc1a.toDictionary().count, 0);
        try saveDocument(doc1a)
    }
    
    func testCreateDocWithID() throws {
        let doc1a = MutableDocument(id: "doc1")
        XCTAssertNotNil(doc1a)
        XCTAssertEqual(doc1a.id, "doc1")
        XCTAssertEqual(doc1a.toDictionary().count, 0);
        try saveDocument(doc1a)
    }
    
    func testCreateDocwithEmptyStringID() throws {
        let doc1a = MutableDocument(id: "")
        XCTAssertNotNil(doc1a)
        
        var error: NSError? = nil
        do {
            try defaultCollection!.save(document: doc1a)
        } catch let err as NSError {
            error = err
        }
        
        XCTAssertNotNil(error)
        XCTAssertEqual(error!.code, CBLError.badDocID)
        XCTAssertEqual(error!.domain, CBLError.domain)
        
        // get document with empty doc-id string; skip test exception breakpoint
        ignoreException {
            XCTAssertNil(try? self.defaultCollection!.document(id: ""))
        }
    }
    
    func testCreateDocWithNilID() throws {
        let doc1a = MutableDocument(id: nil)
        XCTAssertNotNil(doc1a)
        XCTAssertTrue(doc1a.id.count > 0)
        XCTAssertEqual(doc1a.toDictionary().count, 0);
        try saveDocument(doc1a)
    }
    
    func testCreateDocWithDict() throws {
        let dict: [String: Any] = ["name": "Scott Tiger",
                                   "age": 30,
                                   "address": ["street": "1 Main street.",
                                               "city": "Mountain View",
                                               "state": "CA"],
                                   "phones": ["650-123-0001", "650-123-0002"]]
        
        let doc1a = MutableDocument(id: "doc1", data: dict)
        XCTAssertNotNil(doc1a)
        XCTAssertTrue(doc1a.id.count > 0)
        XCTAssertTrue(doc1a.toDictionary() == dict)
        try saveDocument(doc1a)
    }
    
    func testSetDictionaryContent() throws {
        let dict: [String: Any] = ["name": "Scott Tiger",
                                   "age": 30,
                                   "address": ["street": "1 Main street.",
                                               "city": "Mountain View",
                                               "state": "CA"],
                                   "phones": ["650-123-0001", "650-123-0002"]]
        
        let doc = createDocument(data: dict)
        XCTAssertTrue(doc.toDictionary() == dict)
        try saveDocument(doc)
        
        let nuDict: [String: Any] = ["name": "Daniel Tiger",
                                     "age": 32,
                                     "address": ["street": "2 Main street.",
                                                 "city": "Palo Alto",
                                                 "state": "CA"],
                                     "phones": ["650-234-0001", "650-234-0002"]]
        doc.setData(nuDict)
        XCTAssertTrue(doc.toDictionary() == nuDict)
        try saveDocument(doc)
    }
    
    func testGetValueFromNewEmptyDoc() throws {
        let doc = createDocument("doc1")
        try saveDocument(doc) { (d) in
            XCTAssertEqual(d.int(forKey: "key"), 0);
            XCTAssertEqual(d.float(forKey: "key"), 0.0);
            XCTAssertEqual(d.double(forKey: "key"), 0.0);
            XCTAssertEqual(d.boolean(forKey: "key"), false);
            XCTAssertNil(d.blob(forKey: "key"));
            XCTAssertNil(d.date(forKey: "key"));
            XCTAssertNil(d.value(forKey: "key"));
            XCTAssertNil(d.string(forKey: "key"));
            XCTAssertNil(d.dictionary(forKey: "key"));
            XCTAssertNil(d.array(forKey: "key"));
            XCTAssertEqual(d.toDictionary().count, 0);
        }
    }
    
    func testSaveThenGetFromAnotherDB() throws {
        let doc1a = createDocument("doc1")
        doc1a.setValue("Scott Tiger", forKey: "name")
        
        try saveDocument(doc1a)
        
        let anotherDb = try openDB(name: db.name)
        
        let doc1b = try anotherDb.defaultCollection().document(id: "doc1")
        XCTAssertNotNil(doc1b)
        XCTAssertTrue(doc1b !== doc1a)
        XCTAssertEqual(doc1b!.id, doc1a.id)
        XCTAssertTrue(doc1b!.toDictionary() == doc1a.toDictionary())
        
        try anotherDb.close()
    }
    
    func testNoCacheNoLive() throws {
        let doc1a = createDocument("doc1")
        doc1a.setValue("Scott Tiger", forKey: "name")
        try saveDocument(doc1a)
        
        let doc1b = try defaultCollection!.document(id: "doc1")!
        let doc1c = try defaultCollection!.document(id: "doc1")!
        
        let anotherDb = try openDB(name: db.name)
        let doc1d = try anotherDb.defaultCollection().document(id: "doc1")!
        
        XCTAssertTrue(doc1a !== doc1b)
        XCTAssertTrue(doc1a !== doc1c)
        XCTAssertTrue(doc1a !== doc1d)
        XCTAssertTrue(doc1a !== doc1c)
        XCTAssertTrue(doc1a !== doc1d)
        XCTAssertTrue(doc1a !== doc1d)
        
        XCTAssertTrue(doc1a.toDictionary() == doc1b.toDictionary())
        XCTAssertTrue(doc1a.toDictionary() == doc1c.toDictionary())
        XCTAssertTrue(doc1a.toDictionary() == doc1d.toDictionary())
        
        // Update:
        
        let updatedDoc1b = doc1b.toMutable()
        updatedDoc1b.setValue("Daniel Tiger", forKey: "name")
        try saveDocument(updatedDoc1b)
        
        XCTAssertFalse(updatedDoc1b.toDictionary() == doc1a.toDictionary())
        XCTAssertFalse(updatedDoc1b.toDictionary() == doc1c.toDictionary())
        XCTAssertFalse(updatedDoc1b.toDictionary() == doc1d.toDictionary())
        
        try anotherDb.close()
    }
    
    func testSetString() throws {
        var doc = createDocument("doc1")
        doc.setString("string1", forKey: "string1")
        doc.setString("string2", forKey: "string2")
        try saveDocument(doc) { (d) in
            XCTAssertEqual(d.string(forKey: "string1"), "string1")
            XCTAssertEqual(d.string(forKey: "string2"), "string2")
        }
        
        // Update:
        doc.setString("string1a", forKey: "string1")
        doc.setString("string2a", forKey: "string2")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.string(forKey: "string1"), "string1a")
            XCTAssertEqual(d.string(forKey: "string2"), "string2a")
        })
        
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        doc.setString("string1b", forKey: "string1")
        doc.setString("string2b", forKey: "string2")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.string(forKey: "string1"), "string1b")
            XCTAssertEqual(d.string(forKey: "string2"), "string2b")
        })
    }
    
    func testGetString() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.string(forKey: "null"))
            XCTAssertNil(d.string(forKey: "true"))
            XCTAssertNil(d.string(forKey: "false"))
            XCTAssertEqual(d.string(forKey: "string"), "string");
            XCTAssertNil(d.string(forKey: "zero"))
            XCTAssertNil(d.string(forKey: "one"))
            XCTAssertNil(d.string(forKey: "minus_one"))
            XCTAssertNil(d.string(forKey: "one_dot_one"))
            XCTAssertEqual(d.string(forKey: "date"), kTestDate);
            XCTAssertNil(d.string(forKey: "dict"))
            XCTAssertNil(d.string(forKey: "array"))
            XCTAssertNil(d.string(forKey: "blob"))
            XCTAssertNil(d.string(forKey: "non_existing_key"))
        })
    }
    
    func testSetNumber() throws {
        var doc = createDocument("doc1")
        doc.setNumber(1, forKey: "number1")
        doc.setNumber(0, forKey: "number2")
        doc.setNumber(-1, forKey: "number3")
        doc.setNumber(1.1, forKey: "number4")
        doc.setNumber(12345678, forKey: "number5")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(doc.int(forKey: "number1"), 1)
            XCTAssertEqual(doc.int(forKey: "number2"), 0)
            XCTAssertEqual(doc.int(forKey: "number3"), -1)
            XCTAssertEqual(doc.float(forKey: "number4"), 1.1)
            XCTAssertEqual(doc.double(forKey: "number4"), 1.1)
            XCTAssertEqual(doc.int(forKey: "number5"), 12345678)
        })
        
        // Update:
        doc.setNumber(0, forKey: "number1")
        doc.setNumber(1, forKey: "number2")
        doc.setNumber(1.1, forKey: "number3")
        doc.setNumber(-1, forKey: "number4")
        doc.setNumber(-12345678, forKey: "number5")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(doc.int(forKey: "number1"), 0)
            XCTAssertEqual(doc.int(forKey: "number2"), 1)
            XCTAssertEqual(doc.float(forKey: "number3"), 1.1)
            XCTAssertEqual(doc.double(forKey: "number3"), 1.1)
            XCTAssertEqual(doc.int(forKey: "number4"), -1)
            XCTAssertEqual(doc.int(forKey: "number5"), -12345678)
        })
        
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        doc.setNumber(1, forKey: "number1")
        doc.setNumber(0, forKey: "number2")
        doc.setNumber(2.1, forKey: "number3")
        doc.setNumber(-2, forKey: "number4")
        doc.setNumber(-123456789, forKey: "number5")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(doc.int(forKey: "number1"), 1)
            XCTAssertEqual(doc.int(forKey: "number2"), 0)
            XCTAssertEqual(doc.float(forKey: "number3"), 2.1)
            XCTAssertEqual(doc.double(forKey: "number3"), 2.1)
            XCTAssertEqual(doc.int(forKey: "number4"), -2)
            XCTAssertEqual(doc.int(forKey: "number5"), -123456789)
        })
    }
    
    func testGetInteger() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.int(forKey: "null"), 0)
            XCTAssertEqual(d.int(forKey: "true"), 1)
            XCTAssertEqual(d.int(forKey: "false"), 0)
            XCTAssertEqual(d.int(forKey: "string"), 0);
            XCTAssertEqual(d.int(forKey: "zero"),0)
            XCTAssertEqual(d.int(forKey: "one"), 1)
            XCTAssertEqual(d.int(forKey: "minus_one"), -1)
            XCTAssertEqual(d.int(forKey: "one_dot_one"), 1)
            XCTAssertEqual(d.int(forKey: "date"), 0)
            XCTAssertEqual(d.int(forKey: "dict"), 0)
            XCTAssertEqual(d.int(forKey: "array"), 0)
            XCTAssertEqual(d.int(forKey: "blob"), 0)
            XCTAssertEqual(d.int(forKey: "non_existing_key"), 0)
        })
    }

    func testGetFloat() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.float(forKey: "null"), 0.0)
            XCTAssertEqual(d.float(forKey: "true"), 1.0)
            XCTAssertEqual(d.float(forKey: "false"), 0.0)
            XCTAssertEqual(d.float(forKey: "string"), 0.0);
            XCTAssertEqual(d.float(forKey: "zero"),0.0)
            XCTAssertEqual(d.float(forKey: "one"), 1.0)
            XCTAssertEqual(d.float(forKey: "minus_one"), -1.0)
            XCTAssertEqual(d.float(forKey: "one_dot_one"), 1.1)
            XCTAssertEqual(d.float(forKey: "date"), 0.0)
            XCTAssertEqual(d.float(forKey: "dict"), 0.0)
            XCTAssertEqual(d.float(forKey: "array"), 0.0)
            XCTAssertEqual(d.float(forKey: "blob"), 0.0)
            XCTAssertEqual(d.float(forKey: "non_existing_key"), 0.0)
        })
    }
    
    func testGetDouble() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.double(forKey: "null"), 0.0)
            XCTAssertEqual(d.double(forKey: "true"), 1.0)
            XCTAssertEqual(d.double(forKey: "false"), 0.0)
            XCTAssertEqual(d.double(forKey: "string"), 0.0);
            XCTAssertEqual(d.double(forKey: "zero"),0.0)
            XCTAssertEqual(d.double(forKey: "one"), 1.0)
            XCTAssertEqual(d.double(forKey: "minus_one"), -1.0)
            XCTAssertEqual(d.double(forKey: "one_dot_one"), 1.1)
            XCTAssertEqual(d.double(forKey: "date"), 0.0)
            XCTAssertEqual(d.double(forKey: "dict"), 0.0)
            XCTAssertEqual(d.double(forKey: "array"), 0.0)
            XCTAssertEqual(d.double(forKey: "blob"), 0.0)
            XCTAssertEqual(d.double(forKey: "non_existing_key"), 0.0)
        })
    }
    
    func testSetGetMinMaxNumbers() throws {
        let doc = createDocument("doc1")
        doc.setInt(Int.min, forKey: "min_int")
        doc.setInt(Int.max, forKey: "max_int")
        doc.setInt64(Int64.min, forKey: "min_int64")
        doc.setInt64(Int64.max, forKey: "max_int64")
        doc.setFloat(Float.leastNormalMagnitude, forKey: "min_float")
        doc.setFloat(Float.greatestFiniteMagnitude, forKey: "max_float")
        doc.setDouble(Double.leastNormalMagnitude, forKey: "min_double")
        doc.setDouble(Double.greatestFiniteMagnitude, forKey: "max_double")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.int(forKey: "min_int"), Int.min);
            XCTAssertEqual(d.int(forKey: "max_int"), Int.max);
            XCTAssertEqual(d.value(forKey: "min_int") as! Int, Int.min);
            XCTAssertEqual(d.value(forKey: "max_int") as! Int, Int.max);
            
            XCTAssertEqual(d.int64(forKey: "min_int"), Int64.min);
            XCTAssertEqual(d.int64(forKey: "max_int"), Int64.max);
            XCTAssertEqual(d.value(forKey: "min_int") as! Int64, Int64.min);
            XCTAssertEqual(d.value(forKey: "max_int") as! Int64, Int64.max);
            
            XCTAssertEqual(d.float(forKey: "min_float"), Float.leastNormalMagnitude);
            XCTAssertEqual(d.float(forKey: "max_float"), Float.greatestFiniteMagnitude);
            XCTAssertEqual(d.value(forKey: "min_float") as! Float, Float.leastNormalMagnitude);
            XCTAssertEqual(d.value(forKey: "max_float") as! Float, Float.greatestFiniteMagnitude);
            
            XCTAssertEqual(d.double(forKey: "min_double"), Double.leastNormalMagnitude);
            XCTAssertEqual(d.double(forKey: "max_double"), Double.greatestFiniteMagnitude);
            XCTAssertEqual(d.value(forKey: "min_double") as! Double, Double.leastNormalMagnitude);
            XCTAssertEqual(d.value(forKey: "max_double") as! Double, Double.greatestFiniteMagnitude);
        })
    }
    
    func testSetGetFloatNumbers() throws {
        let doc = createDocument("doc1")
        doc.setFloat(1.00, forKey: "number1")
        doc.setFloat(1.49, forKey: "number2")
        doc.setFloat(1.50, forKey: "number3")
        doc.setFloat(1.51, forKey: "number4")
        doc.setFloat(1.99, forKey: "number5")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.int(forKey: "number1"), 1);
            XCTAssertEqual(d.float(forKey: "number1"), 1.00);
            
            XCTAssertEqual(d.int(forKey: "number2"), 1);
            XCTAssertEqual(d.float(forKey: "number2"), 1.49);
            
            XCTAssertEqual(d.int(forKey: "number3"), 1);
            XCTAssertEqual(d.float(forKey: "number3"), 1.50);
            
            XCTAssertEqual(d.int(forKey: "number4"), 1);
            XCTAssertEqual(d.float(forKey: "number4"), 1.51);
            
            XCTAssertEqual(d.int(forKey: "number5"), 1);
            XCTAssertEqual(d.float(forKey: "number5"), 1.99);
        })
    }
    
    func testSetBoolean() throws {
        var doc = createDocument("doc1")
        doc.setBoolean(true, forKey: "boolean1")
        doc.setBoolean(false, forKey: "boolean2")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.boolean(forKey: "boolean1"), true);
            XCTAssertEqual(d.boolean(forKey: "boolean2"), false);
        })
        
        // Update:
        doc.setBoolean(false, forKey: "boolean1")
        doc.setBoolean(true, forKey: "boolean2")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.boolean(forKey: "boolean1"), false);
            XCTAssertEqual(d.boolean(forKey: "boolean2"), true);
        })
        
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        doc.setBoolean(true, forKey: "boolean1")
        doc.setBoolean(false, forKey: "boolean2")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.boolean(forKey: "boolean1"), true);
            XCTAssertEqual(d.boolean(forKey: "boolean2"), false);
        })
    }
    
    func testGetBoolean() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.boolean(forKey: "null"), false)
            XCTAssertEqual(d.boolean(forKey: "true"), true)
            XCTAssertEqual(d.boolean(forKey: "false"),false)
            XCTAssertEqual(d.boolean(forKey: "string"), true);
            XCTAssertEqual(d.boolean(forKey: "zero"), false)
            XCTAssertEqual(d.boolean(forKey: "one"), true)
            XCTAssertEqual(d.boolean(forKey: "minus_one"), true)
            XCTAssertEqual(d.boolean(forKey: "one_dot_one"), true)
            XCTAssertEqual(d.boolean(forKey: "date"), true)
            XCTAssertEqual(d.boolean(forKey: "dict"), true)
            XCTAssertEqual(d.boolean(forKey: "array"), true)
            XCTAssertEqual(d.boolean(forKey: "blob"), true)
            XCTAssertEqual(d.boolean(forKey: "non_existing_key"), false)
        })
    }
    
    func testSetDate() throws {
        var doc = createDocument("doc1")
        let date = Date()
        let dateStr = jsonFromDate(date)
        XCTAssertTrue(dateStr.count > 0)
        doc.setDate(date, forKey: "date")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.value(forKey: "date") as! String, dateStr);
            XCTAssertEqual(d.string(forKey: "date"), dateStr);
            XCTAssertEqual(jsonFromDate(d.date(forKey: "date")!), dateStr);
        })
        
        // Update:
        var nuDate = Date(timeInterval: 60.0, since: date)
        var nuDateStr = jsonFromDate(nuDate)
        doc.setDate(nuDate, forKey: "date")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.value(forKey: "date") as! String, nuDateStr);
            XCTAssertEqual(d.string(forKey: "date"), nuDateStr);
            XCTAssertEqual(jsonFromDate(d.date(forKey: "date")!), nuDateStr);
        })
        
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        nuDate = Date(timeInterval: 120.0, since: date)
        nuDateStr = jsonFromDate(nuDate)
        doc.setValue(nuDate, forKey: "date")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.value(forKey: "date") as! String, nuDateStr);
            XCTAssertEqual(d.string(forKey: "date"), nuDateStr);
            XCTAssertEqual(jsonFromDate(d.date(forKey: "date")!), nuDateStr);
        })
    }
    
    func testGetDate() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.date(forKey: "null"))
            XCTAssertNil(d.date(forKey: "true"))
            XCTAssertNil(d.date(forKey: "false"))
            XCTAssertNil(d.date(forKey: "string"));
            XCTAssertNil(d.date(forKey: "zero"))
            XCTAssertNil(d.date(forKey: "one"))
            XCTAssertNil(d.date(forKey: "minus_one"))
            XCTAssertNil(d.date(forKey: "one_dot_one"))
            XCTAssertEqual(jsonFromDate(d.date(forKey: "date")!), kTestDate);
            XCTAssertNil(d.date(forKey: "dict"))
            XCTAssertNil(d.date(forKey: "array"))
            XCTAssertNil(d.date(forKey: "blob"))
            XCTAssertNil(d.date(forKey: "non_existing_key"))
        })
    }
    
    func testSetBlob() throws {
        var doc = createDocument("doc1")
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        doc.setBlob(blob, forKey: "blob")
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.blob(forKey: "blob")!.properties == blob.properties)
            XCTAssertEqual(d.blob(forKey: "blob")!.content, content)
        })
        
        // Update:
        var nuContent = "1234567890".data(using: .utf8)!
        var nuBlob = Blob(contentType: "text/plain", data: nuContent)
        doc.setBlob(nuBlob, forKey: "blob")
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.blob(forKey: "blob")!.properties == nuBlob.properties)
            XCTAssertEqual(d.blob(forKey: "blob")!.content, nuContent)
        })
        
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        nuContent = "abcdefg".data(using: .utf8)!
        nuBlob = Blob(contentType: "text/plain", data: nuContent)
        doc.setBlob(nuBlob, forKey: "blob")
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.blob(forKey: "blob")!.properties == nuBlob.properties)
            XCTAssertEqual(d.blob(forKey: "blob")!.content, nuContent)
        })
    }
    
    func testGetBlob() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.blob(forKey: "null"))
            XCTAssertNil(d.blob(forKey: "true"))
            XCTAssertNil(d.blob(forKey: "false"))
            XCTAssertNil(d.blob(forKey: "string"));
            XCTAssertNil(d.blob(forKey: "zero"))
            XCTAssertNil(d.blob(forKey: "one"))
            XCTAssertNil(d.blob(forKey: "minus_one"))
            XCTAssertNil(d.blob(forKey: "one_dot_one"))
            XCTAssertNil(d.blob(forKey: "date"))
            XCTAssertNil(d.blob(forKey: "dict"))
            XCTAssertNil(d.blob(forKey: "array"))
            XCTAssertEqual(d.blob(forKey: "blob")!.content, kTestBlob.data(using: .utf8))
            XCTAssertNil(d.blob(forKey: "non_existing_key"))
        })
    }
    
    func testSetDictionary() throws {
        var doc = createDocument("doc1")
        var dict = MutableDictionaryObject()
        dict.setValue("1 Main street", forKey: "street")
        doc.setDictionary(dict, forKey: "dict")
        XCTAssertTrue(doc.value(forKey: "dict") as! DictionaryObject === dict)
        try saveDocument(doc, eval: { (d) in
            let savedDict = doc.value(forKey: "dict") as! DictionaryObject
            XCTAssertTrue(savedDict.toDictionary() == dict.toDictionary())
        })
        
        // Update:
        dict = doc.dictionary(forKey: "dict")!
        dict.setValue("Mountain View", forKey: "city")
        try saveDocument(doc, eval: { (d) in
            let savedDict = doc.value(forKey: "dict") as! DictionaryObject
            XCTAssertTrue(savedDict.toDictionary() == dict.toDictionary())
        })
        
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        dict = doc.dictionary(forKey: "dict")!
        dict.setValue("San Francisco", forKey: "city")
        try saveDocument(doc, eval: { (d) in
            let savedDict = doc.value(forKey: "dict") as! DictionaryObject
            XCTAssertTrue(savedDict.toDictionary() == dict.toDictionary())
        })
    }
    
    func testSetImmutableDictionary() throws {
        let dict1 = MutableDictionaryObject()
        dict1.setValue("n1", forKey: "name")
        
        let doc1a = createDocument("doc1")
        doc1a.setDictionary(dict1, forKey: "dict1")
        try saveDocument(doc1a)
        
        let doc1 = try defaultCollection!.document(id: doc1a.id)!
        let doc1b = doc1.toMutable()
        doc1b.setDictionary(doc1.dictionary(forKey: "dict1"), forKey: "dict1b")
        
        let dict2 = MutableDictionaryObject()
        dict2.setValue("n2", forKey: "name")
        doc1b.setDictionary(dict2, forKey: "dict2")
        
        let dict: [String: Any] = ["dict1": ["name": "n1"],
                                   "dict1b": ["name": "n1"],
                                   "dict2": ["name": "n2"]]
        try saveDocument(doc1b, eval: { (d) in
            XCTAssert(d.toDictionary() == dict)
        })
    }
    
    func testGetDictionary() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.dictionary(forKey: "null"))
            XCTAssertNil(d.dictionary(forKey: "true"))
            XCTAssertNil(d.dictionary(forKey: "false"))
            XCTAssertNil(d.dictionary(forKey: "string"));
            XCTAssertNil(d.dictionary(forKey: "zero"))
            XCTAssertNil(d.dictionary(forKey: "one"))
            XCTAssertNil(d.dictionary(forKey: "minus_one"))
            XCTAssertNil(d.dictionary(forKey: "one_dot_one"))
            XCTAssertNil(d.dictionary(forKey: "date"))
            let dict: [String: Any] = ["street": "1 Main street", "city": "Mountain View", "state": "CA"]
            XCTAssertTrue(doc.dictionary(forKey: "dict")!.toDictionary() == dict)
            XCTAssertNil(d.dictionary(forKey: "array"))
            XCTAssertNil(d.dictionary(forKey: "blob"))
            XCTAssertNil(d.dictionary(forKey: "non_existing_key"))
        })
    }
    
    func testSetArray() throws {
        var doc = createDocument("doc1")
        var array = MutableArrayObject()
        array.addValue("item1")
        array.addValue("item2")
        array.addValue("item3")
        doc.setArray(array, forKey: "array")
        XCTAssertTrue(doc.value(forKey: "array") as! ArrayObject === array)
        XCTAssertTrue(doc.array(forKey: "array")! === array)
        try saveDocument(doc, eval: { (d) in
            let savedArray = doc.value(forKey: "array") as! ArrayObject
            XCTAssertTrue(savedArray.toArray() == array.toArray())
        })
        
        // Update:
        array = doc.array(forKey: "array")!
        array.addValue("item4")
        array.addValue("item5")
        try saveDocument(doc, eval: { (d) in
            let savedArray = doc.value(forKey: "array") as! ArrayObject
            XCTAssertTrue(savedArray.toArray() == array.toArray())
        })
        
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        array = doc.array(forKey: "array")!
        array.addValue("item4")
        array.addValue("item5")
        try saveDocument(doc, eval: { (d) in
            let savedArray = doc.value(forKey: "array") as! ArrayObject
            XCTAssertTrue(savedArray.toArray() == array.toArray())
        })
    }
    
    func testSetImmutableArray() throws {
        let array1 = MutableArrayObject()
        array1.addString("a1")
        array1.addDictionary(MutableDictionaryObject(data: ["name": "n1"]))
        
        let doc1a = createDocument("doc1")
        doc1a.setArray(array1, forKey: "array1")
        try saveDocument(doc1a)
        
        let doc1 = try defaultCollection!.document(id: doc1a.id)!
        let doc1b = doc1.toMutable()
        doc1b.setArray(doc1.array(forKey: "array1"), forKey: "array1b")
        
        let array2 = MutableArrayObject()
        array2.addString("a2")
        array2.addDictionary(MutableDictionaryObject(data: ["name": "n2"]))
        doc1b.setArray(array2, forKey: "array2")
        
        let dict: [String: Any] = ["array1": ["a1", ["name": "n1"]],
                                   "array1b": ["a1", ["name": "n1"]],
                                   "array2": ["a2", ["name": "n2"]]]
        try saveDocument(doc1b, eval: { (d) in
            XCTAssert(d.toDictionary() == dict)
        })
    }
    
    func testGetArray() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.array(forKey: "null"))
            XCTAssertNil(d.array(forKey: "true"))
            XCTAssertNil(d.array(forKey: "false"))
            XCTAssertNil(d.array(forKey: "string"));
            XCTAssertNil(d.array(forKey: "zero"))
            XCTAssertNil(d.array(forKey: "one"))
            XCTAssertNil(d.array(forKey: "minus_one"))
            XCTAssertNil(d.array(forKey: "one_dot_one"))
            XCTAssertNil(d.array(forKey: "date"))
            XCTAssertNil(d.array(forKey: "dict"))
            XCTAssertTrue(d.array(forKey: "array")!.toArray() == ["650-123-0001", "650-123-0002"])
            XCTAssertNil(d.array(forKey: "blob"))
            XCTAssertNil(d.array(forKey: "non_existing_key"))
        })
    }
    
    func testSetNSNull() throws {
        let doc = createDocument("doc1")
        doc.setValue(NSNull(), forKey: "null")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.value(forKey: "null") as! NSNull, NSNull())
            XCTAssertEqual(d.count, 1)
        })
    }
    
    func testSetNil() throws {
        // Note:
        // * As of Oct 2017, we've decided to change the behavior of storing nil into a CBLMutableDictionary
        //   to make it correspond to Cocoa idioms, i.e. it removes the value, instead of storing NSNull.
        // * As of Nov 2017, after API review, we've decided to revert the behavior to allow the API to
        //   be the same across platform. This means that setting nil value will be converted to NSNull
        //   instead of removing the value.
        let doc = createDocument("doc1")
        doc.setValue("something", forKey: "nil")
        doc.setValue(nil, forKey: "nil")
        doc.setValue(NSNull(), forKey: "null")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.value(forKey: "nil") as! NSNull, NSNull())
            XCTAssertEqual(d.value(forKey: "null") as! NSNull, NSNull())
            XCTAssertEqual(d.count, 2)
        })
    }
    
    func testSetNativeDictionary() throws {
        let content = kTestBlob.data(using: String.Encoding.utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        let dict: [String: Any] = ["street": "1 Main street",
                                   "city": "Mountain View",
                                   "state": "CA",
                                   "attachments": ["attach1": blob]]
        
        let doc = createDocument("doc1")
        doc.setValue(dict, forKey: "address")
        
        let address = doc.dictionary(forKey: "address")!
        XCTAssertTrue(address === doc.value(forKey: "address") as! DictionaryObject)
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
        let attachments = address.dictionary(forKey: "attachments")!
        XCTAssertEqual(attachments.blob(forKey: "attach1"), blob)
        XCTAssertTrue(address.toDictionary() == dict)
        
        // Update with a new dictionary:
        let nuDict = ["street": "1 Second street",
                      "city": "Palo Alto",
                      "state": "CA"]
        doc.setValue(nuDict, forKey: "address")
        
        // Check whether the old address dictionary is still accessible:
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
        XCTAssertTrue(address.toDictionary() == dict)
        
        // The old address dictionary should be detached:
        let nuAddress = doc.dictionary(forKey: "address")!
        XCTAssertTrue(address !== nuAddress)
        
        // Update nuAddress:
        nuAddress.setValue("94032", forKey: "zip")
        XCTAssertEqual(nuAddress.string(forKey: "zip"), "94032")
        XCTAssertNil(address.string(forKey: "zip"))
        
        // Save:
        try saveDocument(doc, eval: { (d) in
            let savedDict: [String: Any] = ["address": ["street": "1 Second street",
                                                        "city": "Palo Alto",
                                                        "state": "CA",
                                                        "zip": "94032"]]
            XCTAssertTrue(d.toDictionary() == savedDict)
        })
    }
    
    func testSetNativeArray() throws {
        let content = kTestBlob.data(using: String.Encoding.utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        let array: [Any] = ["a", "b", "c", [blob]]
        
        let doc = createDocument("doc1")
        doc.setValue(array, forKey: "members")
        
        let members = doc.array(forKey: "members")!
        XCTAssertTrue(members === doc.value(forKey: "members") as! ArrayObject)
        XCTAssertEqual(members.count, 4)
        XCTAssertEqual(members.string(at: 0), "a")
        XCTAssertEqual(members.string(at: 1), "b")
        XCTAssertEqual(members.string(at: 2), "c")
        let blobs = members.array(at: 3)!
        XCTAssertEqual(blobs.count, 1)
        XCTAssertEqual(blobs.blob(at: 0), blob)
        XCTAssertTrue(members.toArray() == ["a", "b", "c", [blob]])
        
        // Update with a new array:
        let nuArray = ["d", "e", "f"]
        doc.setValue(nuArray, forKey: "members")
        
        // Check whether the old members array is still accessible:
        XCTAssertTrue(members.toArray() == ["a", "b", "c", [blob]])
        
        // The old members array should be detached:
        let nuMembers = doc.array(forKey: "members")!
        XCTAssertTrue(nuMembers !== members)
        
        // Update nuMembers:
        nuMembers.addValue("g")
        XCTAssertEqual(nuMembers.count, 4)
        XCTAssertEqual(nuMembers.string(at: 3), "g")
        
        // Save:
        try saveDocument(doc, eval: { (d) in
            let savedDict: [String: Any] = ["members": ["d", "e", "f", "g"]]
            XCTAssertTrue(d.toDictionary() == savedDict)
        })
    }
    
    func testUpdateNestedDictionary() throws {
        var doc = createDocument("doc1")
        let addresses = MutableDictionaryObject()
        doc.setValue(addresses, forKey: "addresses")
        
        var shipping = MutableDictionaryObject()
        shipping.setValue("1 Main street", forKey: "street")
        shipping.setValue("Mountain View", forKey: "city")
        shipping.setValue("CA", forKey: "state")
        addresses.setValue(shipping, forKey: "shipping")
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() ==
                ["addresses":
                    ["shipping":
                        ["street": "1 Main street",
                         "city": "Mountain View",
                         "state": "CA"]]])
        })
        
        // Update:
        shipping = doc.dictionary(forKey: "addresses")!.dictionary(forKey: "shipping")!
        shipping.setValue("94042", forKey: "zip")
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() ==
                ["addresses":
                    ["shipping":
                        ["street": "1 Main street",
                         "city": "Mountain View",
                         "state": "CA",
                         "zip": "94042"]]])
        })
        
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        shipping = doc.dictionary(forKey: "addresses")!.dictionary(forKey: "shipping")!
        shipping.setValue("2 Main street", forKey: "street")
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() ==
                ["addresses":
                    ["shipping":
                        ["street": "2 Main street",
                         "city": "Mountain View",
                         "state": "CA",
                         "zip": "94042"]]])
        })
    }
    
    func testUpdateDictionaryInArray() throws {
        var doc = createDocument("doc1")
        let addresses = MutableArrayObject()
        doc.setValue(addresses, forKey: "addresses")
        
        var address1 = MutableDictionaryObject()
        address1.setValue("1 Main street", forKey: "street")
        address1.setValue("Mountain View", forKey: "city")
        address1.setValue("CA", forKey: "state")
        addresses.addValue(address1)
        
        var address2 = MutableDictionaryObject()
        address2.setValue("1 Second street", forKey: "street")
        address2.setValue("Palo Alto", forKey: "city")
        address2.setValue("CA", forKey: "state")
        addresses.addValue(address2)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() ==
                ["addresses": [["street": "1 Main street",
                                "city": "Mountain View",
                                "state": "CA"],
                               ["street": "1 Second street",
                                "city": "Palo Alto",
                                "state": "CA"]]])
        })
        
        // Update:
        address1 = doc.array(forKey: "addresses")!.dictionary(at: 0)!
        address1.setValue("94042", forKey: "zip")
        
        address2 = doc.array(forKey: "addresses")!.dictionary(at: 1)!
        address2.setValue("94302", forKey: "zip")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() ==
                ["addresses": [["street": "1 Main street",
                                "city": "Mountain View",
                                "state": "CA",
                                "zip": "94042"],
                               ["street": "1 Second street",
                                "city": "Palo Alto",
                                "state": "CA",
                                "zip": "94302"]]])
        })
        
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        address1 = doc.array(forKey: "addresses")!.dictionary(at: 0)!
        address1.setValue("2 Main street", forKey: "street")
        
        address2 = doc.array(forKey: "addresses")!.dictionary(at: 1)!
        address2.setValue("2 Second street", forKey: "street")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() ==
                ["addresses": [["street": "2 Main street",
                                "city": "Mountain View",
                                "state": "CA",
                                "zip": "94042"],
                               ["street": "2 Second street",
                                "city": "Palo Alto",
                                "state": "CA",
                                "zip": "94302"]]])
        })
    }
    
    func testUpdateNestedArray() throws {
        var doc = createDocument("doc1")
        let groups = MutableArrayObject()
        doc.setValue(groups, forKey: "groups")
        
        var group1 = MutableArrayObject()
        group1.addValue("a")
        group1.addValue("b")
        group1.addValue("c")
        groups.addValue(group1)
        
        var group2 = MutableArrayObject()
        group2.addValue(1)
        group2.addValue(2)
        group2.addValue(3)
        groups.addValue(group2)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() == ["groups": [["a", "b", "c"], [1, 2, 3]]])
        })
        
        // Update:
        group1 = doc.array(forKey: "groups")!.array(at: 0)!
        group1.setValue("d", at: 0)
        group1.setValue("e", at: 1)
        group1.setValue("f", at: 2)
        
        group2 = doc.array(forKey: "groups")!.array(at: 1)!
        group2.setValue(4, at: 0)
        group2.setValue(5, at: 1)
        group2.setValue(6, at: 2)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() == ["groups": [["d", "e", "f"], [4, 5, 6]]])
        })
        
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        group1 = doc.array(forKey: "groups")!.array(at: 0)!
        group1.setValue("g", at: 0)
        group1.setValue("h", at: 1)
        group1.setValue("i", at: 2)
        
        group2 = doc.array(forKey: "groups")!.array(at: 1)!
        group2.setValue(7, at: 0)
        group2.setValue(8, at: 1)
        group2.setValue(9, at: 2)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() == ["groups": [["g", "h", "i"], [7, 8, 9]]])
        })
    }
    
    func testUpdateArrayInDictionary() throws {
        var doc = createDocument("doc1")
        
        let group1 = MutableDictionaryObject()
        var member1 = MutableArrayObject()
        member1.addValue("a")
        member1.addValue("b")
        member1.addValue("c")
        group1.setValue(member1, forKey: "member")
        doc.setValue(group1, forKey: "group1")
        
        let group2 = MutableDictionaryObject()
        var member2 = MutableArrayObject()
        member2.addValue(1)
        member2.addValue(2)
        member2.addValue(3)
        group2.setValue(member2, forKey: "member")
        doc.setValue(group2, forKey: "group2")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() == ["group1": ["member": ["a", "b", "c"]],
                                               "group2": ["member": [1, 2, 3]]])
        })
        
        // Update:
        member1 = doc.dictionary(forKey: "group1")!.array(forKey: "member")!
        member1.setValue("d", at: 0)
        member1.setValue("e", at: 1)
        member1.setValue("f", at: 2)
        
        member2 = doc.dictionary(forKey: "group2")!.array(forKey: "member")!
        member2.setValue(4, at: 0)
        member2.setValue(5, at: 1)
        member2.setValue(6, at: 2)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() == ["group1": ["member": ["d", "e", "f"]],
                                               "group2": ["member": [4, 5, 6]]])
        })
       
        // Get and update:
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        member1 = doc.dictionary(forKey: "group1")!.array(forKey: "member")!
        member1.setValue("g", at: 0)
        member1.setValue("h", at: 1)
        member1.setValue("i", at: 2)
        
        member2 = doc.dictionary(forKey: "group2")!.array(forKey: "member")!
        member2.setValue(7, at: 0)
        member2.setValue(8, at: 1)
        member2.setValue(9, at: 2)
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.toDictionary() == ["group1": ["member": ["g", "h", "i"]],
                                               "group2": ["member": [7, 8, 9]]])
        })
    }
    
    func testSetDictionaryToMultipleKeys() throws {
        let doc = createDocument("doc1")
        let address = MutableDictionaryObject()
        address.setValue("1 Main street", forKey: "street")
        address.setValue("Mountain View", forKey: "city")
        address.setValue("CA", forKey: "state")
        doc.setValue(address, forKey: "shipping")
        doc.setValue(address, forKey: "billing")
        
        XCTAssert(doc.dictionary(forKey: "shipping")! === address)
        XCTAssert(doc.dictionary(forKey: "billing")! === address)
        
        // Update address: both shipping and billing should get the update:
        address.setValue("94042", forKey: "zip")
        XCTAssertEqual(doc.dictionary(forKey: "shipping")!.string(forKey: "zip"), "94042")
        XCTAssertEqual(doc.dictionary(forKey: "billing")!.string(forKey: "zip"), "94042")
        
        try saveDocument(doc)
        
        // Both shipping address and billing address are still the same instance:
        let shipping = doc.dictionary(forKey: "shipping")!
        let billing = doc.dictionary(forKey: "billing")!
        XCTAssert(shipping === address)
        XCTAssert(billing === address)
        
        // After save: both shipping and billing address are now independent to each other
        let savedDoc = try defaultCollection!.document(id: doc.id)!
        let savedShipping = savedDoc.dictionary(forKey: "shipping")!
        let savedBilling = savedDoc.dictionary(forKey: "billing")!
        XCTAssert(savedShipping !== address)
        XCTAssert(savedBilling !== address)
        XCTAssert(savedShipping !== savedBilling)
    }
    
    func testSetArrayToMultipleKeys() throws {
        let doc = createDocument("doc1")
        
        let phones = MutableArrayObject()
        phones.addValue("650-000-0001")
        phones.addValue("650-000-0002")
        
        doc.setValue(phones, forKey: "mobile")
        doc.setValue(phones, forKey: "home")
        
        XCTAssert(doc.array(forKey: "mobile")! === phones)
        XCTAssert(doc.array(forKey: "home")! === phones)
        
        // Update phones: both mobile and home should get the update
        phones.addValue("650-000-0003")
        XCTAssert(doc.array(forKey: "mobile")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003"])
        XCTAssert(doc.array(forKey: "home")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003"])
        
        try saveDocument(doc)
        
        // Both mobile and home are still the same instance:
        let mobile = doc.array(forKey: "mobile")!
        let home = doc.array(forKey: "home")!
        XCTAssert(mobile === phones)
        XCTAssert(home === phones)
        
        // After getting the document from the database, mobile and home
        // are now independent to each other:
        let savedDoc = try defaultCollection!.document(id: doc.id)!
        let savedMobile = savedDoc.array(forKey: "mobile")!
        let savedHome = savedDoc.array(forKey: "home")!
        XCTAssert(savedMobile !== phones)
        XCTAssert(savedHome !== phones)
        XCTAssert(savedMobile !== savedHome)
    }
    
    func testCount() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc) { (d) in
            XCTAssertEqual(d.count, 12)
            XCTAssertEqual(d.toDictionary().count, d.count)
        }
    }
    
    func testContainsKey() throws {
        let doc = createDocument("doc1")
        let dict: [String: Any] = ["type": "profile",
                                   "name": "Jason",
                                   "age": "30",
                                   "remote": false,
                                   "active": true,
                                   "address": ["street": "1 milky way."]]
        doc.setData(dict)
        
        // Swift Sequence Protocol
        XCTAssert(doc.contains("type"))
        XCTAssert(doc.contains("name"))
        XCTAssert(doc.contains("age"))
        XCTAssert(doc.contains("remote"))
        XCTAssert(doc.contains("active"))
        XCTAssert(doc.contains("address"))
        XCTAssertFalse(doc.contains("weight"))
        
        // DictionaryProtocol
        XCTAssert(doc.contains(key: "type"))
        XCTAssert(doc.contains(key: "name"))
        XCTAssert(doc.contains(key: "age"))
        XCTAssert(doc.contains(key: "remote"))
        XCTAssert(doc.contains(key: "active"))
        XCTAssert(doc.contains(key: "address"))
        XCTAssertFalse(doc.contains(key: "weight"))
    }
    
    func testRemoveKeys() throws {
        let doc = createDocument("doc1")
        let dict: [String: Any] = ["type": "profile",
                                   "name": "Jason",
                                   "weight": 130.5,
                                   "active": true,
                                   "age": 30,
                                   "address": [
                                    "street": "1 milky way.",
                                    "city": "galaxy city",
                                    "zip": 12345]]
        doc.setData(dict)
        
        try saveDocument(doc)
        
        doc.removeValue(forKey: "name")
        doc.removeValue(forKey: "weight")
        doc.removeValue(forKey: "age")
        doc.removeValue(forKey: "active")
        doc.dictionary(forKey: "address")?.removeValue(forKey: "city")
        
        XCTAssertNil(doc.string(forKey: "name"))
        XCTAssertEqual(doc.float(forKey: "weight"), 0.0)
        XCTAssertEqual(doc.double(forKey: "weight"), 0.0)
        XCTAssertEqual(doc.int(forKey: "age"), 0)
        XCTAssertEqual(doc.boolean(forKey: "active"), false)
        
        XCTAssertNil(doc.value(forKey: "name"))
        XCTAssertNil(doc.value(forKey: "weight"))
        XCTAssertNil(doc.value(forKey: "age"))
        XCTAssertNil(doc.value(forKey: "active"))
        XCTAssertNil(doc.dictionary(forKey: "address")!.value(forKey: "city"))
        
        XCTAssertFalse(doc.contains("name"))
        XCTAssertFalse(doc.contains("weight"))
        XCTAssertFalse(doc.contains("age"))
        XCTAssertFalse(doc.contains("active"))
        XCTAssertFalse(doc.dictionary(forKey: "address")!.contains("city"))
        
        let docDict: [String: Any] = ["type": "profile",
                                      "address": ["street": "1 milky way.", "zip": 12345]];
        XCTAssert(doc.toDictionary() == docDict)
        
        let address = doc.dictionary(forKey: "address")!
        let addressDict: [String: Any] = ["street": "1 milky way.", "zip": 12345]
        XCTAssert(address.toDictionary() == addressDict)
        
        // Remove the rest:
        doc.removeValue(forKey: "type")
        doc.removeValue(forKey: "address")
        XCTAssertNil(doc.value(forKey: "type"))
        XCTAssertNil(doc.value(forKey: "address"))
        XCTAssertFalse(doc.contains("type"))
        XCTAssertFalse(doc.contains("address"))
        XCTAssert(doc.toDictionary() == [:] as [String: Any])
    }
    
    func testDeleteDocument() throws {
        let doc = createDocument("doc1")
        doc.setValue("Scott Tiger", forKey: "name")
        
        // Save:
        try saveDocument(doc)
        
        // Delete:
        let savedDoc = try self.defaultCollection!.document(id: doc.id)!
        try self.defaultCollection!.delete(document: savedDoc)
        XCTAssertNil(try self.defaultCollection!.document(id: savedDoc.id))
        
        // Delete again:
        try self.defaultCollection!.delete(document: savedDoc)
        XCTAssertNil(try self.defaultCollection!.document(id: savedDoc.id))
    }
    
    
    func testDictionaryAfterDeleteDocument() throws {
        let dict = ["address": ["street": "1 Main street",
                                "city": "Mountain View",
                                "state": "CA"]]
        
        let doc = createDocument("doc1", data: dict)
        try saveDocument(doc)
        
        
        let savedDoc = try defaultCollection!.document(id: doc.id)!
        let address = savedDoc.dictionary(forKey: "address")!
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
        
        try defaultCollection!.delete(document: savedDoc)
        XCTAssertNil(try defaultCollection!.document(id: savedDoc.id))
        
        // The dictionary still has data:
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
    }
    
    func testPurgeDocument() throws {
        let doc1 = createDocument("doc1")
        doc1.setValue("profile", forKey: "type")
        doc1.setValue("Scott", forKey: "name")
        
        // Purge before save:
        expectError(domain: CBLError.domain, code: CBLError.notFound) {
            try self.defaultCollection!.purge(document: doc1)
        }
        
        try saveDocument(doc1)
        
        // Purge:
        try defaultCollection!.purge(document: doc1)
        
        // Get and purge:
        let doc2 = createDocument("doc2")
        doc2.setValue("profile", forKey: "type")
        doc2.setValue("Scott", forKey: "name")
        try saveDocument(doc2)
        
        try defaultCollection!.purge(id: doc2.id)
    }
    
    func testReopenDB() throws {
        let doc = createDocument("doc1")
        doc.setValue("str", forKey: "string")
        
        try saveDocument(doc)
        
        try self.reopenDB()
        
        let savedDoc = try self.defaultCollection!.document(id: "doc1")!
        XCTAssertEqual(savedDoc.string(forKey: "string"), "str")
        XCTAssert(savedDoc.toDictionary() == ["string": "str"] as [String: Any])
    }
    
    func testBlob() throws {
        let content = kTestBlob.data(using: String.Encoding.utf8)!
        var blob = Blob(contentType: "text/plain", data: content)
        
        let doc = createDocument("doc1")
        doc.setValue(blob, forKey: "data")
        doc.setValue("Jim", forKey: "name")
        
        try saveDocument(doc)
        try reopenDB()
        
        let savedDoc = try defaultCollection!.document(id: "doc1")!
        XCTAssertEqual(savedDoc.string(forKey: "name"), "Jim")
        XCTAssert(savedDoc.value(forKey: "data") as? Blob != nil)
        
        blob = savedDoc.blob(forKey: "data")!
        XCTAssertEqual(blob.contentType, "text/plain")
        XCTAssertEqual(blob.length, UInt64(kTestBlob.count))
        XCTAssertEqual(blob.content, content)
        
        let stream = blob.contentStream!
        stream.open()
        var buffer = Array<UInt8>(repeating: 0, count: 10)
        let bytesRead = stream.read(&buffer, maxLength: 10)
        XCTAssertEqual(bytesRead, 8)
        stream.close()
    }
    
    func testBlobWithStream() throws {
        let content = kTestBlob.data(using: String.Encoding.utf8)
        var stream = InputStream(data: content!)
        var blob = Blob(contentType: "text/plain", contentStream: stream)
        XCTAssertNotNil(blob)
        let doc = createDocument("doc1")
        doc.setValue(blob, forKey: "data")
        try saveDocument(doc)
        
        let savedDoc = try defaultCollection!.document(id: doc.id)!
        blob = savedDoc.blob(forKey: "data")!
        stream = blob.contentStream!
        stream.open()
        var buffer = Array<UInt8>(repeating: 0, count: 10)
        let bytesRead = stream.read(&buffer, maxLength: 10)
        XCTAssertEqual(bytesRead, 8)
        stream.close()
    }
    
    func testMultipleBlobRead() throws {
        let content = kTestBlob.data(using: String.Encoding.utf8)!
        var blob = Blob(contentType: "text/plain", data: content)
        let doc = createDocument("doc1")
        doc.setValue(blob, forKey: "data")
        
        blob = doc.blob(forKey: "data")!
        for _ in 1...5 {
            XCTAssertEqual(blob.content!, content)
            let stream = blob.contentStream!
            stream.open()
            var buffer = Array<UInt8>(repeating: 0, count: 10)
            let bytesRead = stream.read(&buffer, maxLength: 10)
            XCTAssertEqual(bytesRead, 8)
            stream.close()
        }
        
        try saveDocument(doc)
        let savedDoc = try defaultCollection!.document(id: doc.id)!
        blob = savedDoc.blob(forKey: "data")!
        for _ in 1...5 {
            XCTAssertEqual(blob.content!, content)
            let stream = blob.contentStream!
            stream.open()
            var buffer = Array<UInt8>(repeating: 0, count: 10)
            let bytesRead = stream.read(&buffer, maxLength: 10)
            XCTAssertEqual(bytesRead, 8)
            stream.close()
        }
    }
    
    func testReadingExistingBlob() throws {
        let content = kTestBlob.data(using: String.Encoding.utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        
        var doc = createDocument("doc1")
        doc.setValue(blob, forKey: "data")
        doc.setValue("Jim", forKey: "name")
        try saveDocument(doc)
        
        var savedDoc = try defaultCollection!.document(id: doc.id)!
        XCTAssert(savedDoc.value(forKey: "data") as? Blob != nil)
        XCTAssertEqual(savedDoc.blob(forKey: "data")!.content!, content)
        
        try reopenDB()
        
        doc = try defaultCollection!.document(id: doc.id)!.toMutable()
        doc.setValue("bar", forKey: "foo")
        try saveDocument(doc)
        
        savedDoc = try defaultCollection!.document(id: doc.id)!
        XCTAssert(savedDoc.value(forKey: "data") as? Blob != nil)
        XCTAssertEqual(savedDoc.blob(forKey: "data")!.content!, content)
    }
    
    func testEnumeratingKeys() throws {
        let doc = createDocument("doc1")
        for i in 0...19 {
            doc.setValue(i, forKey: "key\(i)")
        }
        var content = doc.toDictionary()
        
        var result: [String: Any] = [:]
        var count = 0
        for key in doc {
            result[key] = doc.int(forKey: key)
            count = count + 1
        }
        XCTAssert(result == content)
        XCTAssertEqual(count, content.count)
        
        // Update:
        
        doc.removeValue(forKey: "key2")
        doc.setValue(20, forKey: "key20")
        doc.setValue(21, forKey: "key21")
        content = doc.toDictionary()
        
        try saveDocument(doc) { (d) in
            result = [:]
            count = 0
            for key in d {
                result[key] = d.value(forKey: key)
                count = count + 1
            }
            XCTAssert(result == content)
            XCTAssertEqual(count, content.count)
        }
    }
    
    func testEquality() throws {
        let data1 = "data1".data(using: String.Encoding.utf8)!
        let data2 = "data2".data(using: String.Encoding.utf8)!
        
        let doc1a = createDocument("doc1")
        doc1a.setInt(42, forKey: "answer")
        doc1a.setValue(["1", "2", "3"], forKey: "options")
        doc1a.setBlob(Blob.init(contentType: "text/plain", data: data1), forKey: "attachment")
        
        let doc1b = createDocument("doc1")
        doc1b.setInt(42, forKey: "answer")
        doc1b.setValue(["1", "2", "3"], forKey: "options")
        doc1b.setBlob(Blob.init(contentType: "text/plain", data: data1), forKey: "attachment")
        
        let doc1c = createDocument("doc1")
        doc1c.setInt(42, forKey: "answer")
        doc1c.setValue(["1", "2", "3"], forKey: "options")
        doc1c.setString("This is a comment", forKey: "comment")
        doc1c.setBlob(Blob.init(contentType: "text/plain", data: data2), forKey: "attachment")
        
        XCTAssert(doc1a == doc1a)
        XCTAssert(doc1a == doc1b)
        XCTAssert(doc1a != doc1c)
        
        XCTAssert(doc1b == doc1a)
        XCTAssert(doc1b == doc1b)
        XCTAssert(doc1b != doc1c)
        
        XCTAssert(doc1c != doc1a)
        XCTAssert(doc1c != doc1b)
        XCTAssert(doc1c == doc1c)
        
        try saveDocument(doc1c)
        
        let savedDoc = try defaultCollection!.document(id: "doc1")!
        XCTAssert(savedDoc == savedDoc)
        XCTAssert(savedDoc == doc1c)
        
        let mDoc = savedDoc.toMutable()
        XCTAssert(mDoc == savedDoc)
        mDoc.setInt(50, forKey: "answer")
        XCTAssert(mDoc != savedDoc)
    }
    
    func testEqualityDifferentDocID() throws {
        let doc1 = createDocument("doc1")
        doc1.setInt(42, forKey: "answer")
        try saveDocument(doc1)
        let sdoc1 = try defaultCollection!.document(id: "doc1")
        XCTAssert(sdoc1 == doc1)
        
        let doc2 = createDocument("doc2")
        doc2.setInt(42, forKey: "answer")
        try saveDocument(doc2)
        let sdoc2 = try defaultCollection!.document(id: "doc2")
        XCTAssert(sdoc2 == doc2)
        
        XCTAssert(doc1 == doc1)
        XCTAssert(doc1 != doc2)
        
        XCTAssert(doc2 != doc1)
        XCTAssert(doc2 == doc2)
        
        XCTAssert(sdoc1 == sdoc1)
        XCTAssert(sdoc1 != sdoc2)
        
        XCTAssert(sdoc2 != sdoc1)
        XCTAssert(sdoc2 == sdoc2)
    }
    
    func testEqualityDifferentDB() throws {
        let doc1a = createDocument("doc1")
        doc1a.setInt(42, forKey: "answer")
        
        let otherDb = try openDB(name: "other")
        let doc1b = createDocument("doc1")
        doc1b.setInt(42, forKey: "answer")
        
        XCTAssert(doc1a == doc1b)
        
        try defaultCollection!.save(document: doc1a)
        try otherDb.defaultCollection().save(document: doc1b)
        
        var sdoc1a = try defaultCollection!.document(id: doc1a.id)!
        var sdoc1b = try otherDb.defaultCollection().document(id: doc1b.id)!
        
        XCTAssert(sdoc1a == doc1a)
        XCTAssert(sdoc1b == doc1b)
        
        XCTAssert(doc1a != doc1b)
        XCTAssert(sdoc1a != sdoc1b)
        
        sdoc1a = try defaultCollection!.document(id: "doc1")!
        sdoc1b = try otherDb.defaultCollection().document(id: "doc1")!
        XCTAssert(sdoc1a != sdoc1b)
        try otherDb.close()
        
        let sameDB = try openDB(name: db.name)
        let anotherDoc1a = try sameDB.defaultCollection().document(id: "doc1")
        XCTAssert(sdoc1a == anotherDoc1a)
        try sameDB.close()
    }
    
    func testRevisionIDNewDoc() throws {
        let doc = createDocument("doc1")
        doc.setString("some", forKey: "key")
        XCTAssertNil(doc.revisionID)
        
        try saveDocument(doc)
        XCTAssertNotNil(doc.revisionID)
    }
    
    func testRevisionIDExistingDoc() throws {
        let _ = try generateDocument(withID: "doc")
        
        // doc from database should always have a revision-id
        let doc = try defaultCollection!.document(id: "doc")
        let revisionID = doc?.revisionID
        XCTAssertNotNil(revisionID)
        
        // making doc as mutable will keep the same revision-id
        let mDoc = doc!.toMutable()
        XCTAssertEqual(revisionID, mDoc.revisionID)
        
        // modifying the doc and saving will update the revision-id.
        // also this will not affect the previous document revision-id
        mDoc.setString("modify", forKey: "update")
        try saveDocument(mDoc)
        XCTAssertNotNil(mDoc.revisionID)
        XCTAssertNotNil(doc?.revisionID)
        XCTAssert(revisionID != mDoc.revisionID)
        XCTAssertEqual(revisionID, doc?.revisionID)
    }
    
    // MARK: toJSON
    
    // CBL-4855
    func testJSONNumber () throws {
        // assigned type [String: Any] -> key1 Int and key2 Double
        let dict1 : [String : Any] = ["key1": 12345, "key2": 10.5]
        XCTAssert(type(of: dict1["key1"]!) == Int.self)
        let mdoc1 = MutableDocument(id: "doc1", data: dict1)
        try self.defaultCollection!.save(document: mdoc1)
        let doc1 = try self.defaultCollection!.document(id: "doc1")!
        let json1 = doc1.toJSON()
        XCTAssertEqual("{\"key1\":12345,\"key2\":10.5}", json1)
        
        // no type -> Swift will assign a type to suit both -> Double
        let dict2 = ["key1": 12345, "key2": 10.5]
        XCTAssert(type(of: dict2["key1"]!) == Double.self)
        let mdoc2 = MutableDocument(id: "doc2", data: dict2)
        try self.defaultCollection!.save(document: mdoc2)
        let doc2 = try self.defaultCollection!.document(id: "doc2")!
        let json2 = doc2.toJSON()
        XCTAssertEqual("{\"key1\":12345.0,\"key2\":10.5}", json2)
        
        // JSONSerialization - assigned type [String: Any]
        let dict3 = try JSONSerialization.jsonObject(with: "{\"key1\": 12345, \"key2\": 10.5 }".data(using: .utf8)!, options: []) as! [String : Any]
        let mdoc3 = MutableDocument(id: "doc3", data: dict3)
        try self.defaultCollection!.save(document: mdoc3)
        let doc3 = try self.defaultCollection!.document(id: "doc3")!
        let json3 = doc3.toJSON()
        XCTAssertEqual("{\"key1\":12345,\"key2\":10.5}", json3)
    }
    
    func testDocumentToJSON() throws {
        let json = try getRickAndMortyJSON()
        var mDoc = try MutableDocument(id: "doc", json: json)
        try self.defaultCollection!.save(document: mDoc)
        
        var doc = try self.defaultCollection!.document(id: "doc")
        var jsonObj = doc?.toJSON().toJSONObj() as! [String: Any]
        XCTAssertEqual(jsonObj["name"] as! String, "Rick Sanchez")
        XCTAssertEqual(jsonObj["id"] as! Int, 1)
        XCTAssertEqual(jsonObj["isAlive"] as! Bool, true)
        XCTAssertEqual(jsonObj["longitude"] as! Double, -21.152958)
        XCTAssertEqual((jsonObj["aka"] as! Array<Any>)[2] as! String, "Albert Ein-douche")
        XCTAssertEqual((jsonObj["family"] as! Array<[String: Any]>)[0]["name"] as! String, "Morty Smith")
        XCTAssertEqual((jsonObj["family"] as! Array<[String: Any]>)[3]["name"] as! String, "Summer Smith")
        XCTAssertEqual((jsonObj["origin"] as! [String: Any])[Blob.blobLengthProperty] as! Int, 12);
        XCTAssertEqual((jsonObj["origin"] as! [String: Any])[Blob.blobDigestProperty] as! String, "sha1-JeAPM4tj7RcZE3+YUIsEMzfCBqI=");
        XCTAssertEqual((jsonObj["origin"] as! [String: Any])[Blob.typeProperty] as! String, Blob.blobType);
        XCTAssertEqual((jsonObj["origin"] as! [String: Any])[Blob.blobContentType] as! String, "text/plain");
        XCTAssertEqual(jsonObj.count, 12)
        
        mDoc = doc!.toMutable()
        mDoc.setValue("newValueAppended", forKey: "newKeyAppended")
        try self.defaultCollection!.save(document: mDoc)
        
        doc = try self.defaultCollection!.document(id: "doc")
        jsonObj = doc!.toJSON().toJSONObj() as! [String: Any]
        XCTAssertEqual(jsonObj["newKeyAppended"] as! String, "newValueAppended")
        XCTAssertEqual(jsonObj.count, 13)
    }
    
    func testUnsavedMutableDocumentToJSON() throws {
        let mDoc = try MutableDocument(id: "doc", json: "{\"unsaved\":\"doc\"}")
        expectException(exception: .internalInconsistencyException) {
            let _ = mDoc.toJSON()
        }
    }
    
    func testSpecialJSONStrings() throws {
        var jsons = [
            "Random:String",
            "[\"item1\",\"item2\"]",
            "",
            " ",
            "[",
            "{",
            "{\"dictionary_without_value\"}",
            "[]"];
        var exceptionThrown = false
        for json in jsons {
            exceptionThrown = false
            do {
                let _ = try MutableDocument(json: json)
            } catch {
                exceptionThrown = true
                XCTAssertEqual((error as NSError).code, CBLError.invalidJSON)
                XCTAssertEqual((error as NSError).domain, CBLError.domain)
            }
            XCTAssert(exceptionThrown)
            
            exceptionThrown = false
            do {
                let _ = try MutableDictionaryObject(json: json)
            } catch {
                exceptionThrown = true
                XCTAssertEqual((error as NSError).code, CBLError.invalidJSON)
                XCTAssertEqual((error as NSError).domain, CBLError.domain)
            }
            XCTAssert(exceptionThrown)
        }
        
        jsons = ["{}"]
        for json in jsons {
            let mDoc = try MutableDocument(json: json)
            XCTAssertNotNil(mDoc)
            XCTAssertEqual(mDoc.count, 0)
            
            let mDict = try MutableDictionaryObject(json: json)
            XCTAssertNotNil(mDict)
            XCTAssertEqual(mDict.count, 0)
        }
    }
    
    func testBlobToJSON() throws {
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        try self.db.saveBlob(blob: blob)
        
        XCTAssertEqual((blob.toJSON().toJSONObj() as! [String: Any])[Blob.typeProperty] as! String, Blob.blobType)
        XCTAssertEqual((blob.toJSON().toJSONObj() as! [String: Any])[Blob.blobContentType] as! String, "text/plain")
        XCTAssertEqual((blob.toJSON().toJSONObj() as! [String: Any])[Blob.blobLengthProperty] as! UInt64, blob.length)
        XCTAssertEqual((blob.toJSON().toJSONObj() as! [String: Any])[Blob.blobDigestProperty] as? String, blob.digest)
        XCTAssertEqual((blob.toJSON().toJSONObj() as! [String: Any]).count, 4)
    }
    
    func testGetBlobFromProps() throws {
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        try self.db.saveBlob(blob: blob)
        
        let retrivedBlob = try self.db.getBlob(properties: [Blob.typeProperty: Blob.blobType,
                                                            Blob.blobDigestProperty: blob.digest!,
                                                            Blob.blobContentType: "text/plain",
                                                            Blob.blobLengthProperty: blob.length])
        XCTAssertNotNil(retrivedBlob)
        XCTAssertEqual(retrivedBlob!.digest, blob.digest)
        XCTAssertEqual(retrivedBlob!.content, blob.content)
    }
    
    func testUnsavedBlob() throws {
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        expectException(exception: .internalInconsistencyException) {
            let _ = blob.toJSON()
        }
    }
    
    func testUnknownDigest() throws {
        let blob = try self.db.getBlob(properties: [Blob.typeProperty:Blob.blobType,
                                                    Blob.blobDigestProperty: "sha1-JeAPM4tj7RcZE3+YUIsEMzfCBqI=",
                                                    Blob.blobContentType: "text/plain",
                                                    Blob.blobLengthProperty: 12])
        XCTAssertNil(blob)
    }
    
    func testGetBlobWithInvalidProps() throws {
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        try self.db.saveBlob(blob: blob)
        
        var b: Blob?
        expectException(exception: .invalidArgumentException) {
            b = try! self.db.getBlob(properties: [Blob.typeProperty:"bl0b",
                                                  Blob.blobDigestProperty: blob.digest! as String,
                                                  Blob.blobContentType: "text/plain",
                                                  Blob.blobLengthProperty: blob.length])
        }
        XCTAssertNil(b)
        
        expectException(exception: .invalidArgumentException) {
            b = try! self.db.getBlob(properties: ["type":Blob.blobType,
                                                  Blob.blobDigestProperty: blob.digest! as String,
                                                  Blob.blobContentType: "text/plain",
                                                  Blob.blobLengthProperty: blob.length])
        }
        XCTAssertNil(b)
        
        expectException(exception: .invalidArgumentException) {
            b = try! self.db.getBlob(properties: [Blob.typeProperty:Blob.blobType,
                                                  Blob.blobDigestProperty: blob.digest! as String,
                                                  Blob.blobContentType: 1234,
                                                  Blob.blobLengthProperty: blob.length])
        }
        XCTAssertNil(b)
        
        expectException(exception: .invalidArgumentException) {
            b = try! self.db.getBlob(properties: [Blob.typeProperty:Blob.blobType,
                                                  Blob.blobDigestProperty: blob.digest! as String,
                                                  Blob.blobContentType: "text/plain",
                                                  Blob.blobLengthProperty: "12"])
        }
        XCTAssertNil(b)
        
        expectException(exception: .invalidArgumentException) {
            b = try! self.db.getBlob(properties: [Blob.typeProperty:Blob.blobType,
                                                  Blob.blobDigestProperty: 12,
                                                  Blob.blobContentType: "text/plain",
                                                  Blob.blobLengthProperty: blob.length])
        }
        XCTAssertNil(b)
    }
    
    func testSaveBlobAndCompactDB() throws {
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        try self.db.saveBlob(blob: blob)
        
        var retrivedBlob = try self.db.getBlob(properties: [Blob.typeProperty:Blob.blobType,
                                                            Blob.blobDigestProperty: blob.digest!,
                                                            Blob.blobContentType: "text/plain",
                                                            Blob.blobLengthProperty: blob.length])
        XCTAssertNotNil(retrivedBlob)
        XCTAssertEqual(retrivedBlob!.digest, blob.digest)
        XCTAssertEqual(retrivedBlob!.content, blob.content)
        
        try self.db.performMaintenance(type: .compact)
        retrivedBlob = try self.db.getBlob(properties: [Blob.typeProperty:Blob.blobType,
                                                            Blob.blobDigestProperty: blob.digest!,
                                                            Blob.blobContentType: "text/plain",
                                                            Blob.blobLengthProperty: blob.length])
        XCTAssertNil(retrivedBlob)
        XCTAssertEqual(retrivedBlob?.length ?? 0, 0)
    }
    
    func testGetCollectionAfterDocIsSaved() throws {
        let col1 = try db.createCollection(name: "collection1")
        let doc = MutableDocument(id: "doc1")
        doc.setString("hello", forKey: "greeting")
        try col1.save(document: doc)
        XCTAssert(doc.collection == col1)
    }
    
    func testDocumentResaveInAnotherCollection() throws {
        let colA = try db.createCollection(name: "collA")
        let colB = try db.createCollection(name: "collB")
        
        var doc = MutableDocument(id: "doc1")
        doc.setString("hello", forKey: "greeting")
        
        try colA.save(document: doc)
        doc = try colA.document(id: "doc1")!.toMutable()
        self.expectError(domain: CBLError.domain, code: CBLError.invalidParameter) {
            try colB.save(document: doc)
        }
    }
    
    func testJSON() throws {
        let jsonString = """
        {
            "name": "John Doe",
            "foo": null
        }
        """
        
        if let jsonData = jsonString.data(using: .utf8) {
            do {
                // Step 3: Convert Data to dictionary
                if let jsonDictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any?] {
                    print(jsonDictionary)
                }
            } catch {
                print("Failed to convert JSON to dictionary: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: toJSONTimestamp & Revision history

    //  https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0005-Version-Vector.md
     
    // 1. TestDocumentTimestamp
    // Description
    //  Test that the document's timestamp returns value as expected.
    // Steps
    //  1. Create a new document with id = "doc1"
    //  2. Get document's timestamp and check that the timestamp is 0.
    //  3. Save the document into the default collection.
    //  4. Get document's timestamp and check that the timestamp is more than 0.
    //  5. Get the document id = "doc1" from the database.
    //  6. Get document's timestamp and check that the timestamp is the same as the timestamp from step 4.
    func testDocumentTimestamp() throws {
        var doc = MutableDocument(id: "doc1")
        assert(doc.timestamp == 0)
        
        try defaultCollection!.save(document: doc)
        let timestamp = doc.timestamp
        assert(timestamp > 0);
        
        doc = try defaultCollection!.document(id: "doc1")!.toMutable()
        assert(doc.timestamp == timestamp)
    }
    
    // 2. TestDocumentRevisionHistory
    // Description
    //  Test that the document's timestamp returns value as expected.
    // Steps
    //  1. Create a new document with id = "doc1"
    //  2. Get document's _revisionIDs and check that the value returned is an empty array.
    //  3. Save the document into the default collection.
    //  4. Get document's _revisionIDs and check that the value returned is an array containing a
    //      single revision id which is the revision id of the documnt.
    //  5. Get the document id = "doc1" from the database.
    //  6. Get document's _revisionIDs and check that the value returned is an array containing a
    //      single revision id which is the revision id of the documnt.
    func testDocumentRevisionHistory() throws {
        var doc = MutableDocument(id: "doc1")
        assert(doc._getRevisionHistory() == nil)
        
        try defaultCollection!.save(document: doc)
        assert(doc._getRevisionHistory() != nil)
        
        // Fails from LiteCore,only 1 rev, no rev history
        // doc = try defaultCollection!.document(id: "doc1")!.toMutable();
        // asser(doc._getRevisionHistory() != nil)
    }
}
