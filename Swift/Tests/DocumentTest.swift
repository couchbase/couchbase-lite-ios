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
    
    func populateData(_ doc: Document) {
        doc.set(true, forKey: "true")
        doc.set(false, forKey: "false")
        doc.set("string", forKey: "string")
        doc.set(0, forKey: "zero")
        doc.set(1, forKey: "one")
        doc.set(-1, forKey: "minus_one")
        doc.set(1.1, forKey: "one_dot_one")
        doc.set(dateFromJson(kTestDate), forKey: "date")
        doc.set(NSNull(), forKey: "null")
        
        // Dictionary:
        let dict = DictionaryObject()
        dict.set("1 Main street", forKey: "street")
        dict.set("Mountain View", forKey: "city")
        dict.set("CA", forKey: "state")
        doc.set(dict, forKey: "dict")
        
        // Array:
        let array = ArrayObject()
        array.add("650-123-0001")
        array.add("650-123-0002")
        doc.set(array, forKey: "array")
        
        // Blob
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        doc.set(blob, forKey: "blob")
    }
    
    
    func testCreateDoc() throws {
        let doc1a = Document()
        XCTAssertNotNil(doc1a)
        XCTAssertTrue(doc1a.id.characters.count > 0)
        XCTAssertFalse(doc1a.isDeleted)
        XCTAssertEqual(doc1a.toDictionary().count, 0);
        
        let doc1b = try saveDocument(doc1a)
        XCTAssertTrue(doc1b !== doc1a)
        XCTAssertNotNil(doc1b)
        XCTAssertEqual(doc1a.id, doc1b.id)
    }
    
    
    func testCreateDocWithID() throws {
        let doc1a = Document("doc1")
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
        let doc1a = Document("")
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
        let doc1a = Document(nil)
        XCTAssertNotNil(doc1a)
        XCTAssertTrue(doc1a.id.characters.count > 0)
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
        
        let doc1a = Document("doc1", dictionary: dict)
        XCTAssertNotNil(doc1a)
        XCTAssertTrue(doc1a.id.characters.count > 0)
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
        
        var doc = createDocument("doc1")
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
        
        doc = try saveDocument(doc)
        XCTAssertTrue(doc.toDictionary() ==  nuDict)
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
    
    
    func testGetValueFromExistingEmptyDoc() throws {
        var doc = createDocument("doc1")
        doc = try saveDocument(doc)
        
        XCTAssertEqual(doc.int(forKey: "key"), 0);
        XCTAssertEqual(doc.float(forKey: "key"), 0.0);
        XCTAssertEqual(doc.double(forKey: "key"), 0.0);
        XCTAssertEqual(doc.boolean(forKey: "key"), false);
        XCTAssertNil(doc.blob(forKey: "key"));
        XCTAssertNil(doc.date(forKey: "key"));
        XCTAssertNil(doc.value(forKey: "key"));
        XCTAssertNil(doc.string(forKey: "key"));
        XCTAssertNil(doc.dictionary(forKey: "key"));
        XCTAssertNil(doc.array(forKey: "key"));
        XCTAssertEqual(doc.toDictionary().count, 0);
    }
    
    
    func testSaveThenGetFromAnotherDB() throws {
        let doc1a = createDocument("doc1")
        doc1a.set("Scott Tiger", forKey: "name")
        
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
        doc1a.set("Scott Tiger", forKey: "name")
        
        try saveDocument(doc1a)
        
        let doc1b = db.getDocument("doc1")
        let doc1c = db.getDocument("doc1")
        
        let anotherDb = try openDB(name: db.name)
        let doc1d = anotherDb.getDocument("doc1")
        
        XCTAssertTrue(doc1a !== doc1b)
        XCTAssertTrue(doc1a !== doc1c)
        XCTAssertTrue(doc1a !== doc1d)
        XCTAssertTrue(doc1b !== doc1c)
        XCTAssertTrue(doc1b !== doc1d)
        XCTAssertTrue(doc1c !== doc1d)
        
        XCTAssertTrue(doc1a.toDictionary() == doc1b!.toDictionary())
        XCTAssertTrue(doc1a.toDictionary() == doc1c!.toDictionary())
        XCTAssertTrue(doc1a.toDictionary() == doc1d!.toDictionary())
        
        // Update:
        
        doc1b!.set("Daniel Tiger", forKey: "name")
        try saveDocument(doc1b!)
        
        XCTAssertFalse(doc1b!.toDictionary() == doc1a.toDictionary())
        XCTAssertFalse(doc1b!.toDictionary() == doc1c!.toDictionary())
        XCTAssertFalse(doc1b!.toDictionary() == doc1d!.toDictionary())
        
        try anotherDb.close()
    }
    
    
    func testSetString() throws {
        let doc = createDocument("doc1")
        doc.set("", forKey: "string1")
        doc.set("string", forKey: "string2")
        
        try saveDocument(doc) { (d) in
            XCTAssertEqual(d.string(forKey: "string1"), "")
            XCTAssertEqual(d.string(forKey: "string2"), "string")
        }
        
        // Update:
        
        doc.set("string", forKey: "string1")
        doc.set("", forKey: "string2")
        
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
        doc.set(1, forKey: "number1")
        doc.set(0, forKey: "number2")
        doc.set(-1, forKey: "number3")
        doc.set(1.1, forKey: "number4")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(doc.int(forKey: "number1"), 1)
            XCTAssertEqual(doc.int(forKey: "number2"), 0)
            XCTAssertEqual(doc.int(forKey: "number3"), -1)
            XCTAssertEqual(doc.float(forKey: "number4"), 1.1)
            XCTAssertEqual(doc.double(forKey: "number4"), 1.1)
        })
        
        // Update:
        
        doc.set(0, forKey: "number1")
        doc.set(1, forKey: "number2")
        doc.set(1.1, forKey: "number3")
        doc.set(-1, forKey: "number4")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(doc.int(forKey: "number1"), 0)
            XCTAssertEqual(doc.int(forKey: "number2"), 1)
            XCTAssertEqual(doc.float(forKey: "number3"), 1.1)
            XCTAssertEqual(doc.double(forKey: "number3"), 1.1)
            XCTAssertEqual(doc.int(forKey: "number4"), -1)
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
        doc.set(Int.min, forKey: "min_int")
        doc.set(Int.max, forKey: "max_int")
        doc.set(Float.leastNormalMagnitude, forKey: "min_float")
        doc.set(Float.greatestFiniteMagnitude, forKey: "max_float")
        doc.set(Double.leastNormalMagnitude, forKey: "min_double")
        doc.set(Double.greatestFiniteMagnitude, forKey: "max_double")
        
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
    
    
    func failingTestSetGetFloatNumbers() throws {
        let doc = createDocument("doc1")
        doc.set(1.00, forKey: "number1")
        doc.set(1.49, forKey: "number2")
        doc.set(1.50, forKey: "number3")
        doc.set(1.51, forKey: "number4")
        doc.set(1.99, forKey: "number5")
        
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
        doc.set(true, forKey: "boolean1")
        doc.set(false, forKey: "boolean2")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.boolean(forKey: "boolean1"), true);
            XCTAssertEqual(d.boolean(forKey: "boolean2"), false);
        })
        
        // Update:
        
        doc.set(false, forKey: "boolean1")
        doc.set(true, forKey: "boolean2")
        
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
        XCTAssertTrue(dateStr.characters.count > 0)
        doc.set(date, forKey: "date")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.value(forKey: "date") as! String, dateStr);
            XCTAssertEqual(d.string(forKey: "date"), dateStr);
            XCTAssertEqual(jsonFromDate(d.date(forKey: "date")!), dateStr);
        })
        
        // Update:
        
        let nuDate = Date(timeInterval: 60.0, since: date)
        let nuDateStr = jsonFromDate(nuDate)
        doc.set(nuDate, forKey: "date")
        
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
        doc.set(blob, forKey: "blob")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.blob(forKey: "blob")!.properties == blob.properties)
            XCTAssertEqual(d.blob(forKey: "blob")!.content, content)
        })
        
        // Update:
        
        let nuContent = "1234567890".data(using: .utf8)!
        let nuBlob = Blob(contentType: "text/plain", data: nuContent)
        doc.set(nuBlob, forKey: "blob")
        
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
        var dict = DictionaryObject()
        dict.set("1 Main street", forKey: "street")
        doc.set(dict, forKey: "dict")
        
        XCTAssertTrue(doc.value(forKey: "dict") as! DictionaryObject === dict)
        doc = try saveDocument(doc)
        
        XCTAssertTrue(doc.value(forKey: "dict") as! DictionaryObject !== dict)
        XCTAssertTrue(doc.value(forKey: "dict") as! DictionaryObject === doc.dictionary(forKey: "dict")!)
        
        // Update:
        
        dict = doc.dictionary(forKey: "dict")!
        dict.set("Mountain View", forKey: "city")
        
        XCTAssertTrue(doc.value(forKey: "dict") as! DictionaryObject === doc.dictionary(forKey: "dict")!)
        let nsDict: [String: Any] = ["street": "1 Main street", "city": "Mountain View"]
        XCTAssertTrue(doc.dictionary(forKey: "dict")!.toDictionary() == nsDict)
        
        doc = try saveDocument(doc)
        
        XCTAssertTrue(doc.value(forKey: "dict") as! DictionaryObject !== dict)
        XCTAssertTrue(doc.value(forKey: "dict") as! DictionaryObject === doc.dictionary(forKey: "dict")!)
        XCTAssertTrue(doc.dictionary(forKey: "dict")!.toDictionary() == nsDict)
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
        var array = ArrayObject()
        array.add("item1")
        array.add("item2")
        array.add("item3")
        doc.set(array, forKey: "array")
        
        XCTAssertTrue(doc.value(forKey: "array") as! ArrayObject === array)
        XCTAssertTrue(doc.array(forKey: "array")! === array)
        XCTAssertTrue(doc.array(forKey: "array")!.toArray() == ["item1", "item2", "item3"])
        
        doc = try saveDocument(doc)
        
        XCTAssertTrue(doc.value(forKey: "array") as! ArrayObject !== array)
        XCTAssertTrue(doc.value(forKey: "array") as! ArrayObject === doc.array(forKey: "array")!)
        XCTAssertTrue(doc.array(forKey: "array")!.toArray() == ["item1", "item2", "item3"])
     
        // Update:
        
        array = doc.array(forKey: "array")!
        array.add("item4")
        array.add("item5")
        
        doc = try saveDocument(doc)
        
        XCTAssertTrue(doc.value(forKey: "array") as! ArrayObject !== array)
        XCTAssertTrue(doc.value(forKey: "array") as! ArrayObject === doc.array(forKey: "array")!)
        XCTAssertTrue(doc.array(forKey: "array")!.toArray() == ["item1", "item2", "item3", "item4", "item5"])
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
        doc.set(NSNull(), forKey: "null")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.value(forKey: "null") as! NSNull, NSNull())
            XCTAssertEqual(d.count, 1)
        })
    }
    
    
    func testSetSwiftDictionary() throws {
        let dict = ["street": "1 Main street",
                    "city": "Mountain View",
                    "state": "CA"]
        
        var doc = createDocument("doc1")
        doc.set(dict, forKey: "address")
        
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
        doc.set(nuDict, forKey: "address")
        
        // Check whether the old address dictionary is still accessible:
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
        XCTAssertTrue(address.toDictionary() == dict)
        
        // The old address dictionary should be detached:
        let nuAddress = doc.dictionary(forKey: "address")!
        XCTAssertTrue(address !== nuAddress)
        
        // Update nuAddress:
        nuAddress.set("94032", forKey: "zip")
        XCTAssertEqual(nuAddress.string(forKey: "zip"), "94032")
        XCTAssertNil(address.string(forKey: "zip"))
        
        // Save:
        doc = try saveDocument(doc)
        
        let docDict: [String: Any] = ["address": ["street": "1 Second street",
                                                  "city": "Palo Alto",
                                                  "state": "CA",
                                                  "zip": "94032"]]
        XCTAssertTrue(doc.toDictionary() == docDict)
    }
    
    
    func testSetSwiftArray() throws {
        let array = ["a", "b", "c"]
        
        var doc = createDocument("doc1")
        doc.set(array, forKey: "members")
        
        let members = doc.array(forKey: "members")!
        XCTAssertTrue(members === doc.value(forKey: "members") as! ArrayObject)
        XCTAssertEqual(members.count, 3)
        XCTAssertEqual(members.string(at: 0), "a")
        XCTAssertEqual(members.string(at: 1), "b")
        XCTAssertEqual(members.string(at: 2), "c")
        XCTAssertTrue(members.toArray() == ["a", "b", "c"])
        
        // Update with a new array:
        let nuArray = ["d", "e", "f"]
        doc.set(nuArray, forKey: "members")
        
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
        nuMembers.add("g")
        XCTAssertEqual(nuMembers.count, 4)
        XCTAssertEqual(nuMembers.string(at: 3), "g")
        
        // Save:
        doc = try saveDocument(doc)
        
        let docDict: [String: Any] = ["members": ["d", "e", "f", "g"]]
        XCTAssertTrue(doc.toDictionary() == docDict)
    }
    
    
    func testUpdateNestedDictionary() throws {
        var doc = createDocument("doc1")
        let addresses = DictionaryObject()
        doc.set(addresses, forKey: "addresses")
        
        var shipping = DictionaryObject()
        shipping.set("1 Main street", forKey: "street")
        shipping.set("Mountain View", forKey: "city")
        shipping.set("CA", forKey: "state")
        addresses.set(shipping, forKey: "shipping")
        
        doc = try saveDocument(doc)
        
        shipping = doc.dictionary(forKey: "addresses")!.dictionary(forKey: "shipping")!
        shipping.set("94042", forKey: "zip")
        
        doc = try saveDocument(doc)
        
        let result: [String: Any] = ["addresses":
                                        ["shipping":
                                            ["street": "1 Main street",
                                             "city": "Mountain View",
                                             "state": "CA",
                                             "zip": "94042"]]]
        XCTAssertTrue(doc.toDictionary() == result)
    }
    
    
    func testUpdateDictionaryInArray() throws {
        var doc = createDocument("doc1")
        let addresses = ArrayObject()
        doc.set(addresses, forKey: "addresses")
        
        var address1 = DictionaryObject()
        address1.set("1 Main street", forKey: "street")
        address1.set("Mountain View", forKey: "city")
        address1.set("CA", forKey: "state")
        addresses.add(address1)
        
        var address2 = DictionaryObject()
        address2.set("1 Second street", forKey: "street")
        address2.set("Palo Alto", forKey: "city")
        address2.set("CA", forKey: "state")
        addresses.add(address2)
        
        doc = try saveDocument(doc)
        
        address1 = doc.array(forKey: "addresses")!.dictionary(at: 0)!
        address1.set("2 Main street", forKey: "street")
        address1.set("94042", forKey: "zip")
        
        address2 = doc.array(forKey: "addresses")!.dictionary(at: 1)!
        address2.set("2 Second street", forKey: "street")
        address2.set("94302", forKey: "zip")
        
        doc = try saveDocument(doc)
        
        let result: [String: Any] = ["addresses": [["street": "2 Main street",
                                                    "city": "Mountain View",
                                                    "state": "CA",
                                                    "zip": "94042"],
                                                   ["street": "2 Second street",
                                                    "city": "Palo Alto",
                                                    "state": "CA",
                                                    "zip": "94302"]]]
        XCTAssertTrue(doc.toDictionary() == result)
    }
    
    
    func testUpdateNestedArray() throws {
        var doc = createDocument("doc1")
        let groups = ArrayObject()
        doc.set(groups, forKey: "groups")
        
        var group1 = ArrayObject()
        group1.add("a")
        group1.add("b")
        group1.add("c")
        groups.add(group1)
        
        var group2 = ArrayObject()
        group2.add(1)
        group2.add(2)
        group2.add(3)
        groups.add(group2)
        
        doc = try saveDocument(doc)
        
        group1 = doc.array(forKey: "groups")!.array(at: 0)!
        group1.set("d", at: 0)
        group1.set("e", at: 1)
        group1.set("f", at: 2)
        
        group2 = doc.array(forKey: "groups")!.array(at: 1)!
        group2.set(4, at: 0)
        group2.set(5, at: 1)
        group2.set(6, at: 2)
        
        doc = try saveDocument(doc)
        
        let result: [String: Any] = ["groups": [["d", "e", "f"], [4, 5, 6]]]
        XCTAssertTrue(doc.toDictionary() == result)
    }
    
    
    func testUpdateArrayInDictionary() throws {
        var doc = createDocument("doc1")
        
        let group1 = DictionaryObject()
        var member1 = ArrayObject()
        member1.add("a")
        member1.add("b")
        member1.add("c")
        group1.set(member1, forKey: "member")
        doc.set(group1, forKey: "group1")
        
        let group2 = DictionaryObject()
        var member2 = ArrayObject()
        member2.add(1)
        member2.add(2)
        member2.add(3)
        group2.set(member2, forKey: "member")
        doc.set(group2, forKey: "group2")
        
        doc = try saveDocument(doc)
        
        member1 = doc.dictionary(forKey: "group1")!.array(forKey: "member")!
        member1.set("d", at: 0)
        member1.set("e", at: 1)
        member1.set("f", at: 2)
        
        member2 = doc.dictionary(forKey: "group2")!.array(forKey: "member")!
        member2.set(4, at: 0)
        member2.set(5, at: 1)
        member2.set(6, at: 2)
        
        doc = try saveDocument(doc)
        
        let result: [String: Any] = ["group1": ["member": ["d", "e", "f"]],
                                     "group2": ["member": [4, 5, 6]]]
        XCTAssertTrue(doc.toDictionary() == result)
    }
    
    
    func testSetDictionaryToMultipleKeys() throws {
        var doc = createDocument("doc1")
        
        let address = DictionaryObject()
        address.set("1 Main street", forKey: "street")
        address.set("Mountain View", forKey: "city")
        address.set("CA", forKey: "state")
        doc.set(address, forKey: "shipping")
        doc.set(address, forKey: "billing")
        
        XCTAssert(doc.dictionary(forKey: "shipping")! === address)
        XCTAssert(doc.dictionary(forKey: "billing")! === address)
        
        address.set("94042", forKey: "zip")
        XCTAssertEqual(doc.dictionary(forKey: "shipping")!.string(forKey: "zip"), "94042")
        XCTAssertEqual(doc.dictionary(forKey: "billing")!.string(forKey: "zip"), "94042")
        
        doc = try saveDocument(doc)
        
        let shipping = doc.dictionary(forKey: "shipping")!
        let billing = doc.dictionary(forKey: "billing")!
        
        // After save: both shipping and billing address are now independent to each other
        XCTAssert(shipping !== address)
        XCTAssert(billing !== address)
        XCTAssert(shipping !== billing)
        
        shipping.set("2 Main street", forKey: "street")
        billing.set("3 Main street", forKey: "street")
        
        // Save update:
        doc = try saveDocument(doc)
        
        XCTAssertEqual(doc.dictionary(forKey: "shipping")!.string(forKey: "street")!, "2 Main street")
        XCTAssertEqual(doc.dictionary(forKey: "billing")!.string(forKey: "street")!, "3 Main street")
    }
    
    
    func testSetArrayToMultipleKeys() throws {
        var doc = createDocument("doc1")
        
        let phones = ArrayObject()
        phones.add("650-000-0001")
        phones.add("650-000-0002")
        
        doc.set(phones, forKey: "mobile")
        doc.set(phones, forKey: "home")
        
        XCTAssert(doc.array(forKey: "mobile")! === phones)
        XCTAssert(doc.array(forKey: "home")! === phones)
        
        // Update phones: both mobile and home should get the update
        phones.add("650-000-0003")
        XCTAssert(doc.array(forKey: "mobile")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003"])
        XCTAssert(doc.array(forKey: "home")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003"])
        
        doc = try saveDocument(doc)
        
        // After save: both mobile and home are not independent to each other
        let mobile = doc.array(forKey: "mobile")!
        let home = doc.array(forKey: "home")!
        XCTAssert(mobile !== phones)
        XCTAssert(home !== phones)
        XCTAssert(mobile !== home)
        
        // Update mobile and home:
        mobile.add("650-000-1234")
        home.add("650-000-5678")
        
        doc = try saveDocument(doc)
        
        XCTAssert(doc.array(forKey: "mobile")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003", "650-000-1234"])
        XCTAssert(doc.array(forKey: "home")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003", "650-000-5678"])
    }
    
    
    func failingTestToDictionary() throws {
        // CBLDocument* doc1 = [self createDocument: @"doc1"];
        // [self populateData: doc1];
        // TODO: Should blob be serialized into JSON dictionary?
    }
    
    
    func testCount() throws {
        var doc = createDocument("doc1")
        populateData(doc)
        
        XCTAssertEqual(doc.count, 12)
        XCTAssertEqual(doc.count, doc.toDictionary().count)
        
        doc = try saveDocument(doc)
        
        XCTAssertEqual(doc.count, 12)
        XCTAssertEqual(doc.count, doc.toDictionary().count)
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
        doc.set("Scott Tiger", forKey: "name")
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
        doc.set("Scott Tiger", forKey: "name")
        XCTAssertFalse(doc.isDeleted)
        
        // Save:
        try saveDocument(doc)
        
        // Delete:
        try self.db.delete(doc)
        XCTAssertNil(doc.value(forKey: "name"))
        XCTAssert(doc.toDictionary() == [:] as [String: Any])
        XCTAssert(doc.isDeleted)
    }
    
    
    func testDictionaryAfterDeleteDocument() throws {
        let dict = ["address": ["street": "1 Main street",
                                "city": "Mountain View",
                                "state": "CA"]]
        
        let doc = createDocument("doc1", dictionary: dict)
        try saveDocument(doc)
        
        let address = doc.dictionary(forKey: "address")!
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
        
        try self.db.delete(doc)
        XCTAssertNil(doc.dictionary(forKey: "address"))
        XCTAssert(doc.toDictionary() == [:] as [String: Any])
        
        // The dictionary still has data but is detached:
        XCTAssertEqual(address.string(forKey: "street"), "1 Main street")
        XCTAssertEqual(address.string(forKey: "city"), "Mountain View")
        XCTAssertEqual(address.string(forKey: "state"), "CA")
        
        // Make changes to the dictionary shouldn't affect the document.
        address.set("94042", forKey: "zip")
        XCTAssertNil(doc.dictionary(forKey: "address"))
        XCTAssert(doc.toDictionary() == [:] as [String: Any])
    }
    
    
    func testPurgeDocument() throws {
        let doc = createDocument("doc1")
        doc.set("profile", forKey: "type")
        doc.set("Scott", forKey: "name")
        XCTAssertFalse(doc.isDeleted)
        
        // Purge before save:
        try? self.db.purge(doc)
        XCTAssertEqual(doc.string(forKey: "type"), "profile")
        XCTAssertEqual(doc.string(forKey: "name"), "Scott")
        
        // Save:
        try saveDocument(doc)
        
        // Purge:
        try self.db.purge(doc)
        XCTAssertFalse(doc.isDeleted)
    }
    
    
    func testReopenDB() throws {
        var doc = createDocument("doc1")
        doc.set("str", forKey: "string")
        
        try saveDocument(doc)
        
        try self.reopenDB()
        
        doc = self.db.getDocument("doc1")!
        XCTAssertEqual(doc.string(forKey: "string"), "str")
        XCTAssert(doc.toDictionary() == ["string": "str"] as [String: Any])
    }
    
    
    func testBlob() throws {
        let content = kTestBlob.data(using: String.Encoding.utf8)!
        var blob = Blob(contentType: "text/plain", data: content)
        var doc = createDocument("doc1")
        doc.set(blob, forKey: "data")
        doc.set("Jim", forKey: "name")
        
        try saveDocument(doc)
        try reopenDB()
        
        doc = db.getDocument("doc1")!
        XCTAssertEqual(doc.string(forKey: "name"), "Jim")
        XCTAssert(doc.value(forKey: "data") as? Blob != nil)
        
        blob = doc.blob(forKey: "data")!
        XCTAssertEqual(blob.contentType, "text/plain")
        XCTAssertEqual(blob.length, UInt64(kTestBlob.characters.count))
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
        
        var doc = createDocument("doc1")
        doc.set(blob, forKey: "data")
        
        doc = try saveDocument(doc)
        
        blob = doc.blob(forKey: "data")!
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
        var doc = createDocument("doc1")
        doc.set(blob, forKey: "data")
        
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
        
        doc = try saveDocument(doc)
        
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
    }
    
    
    func testReadingExistingBlob() throws {
        let content = kTestBlob.data(using: String.Encoding.utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        var doc = createDocument("doc1")
        doc.set(blob, forKey: "data")
        doc.set("Jim", forKey: "name")
        
        try saveDocument(doc)
        
        XCTAssert(doc.value(forKey: "data") as? Blob != nil)
        XCTAssertEqual(doc.blob(forKey: "data")!.content!, content)
        
        try reopenDB()
        
        doc = db.getDocument("doc1")!
        doc.set("bar", forKey: "foo")
        try saveDocument(doc)
        
        XCTAssert(doc.value(forKey: "data") as? Blob != nil)
        XCTAssertEqual(doc.blob(forKey: "data")!.content!, content)
    }
    
    
    func testEnumeratingKeys() throws {
        let doc = createDocument("doc1")
        for i in 0...19 {
            doc.set(i, forKey: "key\(i)")
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
        doc.set(20, forKey: "key20")
        doc.set(21, forKey: "key21")
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
