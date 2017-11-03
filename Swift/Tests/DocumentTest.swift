//
//  DocumentTest.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
        XCTAssertFalse(doc1a.isDeleted)
        XCTAssertEqual(doc1a.toDictionary().count, 0);
        
        let doc1b = try saveDocument(doc1a)
        XCTAssertTrue(doc1b !== doc1a)
        XCTAssertNotNil(doc1b)
        XCTAssertEqual(doc1a.id, doc1b.id)
    }
    
    
    func testCreateDocWithID() throws {
        let doc1a = MutableDocument("doc1")
        XCTAssertNotNil(doc1a)
        XCTAssertEqual(doc1a.id, "doc1")
        XCTAssertFalse(doc1a.isDeleted)
        XCTAssertEqual(doc1a.toDictionary().count, 0);
        
        let doc1b = try saveDocument(doc1a)
        XCTAssertTrue(doc1b !== doc1a)
        XCTAssertNotNil(doc1b)
        XCTAssertEqual(doc1a.id, doc1b.id)
    }
    
    
    func testCreateDocwithEmptyStringID() throws {
        let doc1a = MutableDocument("")
        XCTAssertNotNil(doc1a)
        
        var error: NSError? = nil
        do {
            try db.save(doc1a)
        } catch let err as NSError {
            error = err
        }
        
        XCTAssertNotNil(error)
        XCTAssertEqual(error!.code, 38)
        XCTAssertEqual(error!.domain, "LiteCore")
    }
    
    
    func testCreateDocWithNilID() throws {
        let doc1a = MutableDocument(nil)
        XCTAssertNotNil(doc1a)
        XCTAssertTrue(doc1a.id.count > 0)
        XCTAssertFalse(doc1a.isDeleted)
        XCTAssertEqual(doc1a.toDictionary().count, 0);
        
        let doc1b = try saveDocument(doc1a)
        XCTAssertTrue(doc1b !== doc1a)
        XCTAssertNotNil(doc1b)
        XCTAssertEqual(doc1a.id, doc1b.id)
    }
    
    
    func testCreateDocWithDict() throws {
        let dict: [String: Any] = ["name": "Scott Tiger",
                                   "age": 30,
                                   "address": ["street": "1 Main street.",
                                               "city": "Mountain View",
                                               "state": "CA"],
                                   "phones": ["650-123-0001", "650-123-0002"]]
        
        let doc1a = MutableDocument("doc1", dictionary: dict)
        XCTAssertNotNil(doc1a)
        XCTAssertTrue(doc1a.id.count > 0)
        XCTAssertFalse(doc1a.isDeleted)
        XCTAssertTrue(doc1a.toDictionary() ==  dict)
        
        let doc1b = try saveDocument(doc1a)
        XCTAssertTrue(doc1b !== doc1a)
        XCTAssertNotNil(doc1b)
        XCTAssertEqual(doc1b.id, doc1a.id)
        XCTAssertTrue(doc1b.toDictionary() ==  dict)
    }
    
    
    func testSetDictionaryContent() throws {
        let dict: [String: Any] = ["name": "Scott Tiger",
                                   "age": 30,
                                   "address": ["street": "1 Main street.",
                                               "city": "Mountain View",
                                               "state": "CA"],
                                   "phones": ["650-123-0001", "650-123-0002"]]
        
        let doc = createDocument("doc1")
        doc.setDictionary(dict)
        XCTAssertTrue(doc.toDictionary() ==  dict)
        
        let nuDict: [String: Any] = ["name": "Daniel Tiger",
                                     "age": 32,
                                     "address": ["street": "2 Main street.",
                                                 "city": "Palo Alto",
                                                 "state": "CA"],
                                     "phones": ["650-234-0001", "650-234-0002"]]
        doc.setDictionary(nuDict)
        XCTAssertTrue(doc.toDictionary() ==  nuDict)
        
        let savedDoc = try saveDocument(doc)
        XCTAssertTrue(savedDoc.toDictionary() ==  nuDict)
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
        
        let doc1b = anotherDb.getDocument("doc1")
        XCTAssertNotNil(doc1b)
        XCTAssertTrue(doc1b !== doc1a)
        XCTAssertEqual(doc1b!.id, doc1a.id)
        XCTAssertTrue(doc1b!.toDictionary() == doc1a.toDictionary())
        
        try anotherDb.close()
    }
    
    
    func testNoCacheNoLive() throws {
        let doc1a = createDocument("doc1")
        doc1a.setValue("Scott Tiger", forKey: "name")
        
        let savedDoc1a = try saveDocument(doc1a)
        
        let doc1b = db.getDocument("doc1")
        let doc1c = db.getDocument("doc1")
        
        let anotherDb = try openDB(name: db.name)
        let doc1d = anotherDb.getDocument("doc1")
        
        XCTAssertTrue(savedDoc1a !== doc1b)
        XCTAssertTrue(savedDoc1a !== doc1c)
        XCTAssertTrue(savedDoc1a !== doc1d)
        XCTAssertTrue(savedDoc1a !== doc1c)
        XCTAssertTrue(savedDoc1a !== doc1d)
        XCTAssertTrue(savedDoc1a !== doc1d)
        
        XCTAssertTrue(savedDoc1a.toDictionary() == doc1b!.toDictionary())
        XCTAssertTrue(savedDoc1a.toDictionary() == doc1c!.toDictionary())
        XCTAssertTrue(savedDoc1a.toDictionary() == doc1d!.toDictionary())
        
        // Update:
        
        let updatedDoc1b = doc1b!.edit()
        updatedDoc1b.setValue("Daniel Tiger", forKey: "name")
        let savedDoc1b = try saveDocument(updatedDoc1b)
        
        XCTAssertFalse(savedDoc1b.toDictionary() == savedDoc1a.toDictionary())
        XCTAssertFalse(savedDoc1b.toDictionary() == doc1c!.toDictionary())
        XCTAssertFalse(savedDoc1b.toDictionary() == doc1d!.toDictionary())
        
        try anotherDb.close()
    }
    
    
    func testSetString() throws {
        let doc = createDocument("doc1")
        doc.setValue("", forKey: "string1")
        doc.setValue("string", forKey: "string2")
        
        try saveDocument(doc) { (d) in
            XCTAssertEqual(d.string(forKey: "string1"), "")
            XCTAssertEqual(d.string(forKey: "string2"), "string")
        }
        
        // Update:
        
        doc.setValue("string", forKey: "string1")
        doc.setValue("", forKey: "string2")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.string(forKey: "string1"), "string")
            XCTAssertEqual(d.string(forKey: "string2"), "")
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
        let doc = createDocument("doc1")
        doc.setValue(1, forKey: "number1")
        doc.setValue(0, forKey: "number2")
        doc.setValue(-1, forKey: "number3")
        doc.setValue(1.1, forKey: "number4")
        doc.setValue(12345678, forKey: "number5")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(doc.int(forKey: "number1"), 1)
            XCTAssertEqual(doc.int(forKey: "number2"), 0)
            XCTAssertEqual(doc.int(forKey: "number3"), -1)
            XCTAssertEqual(doc.float(forKey: "number4"), 1.1)
            XCTAssertEqual(doc.double(forKey: "number4"), 1.1)
            XCTAssertEqual(doc.int(forKey: "number5"), 12345678)
        })
        
        // Update:
        
        doc.setValue(0, forKey: "number1")
        doc.setValue(1, forKey: "number2")
        doc.setValue(1.1, forKey: "number3")
        doc.setValue(-1, forKey: "number4")
        doc.setValue(-12345678, forKey: "number5")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(doc.int(forKey: "number1"), 0)
            XCTAssertEqual(doc.int(forKey: "number2"), 1)
            XCTAssertEqual(doc.float(forKey: "number3"), 1.1)
            XCTAssertEqual(doc.double(forKey: "number3"), 1.1)
            XCTAssertEqual(doc.int(forKey: "number4"), -1)
            XCTAssertEqual(doc.int(forKey: "number5"), -12345678)
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
        doc.setValue(Int.min, forKey: "min_int")
        doc.setValue(Int.max, forKey: "max_int")
        doc.setValue(Float.leastNormalMagnitude, forKey: "min_float")
        doc.setValue(Float.greatestFiniteMagnitude, forKey: "max_float")
        doc.setValue(Double.leastNormalMagnitude, forKey: "min_double")
        doc.setValue(Double.greatestFiniteMagnitude, forKey: "max_double")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.int(forKey: "min_int"), Int.min);
            XCTAssertEqual(d.int(forKey: "max_int"), Int.max);
            XCTAssertEqual(d.value(forKey: "min_int") as! Int, Int.min);
            XCTAssertEqual(d.value(forKey: "max_int") as! Int, Int.max);
            
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
        doc.setValue(1.00, forKey: "number1")
        doc.setValue(1.49, forKey: "number2")
        doc.setValue(1.50, forKey: "number3")
        doc.setValue(1.51, forKey: "number4")
        doc.setValue(1.99, forKey: "number5")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.int(forKey: "number1"), 1);
            XCTAssertEqual(d.float(forKey: "number1"), 1.00);
            XCTAssertEqual(d.double(forKey: "number1"), 1.00);
            
            XCTAssertEqual(d.int(forKey: "number2"), 1);
            XCTAssertEqual(d.float(forKey: "number2"), 1.49);
            XCTAssertEqual(d.double(forKey: "number2"), 1.49);
            
            XCTAssertEqual(d.int(forKey: "number3"), 1);
            XCTAssertEqual(d.float(forKey: "number3"), 1.50);
            XCTAssertEqual(d.double(forKey: "number3"), 1.50);
            
            XCTAssertEqual(d.int(forKey: "number4"), 1);
            XCTAssertEqual(d.float(forKey: "number4"), 1.51);
            XCTAssertEqual(d.double(forKey: "number4"), 1.51);
            
            XCTAssertEqual(d.int(forKey: "number5"), 1);
            XCTAssertEqual(d.float(forKey: "number5"), 1.99);
            XCTAssertEqual(d.double(forKey: "number5"), 1.99);
        })
    }
    
    
    func testSetBoolean() throws {
        let doc = createDocument("doc1")
        doc.setValue(true, forKey: "boolean1")
        doc.setValue(false, forKey: "boolean2")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.boolean(forKey: "boolean1"), true);
            XCTAssertEqual(d.boolean(forKey: "boolean2"), false);
        })
        
        // Update:
        
        doc.setValue(false, forKey: "boolean1")
        doc.setValue(true, forKey: "boolean2")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.boolean(forKey: "boolean1"), false);
            XCTAssertEqual(d.boolean(forKey: "boolean2"), true);
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
        let doc = createDocument("doc1")
        let date = Date()
        let dateStr = jsonFromDate(date)
        XCTAssertTrue(dateStr.count > 0)
        doc.setValue(date, forKey: "date")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.value(forKey: "date") as! String, dateStr);
            XCTAssertEqual(d.string(forKey: "date"), dateStr);
            XCTAssertEqual(jsonFromDate(d.date(forKey: "date")!), dateStr);
        })
        
        // Update:
        
        let nuDate = Date(timeInterval: 60.0, since: date)
        let nuDateStr = jsonFromDate(nuDate)
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
        let doc = createDocument("doc1")
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        doc.setValue(blob, forKey: "blob")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.blob(forKey: "blob")!.properties == blob.properties)
            XCTAssertEqual(d.blob(forKey: "blob")!.content, content)
        })
        
        // Update:
        
        let nuContent = "1234567890".data(using: .utf8)!
        let nuBlob = Blob(contentType: "text/plain", data: nuContent)
        doc.setValue(nuBlob, forKey: "blob")
        
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
        doc.setValue(dict, forKey: "dict")
        
        XCTAssertTrue(doc.value(forKey: "dict") as! DictionaryObject === dict)
        var savedDoc = try saveDocument(doc)
        
        XCTAssertTrue(savedDoc.value(forKey: "dict") as! DictionaryObject !== dict)
        XCTAssertTrue(savedDoc.value(forKey: "dict") as! DictionaryObject === savedDoc.dictionary(forKey: "dict")!)
        
        // Update:
        doc = savedDoc.edit()
        dict = doc.dictionary(forKey: "dict")!
        dict.setValue("Mountain View", forKey: "city")
        
        XCTAssertTrue(doc.value(forKey: "dict") as! DictionaryObject === doc.dictionary(forKey: "dict")!)
        let nsDict: [String: Any] = ["street": "1 Main street", "city": "Mountain View"]
        XCTAssertTrue(doc.dictionary(forKey: "dict")!.toDictionary() == nsDict)
        
        savedDoc = try saveDocument(doc)
        
        XCTAssertTrue(savedDoc.value(forKey: "dict") as! DictionaryObject !== dict)
        XCTAssertTrue(savedDoc.value(forKey: "dict") as! DictionaryObject === savedDoc.dictionary(forKey: "dict")!)
        XCTAssertTrue(savedDoc.dictionary(forKey: "dict")!.toDictionary() == nsDict)
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
        doc.setValue(array, forKey: "array")
        
        XCTAssertTrue(doc.value(forKey: "array") as! ArrayObject === array)
        XCTAssertTrue(doc.array(forKey: "array")! === array)
        XCTAssertTrue(doc.array(forKey: "array")!.toArray() == ["item1", "item2", "item3"])
        
        var savedDoc = try saveDocument(doc)
        
        XCTAssertTrue(savedDoc.value(forKey: "array") as! ArrayObject !== array)
        XCTAssertTrue(savedDoc.value(forKey: "array") as! ArrayObject === savedDoc.array(forKey: "array")!)
        XCTAssertTrue(savedDoc.array(forKey: "array")!.toArray() == ["item1", "item2", "item3"])
     
        // Update:
        doc = savedDoc.edit()
        array = doc.array(forKey: "array")!
        array.addValue("item4")
        array.addValue("item5")
        
        savedDoc = try saveDocument(doc)
        
        XCTAssertTrue(savedDoc.value(forKey: "array") as! ArrayObject !== array)
        XCTAssertTrue(savedDoc.value(forKey: "array") as! ArrayObject === savedDoc.array(forKey: "array")!)
        XCTAssertTrue(savedDoc.array(forKey: "array")!.toArray() == ["item1", "item2", "item3", "item4", "item5"])
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
    
    
    func testSetSwiftDictionary() throws {
        let dict = ["street": "1 Main street",
                    "city": "Mountain View",
                    "state": "CA"]
        
        let doc = createDocument("doc1")
        doc.setValue(dict, forKey: "address")
        
        let address = doc.dictionary(forKey: "address")!
        XCTAssertTrue(address === doc.value(forKey: "address") as! DictionaryObject)
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
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
        let savedDoc = try saveDocument(doc)
        let docDict: [String: Any] = ["address": ["street": "1 Second street",
                                                  "city": "Palo Alto",
                                                  "state": "CA",
                                                  "zip": "94032"]]
        XCTAssertTrue(savedDoc.toDictionary() == docDict)
    }
    
    
    func testSetSwiftArray() throws {
        let array = ["a", "b", "c"]
        
        let doc = createDocument("doc1")
        doc.setValue(array, forKey: "members")
        
        let members = doc.array(forKey: "members")!
        XCTAssertTrue(members === doc.value(forKey: "members") as! ArrayObject)
        XCTAssertEqual(members.count, 3)
        XCTAssertEqual(members.string(at: 0), "a")
        XCTAssertEqual(members.string(at: 1), "b")
        XCTAssertEqual(members.string(at: 2), "c")
        XCTAssertTrue(members.toArray() == ["a", "b", "c"])
        
        // Update with a new array:
        let nuArray = ["d", "e", "f"]
        doc.setValue(nuArray, forKey: "members")
        
        // Check whether the old members array is still accessible:
        XCTAssertEqual(members.count, 3)
        XCTAssertEqual(members.string(at: 0), "a")
        XCTAssertEqual(members.string(at: 1), "b")
        XCTAssertEqual(members.string(at: 2), "c")
        XCTAssertTrue(members.toArray() == ["a", "b", "c"])
        
        // The old members array should be detached:
        let nuMembers = doc.array(forKey: "members")!
        XCTAssertTrue(nuMembers !== members)
        
        // Update nuMembers:
        nuMembers.addValue("g")
        XCTAssertEqual(nuMembers.count, 4)
        XCTAssertEqual(nuMembers.string(at: 3), "g")
        
        // Save:
        let savedDoc = try saveDocument(doc)
        let docDict: [String: Any] = ["members": ["d", "e", "f", "g"]]
        XCTAssertTrue(savedDoc.toDictionary() == docDict)
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
        
        var savedDoc = try saveDocument(doc)
        
        // Update:
        doc = savedDoc.edit()
        shipping = doc.dictionary(forKey: "addresses")!.dictionary(forKey: "shipping")!
        shipping.setValue("94042", forKey: "zip")
        savedDoc = try saveDocument(doc)
        
        let result: [String: Any] = ["addresses":
                                        ["shipping":
                                            ["street": "1 Main street",
                                             "city": "Mountain View",
                                             "state": "CA",
                                             "zip": "94042"]]]
        XCTAssertTrue(savedDoc.toDictionary() == result)
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
        
        var savedDoc = try saveDocument(doc)
        
        // Update:
        doc = savedDoc.edit()
        address1 = doc.array(forKey: "addresses")!.dictionary(at: 0)!
        address1.setValue("2 Main street", forKey: "street")
        address1.setValue("94042", forKey: "zip")
        
        address2 = doc.array(forKey: "addresses")!.dictionary(at: 1)!
        address2.setValue("2 Second street", forKey: "street")
        address2.setValue("94302", forKey: "zip")
        
        savedDoc = try saveDocument(doc)
        let result: [String: Any] = ["addresses": [["street": "2 Main street",
                                                    "city": "Mountain View",
                                                    "state": "CA",
                                                    "zip": "94042"],
                                                   ["street": "2 Second street",
                                                    "city": "Palo Alto",
                                                    "state": "CA",
                                                    "zip": "94302"]]]
        XCTAssertTrue(savedDoc.toDictionary() == result)
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
        
        var savedDoc = try saveDocument(doc)
        
        doc = savedDoc.edit()
        group1 = doc.array(forKey: "groups")!.array(at: 0)!
        group1.setValue("d", at: 0)
        group1.setValue("e", at: 1)
        group1.setValue("f", at: 2)
        
        group2 = doc.array(forKey: "groups")!.array(at: 1)!
        group2.setValue(4, at: 0)
        group2.setValue(5, at: 1)
        group2.setValue(6, at: 2)
        
        savedDoc = try saveDocument(doc)
        let result: [String: Any] = ["groups": [["d", "e", "f"], [4, 5, 6]]]
        XCTAssertTrue(savedDoc.toDictionary() == result)
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
        
        var savedDoc = try saveDocument(doc)
        
        doc = savedDoc.edit()
        member1 = doc.dictionary(forKey: "group1")!.array(forKey: "member")!
        member1.setValue("d", at: 0)
        member1.setValue("e", at: 1)
        member1.setValue("f", at: 2)
        
        member2 = doc.dictionary(forKey: "group2")!.array(forKey: "member")!
        member2.setValue(4, at: 0)
        member2.setValue(5, at: 1)
        member2.setValue(6, at: 2)
        
        savedDoc = try saveDocument(doc)
        let result: [String: Any] = ["group1": ["member": ["d", "e", "f"]],
                                     "group2": ["member": [4, 5, 6]]]
        XCTAssertTrue(savedDoc.toDictionary() == result)
    }
    
    
    func testSetDictionaryToMultipleKeys() throws {
        var doc = createDocument("doc1")
        
        let address = MutableDictionaryObject()
        address.setValue("1 Main street", forKey: "street")
        address.setValue("Mountain View", forKey: "city")
        address.setValue("CA", forKey: "state")
        doc.setValue(address, forKey: "shipping")
        doc.setValue(address, forKey: "billing")
        
        XCTAssert(doc.dictionary(forKey: "shipping")! === address)
        XCTAssert(doc.dictionary(forKey: "billing")! === address)
        
        address.setValue("94042", forKey: "zip")
        XCTAssertEqual(doc.dictionary(forKey: "shipping")!.string(forKey: "zip"), "94042")
        XCTAssertEqual(doc.dictionary(forKey: "billing")!.string(forKey: "zip"), "94042")
        
        var savedDoc = try saveDocument(doc)
        
        doc = savedDoc.edit()
        let shipping = doc.dictionary(forKey: "shipping")!
        let billing = doc.dictionary(forKey: "billing")!
        
        // After save: both shipping and billing address are now independent to each other
        XCTAssert(shipping !== address)
        XCTAssert(billing !== address)
        XCTAssert(shipping !== billing)
        
        shipping.setValue("2 Main street", forKey: "street")
        billing.setValue("3 Main street", forKey: "street")
        
        // Save update:
        savedDoc = try saveDocument(doc)
        XCTAssertEqual(savedDoc.dictionary(forKey: "shipping")!.string(forKey: "street")!, "2 Main street")
        XCTAssertEqual(savedDoc.dictionary(forKey: "billing")!.string(forKey: "street")!, "3 Main street")
    }
    
    
    func testSetArrayToMultipleKeys() throws {
        var doc = createDocument("doc1")
        
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
        
        var savedDoc = try saveDocument(doc)
        
        // After save: both mobile and home are not independent to each other
        doc = savedDoc.edit()
        let mobile = doc.array(forKey: "mobile")!
        let home = doc.array(forKey: "home")!
        XCTAssert(mobile !== phones)
        XCTAssert(home !== phones)
        XCTAssert(mobile !== home)
        
        // Update mobile and home:
        mobile.addValue("650-000-1234")
        home.addValue("650-000-5678")
        
        savedDoc = try saveDocument(doc)
        XCTAssert(savedDoc.array(forKey: "mobile")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003", "650-000-1234"])
        XCTAssert(savedDoc.array(forKey: "home")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003", "650-000-5678"])
    }
    
    
    func failingTestToDictionary() throws {
        // CBLMutableDocument* doc1 = [self createDocument: @"doc1"];
        // [self populateData: doc1];
        // TODO: Should blob be serialized into JSON dictionary?
    }
    
    
    func testCount() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        
        XCTAssertEqual(doc.count, 12)
        XCTAssertEqual(doc.count, doc.toDictionary().count)
        
        let savedDoc = try saveDocument(doc)
        XCTAssertEqual(savedDoc.count, 12)
        XCTAssertEqual(savedDoc.count, savedDoc.toDictionary().count)
    }
    
    
    func testContainsKey() throws {
        let doc = createDocument("doc1")
        let dict: [String: Any] = ["type": "profile",
                                   "name": "Jason",
                                   "age": "30",
                                   "address": ["street": "1 milky way."]]
        doc.setDictionary(dict)
        XCTAssert(doc.contains("type"))
        XCTAssert(doc.contains("name"))
        XCTAssert(doc.contains("age"))
        XCTAssert(doc.contains("address"))
        XCTAssertFalse(doc.contains("weight"))
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
        doc.setDictionary(dict)
        
        try saveDocument(doc)
        
        doc.remove(forKey: "name")
        doc.remove(forKey: "weight")
        doc.remove(forKey: "age")
        doc.remove(forKey: "active")
        doc.dictionary(forKey: "address")?.remove(forKey: "city")
        
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
        doc.remove(forKey: "type")
        doc.remove(forKey: "address")
        XCTAssertNil(doc.value(forKey: "type"))
        XCTAssertNil(doc.value(forKey: "address"))
        XCTAssertFalse(doc.contains("type"))
        XCTAssertFalse(doc.contains("address"))
        XCTAssert(doc.toDictionary() == [:] as [String: Any])
    }
    
    
    func failingTestDeleteNewDocument() throws {
        let doc = createDocument("doc1")
        doc.setValue("Scott Tiger", forKey: "name")
        XCTAssertFalse(doc.isDeleted)
        
        var error: NSError?
        do {
            try self.db.delete(doc)
        } catch let err as NSError {
            error = err
        }
        
        XCTAssertNotNil(error)
        XCTAssertEqual(error!.code, 404)
        XCTAssertFalse(doc.isDeleted)
        XCTAssertEqual(doc.string(forKey: "name")!, "Scott Tiger")
    }
    
    
    func testDeleteDocument() throws {
        let doc = createDocument("doc1")
        doc.setValue("Scott Tiger", forKey: "name")
        XCTAssertFalse(doc.isDeleted)
        
        // Save:
        var savedDoc = try saveDocument(doc)
        
        // Delete:
        try self.db.delete(savedDoc)
        
        savedDoc = self.db.getDocument("doc1")!
        XCTAssertNil(savedDoc.value(forKey: "name"))
        XCTAssert(savedDoc.toDictionary() == [:] as [String: Any])
        XCTAssert(savedDoc.isDeleted)
    }
    
    
    func testDictionaryAfterDeleteDocument() throws {
        let dict = ["address": ["street": "1 Main street",
                                "city": "Mountain View",
                                "state": "CA"]]
        
        let doc = createDocument("doc1", dictionary: dict)
        var savedDoc = try saveDocument(doc)
        
        let address = savedDoc.dictionary(forKey: "address")!
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
        
        try self.db.delete(savedDoc)
        
        savedDoc = self.db.getDocument("doc1")!
        XCTAssertNil(savedDoc.dictionary(forKey: "address"))
        XCTAssert(savedDoc.toDictionary() == [:] as [String: Any])
        
        // The dictionary still has data:
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
    }
    
    
    func testPurgeDocument() throws {
        let doc = createDocument("doc1")
        doc.setValue("profile", forKey: "type")
        doc.setValue("Scott", forKey: "name")
        XCTAssertFalse(doc.isDeleted)
        
        // Purge before save:
        try? self.db.purge(doc)
        
        XCTAssertThrowsError(try self.db.purge(doc), "") { (e) in
            let error = e as NSError
            XCTAssertEqual(error.domain, "CouchbaseLite")
            XCTAssertEqual(error.code, 404)
        }
        
        // Save:
        let savedDoc = try saveDocument(doc)
        
        // Purge:
        try self.db.purge(savedDoc)

    }
    
    
    func testReopenDB() throws {
        let doc = createDocument("doc1")
        doc.setValue("str", forKey: "string")
        
        try saveDocument(doc)
        
        try self.reopenDB()
        
        let savedDoc = self.db.getDocument("doc1")!
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
        
        let savedDoc = db.getDocument("doc1")!
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
        
        let savedDoc = try saveDocument(doc)
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
        
        let savedDoc = try saveDocument(doc)
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
        
        var savedDoc = try saveDocument(doc)
        XCTAssert(savedDoc.value(forKey: "data") as? Blob != nil)
        XCTAssertEqual(savedDoc.blob(forKey: "data")!.content!, content)
        
        try reopenDB()
        
        doc = db.getDocument("doc1")!.edit()
        doc.setValue("bar", forKey: "foo")
        savedDoc = try saveDocument(doc)
        
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
        
        doc.remove(forKey: "key2")
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
}
