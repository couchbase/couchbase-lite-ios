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
            XCTAssertEqual(d.getInt("key"), 0);
            XCTAssertEqual(d.getFloat("key"), 0.0);
            XCTAssertEqual(d.getDouble("key"), 0.0);
            XCTAssertEqual(d.getBoolean("key"), false);
            XCTAssertNil(d.getBlob("key"));
            XCTAssertNil(d.getDate("key"));
            XCTAssertNil(d.getValue("key"));
            XCTAssertNil(d.getString("key"));
            XCTAssertNil(d.getDictionary("key"));
            XCTAssertNil(d.getArray("key"));
            XCTAssertEqual(d.toDictionary().count, 0);
        }
    }
    
    
    func testGetValueFromExistingEmptyDoc() throws {
        var doc = createDocument("doc1")
        doc = try saveDocument(doc)
        
        XCTAssertEqual(doc.getInt("key"), 0);
        XCTAssertEqual(doc.getFloat("key"), 0.0);
        XCTAssertEqual(doc.getDouble("key"), 0.0);
        XCTAssertEqual(doc.getBoolean("key"), false);
        XCTAssertNil(doc.getBlob("key"));
        XCTAssertNil(doc.getDate("key"));
        XCTAssertNil(doc.getValue("key"));
        XCTAssertNil(doc.getString("key"));
        XCTAssertNil(doc.getDictionary("key"));
        XCTAssertNil(doc.getArray("key"));
        XCTAssertEqual(doc.toDictionary().count, 0);
    }
    
    
    func testSaveThenGetFromAnotherDB() throws {
        let doc1a = createDocument("doc1")
        doc1a.set("Scott Tiger", forKey: "name")
        
        try saveDocument(doc1a)
        
        let anotherDb = try createDB()
        
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
        
        let anotherDb = try createDB()
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
            XCTAssertEqual(d.getString("string1"), "")
            XCTAssertEqual(d.getString("string2"), "string")
        }
        
        // Update:
        
        doc.set("string", forKey: "string1")
        doc.set("", forKey: "string2")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.getString("string1"), "string")
            XCTAssertEqual(d.getString("string2"), "")
        })
    }
    
    
    func testGetString() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.getString("null"))
            XCTAssertNil(d.getString("true"))
            XCTAssertNil(d.getString("false"))
            XCTAssertEqual(d.getString("string"), "string");
            XCTAssertNil(d.getString("zero"))
            XCTAssertNil(d.getString("one"))
            XCTAssertNil(d.getString("minus_one"))
            XCTAssertNil(d.getString("one_dot_one"))
            XCTAssertEqual(d.getString("date"), kTestDate);
            XCTAssertNil(d.getString("dict"))
            XCTAssertNil(d.getString("array"))
            XCTAssertNil(d.getString("blob"))
            XCTAssertNil(d.getString("non_existing_key"))
        })
    }
    
    
    func testSetNumber() throws {
        let doc = createDocument("doc1")
        doc.set(1, forKey: "number1")
        doc.set(0, forKey: "number2")
        doc.set(-1, forKey: "number3")
        doc.set(1.1, forKey: "number4")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(doc.getInt("number1"), 1)
            XCTAssertEqual(doc.getInt("number2"), 0)
            XCTAssertEqual(doc.getInt("number3"), -1)
            XCTAssertEqual(doc.getFloat("number4"), 1.1)
            XCTAssertEqual(doc.getDouble("number4"), 1.1)
        })
        
        // Update:
        
        doc.set(0, forKey: "number1")
        doc.set(1, forKey: "number2")
        doc.set(1.1, forKey: "number3")
        doc.set(-1, forKey: "number4")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(doc.getInt("number1"), 0)
            XCTAssertEqual(doc.getInt("number2"), 1)
            XCTAssertEqual(doc.getFloat("number3"), 1.1)
            XCTAssertEqual(doc.getDouble("number3"), 1.1)
            XCTAssertEqual(doc.getInt("number4"), -1)
        })
    }
    
    
    func testGetInteger() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.getInt("null"), 0)
            XCTAssertEqual(d.getInt("true"), 1)
            XCTAssertEqual(d.getInt("false"), 0)
            XCTAssertEqual(d.getInt("string"), 0);
            XCTAssertEqual(d.getInt("zero"),0)
            XCTAssertEqual(d.getInt("one"), 1)
            XCTAssertEqual(d.getInt("minus_one"), -1)
            XCTAssertEqual(d.getInt("one_dot_one"), 1)
            XCTAssertEqual(d.getInt("date"), 0)
            XCTAssertEqual(d.getInt("dict"), 0)
            XCTAssertEqual(d.getInt("array"), 0)
            XCTAssertEqual(d.getInt("blob"), 0)
            XCTAssertEqual(d.getInt("non_existing_key"), 0)
        })
    }

    
    func testGetFloat() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.getFloat("null"), 0.0)
            XCTAssertEqual(d.getFloat("true"), 1.0)
            XCTAssertEqual(d.getFloat("false"), 0.0)
            XCTAssertEqual(d.getFloat("string"), 0.0);
            XCTAssertEqual(d.getFloat("zero"),0.0)
            XCTAssertEqual(d.getFloat("one"), 1.0)
            XCTAssertEqual(d.getFloat("minus_one"), -1.0)
            XCTAssertEqual(d.getFloat("one_dot_one"), 1.1)
            XCTAssertEqual(d.getFloat("date"), 0.0)
            XCTAssertEqual(d.getFloat("dict"), 0.0)
            XCTAssertEqual(d.getFloat("array"), 0.0)
            XCTAssertEqual(d.getFloat("blob"), 0.0)
            XCTAssertEqual(d.getFloat("non_existing_key"), 0.0)
        })
    }
    
    
    func testGetDouble() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.getDouble("null"), 0.0)
            XCTAssertEqual(d.getDouble("true"), 1.0)
            XCTAssertEqual(d.getDouble("false"), 0.0)
            XCTAssertEqual(d.getDouble("string"), 0.0);
            XCTAssertEqual(d.getDouble("zero"),0.0)
            XCTAssertEqual(d.getDouble("one"), 1.0)
            XCTAssertEqual(d.getDouble("minus_one"), -1.0)
            XCTAssertEqual(d.getDouble("one_dot_one"), 1.1)
            XCTAssertEqual(d.getDouble("date"), 0.0)
            XCTAssertEqual(d.getDouble("dict"), 0.0)
            XCTAssertEqual(d.getDouble("array"), 0.0)
            XCTAssertEqual(d.getDouble("blob"), 0.0)
            XCTAssertEqual(d.getDouble("non_existing_key"), 0.0)
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
            XCTAssertEqual(d.getInt("min_int"), Int.min);
            XCTAssertEqual(d.getInt("max_int"), Int.max);
            XCTAssertEqual(d.getValue("min_int") as! Int, Int.min);
            XCTAssertEqual(d.getValue("max_int") as! Int, Int.max);
            
            XCTAssertEqual(d.getFloat("min_float"), Float.leastNormalMagnitude);
            XCTAssertEqual(d.getFloat("max_float"), Float.greatestFiniteMagnitude);
            XCTAssertEqual(d.getValue("min_float") as! Float, Float.leastNormalMagnitude);
            XCTAssertEqual(d.getValue("max_float") as! Float, Float.greatestFiniteMagnitude);
            
            XCTAssertEqual(d.getDouble("min_double"), Double.leastNormalMagnitude);
            XCTAssertEqual(d.getDouble("max_double"), Double.greatestFiniteMagnitude);
            XCTAssertEqual(d.getValue("min_double") as! Double, Double.leastNormalMagnitude);
            XCTAssertEqual(d.getValue("max_double") as! Double, Double.greatestFiniteMagnitude);
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
            XCTAssertEqual(d.getInt("number1"), 1);
            XCTAssertEqual(d.getFloat("number1"), 1.00);
            XCTAssertEqual(d.getDouble("number1"), 1.00);
            
            XCTAssertEqual(d.getInt("number2"), 1);
            XCTAssertEqual(d.getFloat("number2"), 1.49);
            XCTAssertEqual(d.getDouble("number2"), 1.49);
            
            XCTAssertEqual(d.getInt("number3"), 1);
            XCTAssertEqual(d.getFloat("number3"), 1.50);
            XCTAssertEqual(d.getDouble("number3"), 1.50);
            
            XCTAssertEqual(d.getInt("number4"), 1);
            XCTAssertEqual(d.getFloat("number4"), 1.51);
            XCTAssertEqual(d.getDouble("number4"), 1.51);
            
            XCTAssertEqual(d.getInt("number5"), 1);
            XCTAssertEqual(d.getFloat("number5"), 1.99);
            XCTAssertEqual(d.getDouble("number5"), 1.99);
        })
    }
    
    
    func testSetBoolean() throws {
        let doc = createDocument("doc1")
        doc.set(true, forKey: "boolean1")
        doc.set(false, forKey: "boolean2")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.getBoolean("boolean1"), true);
            XCTAssertEqual(d.getBoolean("boolean2"), false);
        })
        
        // Update:
        
        doc.set(false, forKey: "boolean1")
        doc.set(true, forKey: "boolean2")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.getBoolean("boolean1"), false);
            XCTAssertEqual(d.getBoolean("boolean2"), true);
        })
    }
    
    
    func testGetBoolean() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.getBoolean("null"), false)
            XCTAssertEqual(d.getBoolean("true"), true)
            XCTAssertEqual(d.getBoolean("false"),false)
            XCTAssertEqual(d.getBoolean("string"), true);
            XCTAssertEqual(d.getBoolean("zero"), false)
            XCTAssertEqual(d.getBoolean("one"), true)
            XCTAssertEqual(d.getBoolean("minus_one"), true)
            XCTAssertEqual(d.getBoolean("one_dot_one"), true)
            XCTAssertEqual(d.getBoolean("date"), true)
            XCTAssertEqual(d.getBoolean("dict"), true)
            XCTAssertEqual(d.getBoolean("array"), true)
            XCTAssertEqual(d.getBoolean("blob"), true)
            XCTAssertEqual(d.getBoolean("non_existing_key"), false)
        })
    }
    
    
    func testSetDate() throws {
        let doc = createDocument("doc1")
        let date = Date()
        let dateStr = jsonFromDate(date)
        XCTAssertTrue(dateStr.characters.count > 0)
        doc.set(date, forKey: "date")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.getValue("date") as! String, dateStr);
            XCTAssertEqual(d.getString("date"), dateStr);
            XCTAssertEqual(jsonFromDate(d.getDate("date")!), dateStr);
        })
        
        // Update:
        
        let nuDate = Date(timeInterval: 60.0, since: date)
        let nuDateStr = jsonFromDate(nuDate)
        doc.set(nuDate, forKey: "date")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.getValue("date") as! String, nuDateStr);
            XCTAssertEqual(d.getString("date"), nuDateStr);
            XCTAssertEqual(jsonFromDate(d.getDate("date")!), nuDateStr);
        })
    }
    
    
    func testGetDate() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.getDate("null"))
            XCTAssertNil(d.getDate("true"))
            XCTAssertNil(d.getDate("false"))
            XCTAssertNil(d.getDate("string"));
            XCTAssertNil(d.getDate("zero"))
            XCTAssertNil(d.getDate("one"))
            XCTAssertNil(d.getDate("minus_one"))
            XCTAssertNil(d.getDate("one_dot_one"))
            XCTAssertEqual(jsonFromDate(d.getDate("date")!), kTestDate);
            XCTAssertNil(d.getDate("dict"))
            XCTAssertNil(d.getDate("array"))
            XCTAssertNil(d.getDate("blob"))
            XCTAssertNil(d.getDate("non_existing_key"))
        })
    }
    
    
    func testSetBlob() throws {
        let doc = createDocument("doc1")
        let content = kTestBlob.data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        doc.set(blob, forKey: "blob")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.getBlob("blob")!.properties == blob.properties)
            XCTAssertEqual(d.getBlob("blob")!.content, content)
        })
        
        // Update:
        
        let nuContent = "1234567890".data(using: .utf8)!
        let nuBlob = Blob(contentType: "text/plain", data: nuContent)
        doc.set(nuBlob, forKey: "blob")
        
        try saveDocument(doc, eval: { (d) in
            XCTAssertTrue(d.getBlob("blob")!.properties == nuBlob.properties)
            XCTAssertEqual(d.getBlob("blob")!.content, nuContent)
        })
    }
    
    
    func testGetBlob() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.getBlob("null"))
            XCTAssertNil(d.getBlob("true"))
            XCTAssertNil(d.getBlob("false"))
            XCTAssertNil(d.getBlob("string"));
            XCTAssertNil(d.getBlob("zero"))
            XCTAssertNil(d.getBlob("one"))
            XCTAssertNil(d.getBlob("minus_one"))
            XCTAssertNil(d.getBlob("one_dot_one"))
            XCTAssertNil(d.getBlob("date"))
            XCTAssertNil(d.getBlob("dict"))
            XCTAssertNil(d.getBlob("array"))
            XCTAssertEqual(d.getBlob("blob")!.content, kTestBlob.data(using: .utf8))
            XCTAssertNil(d.getBlob("non_existing_key"))
        })
    }
    
    
    func testSetDictionary() throws {
        var doc = createDocument("doc1")
        var dict = DictionaryObject()
        dict.set("1 Main street", forKey: "street")
        doc.set(dict, forKey: "dict")
        
        XCTAssertTrue(doc.getValue("dict") as! DictionaryObject === dict)
        doc = try saveDocument(doc)
        
        XCTAssertTrue(doc.getValue("dict") as! DictionaryObject !== dict)
        XCTAssertTrue(doc.getValue("dict") as! DictionaryObject === doc.getDictionary("dict")!)
        
        // Update:
        
        dict = doc.getDictionary("dict")!
        dict.set("Mountain View", forKey: "city")
        
        XCTAssertTrue(doc.getValue("dict") as! DictionaryObject === doc.getDictionary("dict")!)
        let nsDict: [String: Any] = ["street": "1 Main street", "city": "Mountain View"]
        XCTAssertTrue(doc.getDictionary("dict")!.toDictionary() == nsDict)
        
        doc = try saveDocument(doc)
        
        XCTAssertTrue(doc.getValue("dict") as! DictionaryObject !== dict)
        XCTAssertTrue(doc.getValue("dict") as! DictionaryObject === doc.getDictionary("dict")!)
        XCTAssertTrue(doc.getDictionary("dict")!.toDictionary() == nsDict)
    }
    
    
    func testGetDictionary() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.getDictionary("null"))
            XCTAssertNil(d.getDictionary("true"))
            XCTAssertNil(d.getDictionary("false"))
            XCTAssertNil(d.getDictionary("string"));
            XCTAssertNil(d.getDictionary("zero"))
            XCTAssertNil(d.getDictionary("one"))
            XCTAssertNil(d.getDictionary("minus_one"))
            XCTAssertNil(d.getDictionary("one_dot_one"))
            XCTAssertNil(d.getDictionary("date"))
            let dict: [String: Any] = ["street": "1 Main street", "city": "Mountain View", "state": "CA"]
            XCTAssertTrue(doc.getDictionary("dict")!.toDictionary() == dict)
            XCTAssertNil(d.getDictionary("array"))
            XCTAssertNil(d.getDictionary("blob"))
            XCTAssertNil(d.getDictionary("non_existing_key"))
        })
    }
    
    
    func testSetArray() throws {
        var doc = createDocument("doc1")
        var array = ArrayObject()
        array.add("item1")
        array.add("item2")
        array.add("item3")
        doc.set(array, forKey: "array")
        
        XCTAssertTrue(doc.getValue("array") as! ArrayObject === array)
        XCTAssertTrue(doc.getArray("array")! === array)
        XCTAssertTrue(doc.getArray("array")!.toArray() == ["item1", "item2", "item3"])
        
        doc = try saveDocument(doc)
        
        XCTAssertTrue(doc.getValue("array") as! ArrayObject !== array)
        XCTAssertTrue(doc.getValue("array") as! ArrayObject === doc.getArray("array")!)
        XCTAssertTrue(doc.getArray("array")!.toArray() == ["item1", "item2", "item3"])
     
        // Update:
        
        array = doc.getArray("array")!
        array.add("item4")
        array.add("item5")
        
        doc = try saveDocument(doc)
        
        XCTAssertTrue(doc.getValue("array") as! ArrayObject !== array)
        XCTAssertTrue(doc.getValue("array") as! ArrayObject === doc.getArray("array")!)
        XCTAssertTrue(doc.getArray("array")!.toArray() == ["item1", "item2", "item3", "item4", "item5"])
    }
    
    
    func testGetArray() throws {
        let doc = createDocument("doc1")
        populateData(doc)
        try saveDocument(doc, eval: { (d) in
            XCTAssertNil(d.getArray("null"))
            XCTAssertNil(d.getArray("true"))
            XCTAssertNil(d.getArray("false"))
            XCTAssertNil(d.getArray("string"));
            XCTAssertNil(d.getArray("zero"))
            XCTAssertNil(d.getArray("one"))
            XCTAssertNil(d.getArray("minus_one"))
            XCTAssertNil(d.getArray("one_dot_one"))
            XCTAssertNil(d.getArray("date"))
            XCTAssertNil(d.getArray("dict"))
            XCTAssertTrue(d.getArray("array")!.toArray() == ["650-123-0001", "650-123-0002"])
            XCTAssertNil(d.getArray("blob"))
            XCTAssertNil(d.getArray("non_existing_key"))
        })
    }
    
    
    func testSetNSNull() throws {
        let doc = createDocument("doc1")
        doc.set(NSNull(), forKey: "null")
        try saveDocument(doc, eval: { (d) in
            XCTAssertEqual(d.getValue("null") as! NSNull, NSNull())
            XCTAssertEqual(d.count, 1)
        })
    }
    
    
    func testSetSwiftDictionary() throws {
        let dict = ["street": "1 Main street",
                    "city": "Mountain View",
                    "state": "CA"]
        
        var doc = createDocument("doc1")
        doc.set(dict, forKey: "address")
        
        let address = doc.getDictionary("address")!
        XCTAssertTrue(address === doc.getValue("address") as! DictionaryObject)
        XCTAssertEqual(address.getString("street"), "1 Main street")
        XCTAssertEqual(address.getString("city"), "Mountain View")
        XCTAssertEqual(address.getString("state"), "CA")
        XCTAssertTrue(address.toDictionary() == dict)
        
        // Update with a new dictionary:
        let nuDict = ["street": "1 Second street",
                      "city": "Palo Alto",
                      "state": "CA"]
        doc.set(nuDict, forKey: "address")
        
        // Check whether the old address dictionary is still accessible:
        XCTAssertEqual(address.getString("street"), "1 Main street")
        XCTAssertEqual(address.getString("city"), "Mountain View")
        XCTAssertEqual(address.getString("state"), "CA")
        XCTAssertTrue(address.toDictionary() == dict)
        
        // The old address dictionary should be detached:
        let nuAddress = doc.getDictionary("address")!
        XCTAssertTrue(address !== nuAddress)
        
        // Update nuAddress:
        nuAddress.set("94032", forKey: "zip")
        XCTAssertEqual(nuAddress.getString("zip"), "94032")
        XCTAssertNil(address.getString("zip"))
        
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
        
        let members = doc.getArray("members")!
        XCTAssertTrue(members === doc.getValue("members") as! ArrayObject)
        XCTAssertEqual(members.count, 3)
        XCTAssertEqual(members.getString(0), "a")
        XCTAssertEqual(members.getString(1), "b")
        XCTAssertEqual(members.getString(2), "c")
        XCTAssertTrue(members.toArray() == ["a", "b", "c"])
        
        // Update with a new array:
        let nuArray = ["d", "e", "f"]
        doc.set(nuArray, forKey: "members")
        
        // Check whether the old members array is still accessible:
        XCTAssertEqual(members.count, 3)
        XCTAssertEqual(members.getString(0), "a")
        XCTAssertEqual(members.getString(1), "b")
        XCTAssertEqual(members.getString(2), "c")
        XCTAssertTrue(members.toArray() == ["a", "b", "c"])
        
        // The old members array should be detached:
        let nuMembers = doc.getArray("members")!
        XCTAssertTrue(nuMembers !== members)
        
        // Update nuMembers:
        nuMembers.add("g")
        XCTAssertEqual(nuMembers.count, 4)
        XCTAssertEqual(nuMembers.getString(3), "g")
        
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
        
        shipping = doc.getDictionary("addresses")!.getDictionary("shipping")!
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
        
        address1 = doc.getArray("addresses")!.getDictionary(0)!
        address1.set("2 Main street", forKey: "street")
        address1.set("94042", forKey: "zip")
        
        address2 = doc.getArray("addresses")!.getDictionary(1)!
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
        
        group1 = doc.getArray("groups")!.getArray(0)!
        group1.set("d", at: 0)
        group1.set("e", at: 1)
        group1.set("f", at: 2)
        
        group2 = doc.getArray("groups")!.getArray(1)!
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
        
        member1 = doc.getDictionary("group1")!.getArray("member")!
        member1.set("d", at: 0)
        member1.set("e", at: 1)
        member1.set("f", at: 2)
        
        member2 = doc.getDictionary("group2")!.getArray("member")!
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
        
        XCTAssert(doc.getDictionary("shipping")! === address)
        XCTAssert(doc.getDictionary("billing")! === address)
        
        address.set("94042", forKey: "zip")
        XCTAssertEqual(doc.getDictionary("shipping")!.getString("zip"), "94042")
        XCTAssertEqual(doc.getDictionary("billing")!.getString("zip"), "94042")
        
        doc = try saveDocument(doc)
        
        let shipping = doc.getDictionary("shipping")!
        let billing = doc.getDictionary("billing")!
        
        // After save: both shipping and billing address are now independent to each other
        XCTAssert(shipping !== address)
        XCTAssert(billing !== address)
        XCTAssert(shipping !== billing)
        
        shipping.set("2 Main street", forKey: "street")
        billing.set("3 Main street", forKey: "street")
        
        // Save update:
        doc = try saveDocument(doc)
        
        XCTAssertEqual(doc.getDictionary("shipping")!.getString("street")!, "2 Main street")
        XCTAssertEqual(doc.getDictionary("billing")!.getString("street")!, "3 Main street")
    }
    
    
    func testSetArrayToMultipleKeys() throws {
        var doc = createDocument("doc1")
        
        let phones = ArrayObject()
        phones.add("650-000-0001")
        phones.add("650-000-0002")
        
        doc.set(phones, forKey: "mobile")
        doc.set(phones, forKey: "home")
        
        XCTAssert(doc.getArray("mobile")! === phones)
        XCTAssert(doc.getArray("home")! === phones)
        
        // Update phones: both mobile and home should get the update
        phones.add("650-000-0003")
        XCTAssert(doc.getArray("mobile")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003"])
        XCTAssert(doc.getArray("home")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003"])
        
        doc = try saveDocument(doc)
        
        // After save: both mobile and home are not independent to each other
        let mobile = doc.getArray("mobile")!
        let home = doc.getArray("home")!
        XCTAssert(mobile !== phones)
        XCTAssert(home !== phones)
        XCTAssert(mobile !== home)
        
        // Update mobile and home:
        mobile.add("650-000-1234")
        home.add("650-000-5678")
        
        doc = try saveDocument(doc)
        
        XCTAssert(doc.getArray("mobile")!.toArray() ==
            ["650-000-0001", "650-000-0002", "650-000-0003", "650-000-1234"])
        XCTAssert(doc.getArray("home")!.toArray() ==
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
        
        doc.set(nil, forKey: "name")
        doc.set(nil, forKey: "weight")
        doc.set(nil, forKey: "age")
        doc.set(nil, forKey: "active")
        doc.getDictionary("address")?.set(nil, forKey: "city")
        
        XCTAssertNil(doc.getString("name"))
        XCTAssertEqual(doc.getFloat("weight"), 0.0)
        XCTAssertEqual(doc.getDouble("weight"), 0.0)
        XCTAssertEqual(doc.getInt("age"), 0)
        XCTAssertEqual(doc.getBoolean("active"), false)
        
        XCTAssertNil(doc.getValue("name"))
        XCTAssertNil(doc.getValue("weight"))
        XCTAssertNil(doc.getValue("age"))
        XCTAssertNil(doc.getValue("active"))
        XCTAssertNil(doc.getDictionary("address")!.getValue("city"))
        
        let docDict: [String: Any] = ["type": "profile",
                                      "address": ["street": "1 milky way.", "zip": 12345]];
        XCTAssert(doc.toDictionary() == docDict)
        
        let address = doc.getDictionary("address")!
        let addressDict: [String: Any] = ["street": "1 milky way.", "zip": 12345]
        XCTAssert(address.toDictionary() == addressDict)
        
        // Remove the rest:
        doc.set(nil, forKey: "type")
        doc.set(nil, forKey: "address")
        XCTAssertNil(doc.getValue("type"))
        XCTAssertNil(doc.getValue("address"))
        XCTAssert(doc.toDictionary() == [:] as [String: Any])
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
        XCTAssertEqual(doc.getString("name")!, "Scott Tiger")
    }
    
    
    func testDeleteDocument() throws {
        let doc = createDocument("doc1")
        doc.set("Scott Tiger", forKey: "name")
        XCTAssertFalse(doc.isDeleted)
        
        // Save:
        try saveDocument(doc)
        
        // Delete:
        try self.db.delete(doc)
        XCTAssertNil(doc.getValue("name"))
        XCTAssert(doc.toDictionary() == [:] as [String: Any])
        XCTAssert(doc.isDeleted)
    }
    
    
    func testDictionaryAfterDeleteDocument() throws {
        let dict = ["address": ["street": "1 Main street",
                                "city": "Mountain View",
                                "state": "CA"]]
        
        let doc = createDocument("doc1", dictionary: dict)
        try saveDocument(doc)
        
        let address = doc.getDictionary("address")!
        XCTAssertEqual(address.getString("street"), "1 Main street")
        XCTAssertEqual(address.getString("city"), "Mountain View")
        XCTAssertEqual(address.getString("state"), "CA")
        
        try self.db.delete(doc)
        XCTAssertNil(doc.getDictionary("address"))
        XCTAssert(doc.toDictionary() == [:] as [String: Any])
        
        // The dictionary still has data but is detached:
        XCTAssertEqual(address.getString("street"), "1 Main street")
        XCTAssertEqual(address.getString("city"), "Mountain View")
        XCTAssertEqual(address.getString("state"), "CA")
        
        // Make changes to the dictionary shouldn't affect the document.
        address.set("94042", forKey: "zip")
        XCTAssertNil(doc.getDictionary("address"))
        XCTAssert(doc.toDictionary() == [:] as [String: Any])
    }
    
    
    func testPurgeDocument() throws {
        let doc = createDocument("doc1")
        doc.set("profile", forKey: "type")
        doc.set("Scott", forKey: "name")
        XCTAssertFalse(doc.isDeleted)
        
        // Purge before save:
        try? self.db.purge(doc)
        XCTAssertEqual(doc.getString("type"), "profile")
        XCTAssertEqual(doc.getString("name"), "Scott")
        
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
        XCTAssertEqual(doc.getString("string"), "str")
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
        XCTAssertEqual(doc.getString("name"), "Jim")
        XCTAssert(doc.getValue("data") as? Blob != nil)
        
        blob = doc.getBlob("data")!
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
        
        blob = doc.getBlob("data")!
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
        
        blob = doc.getBlob("data")!
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
        
        blob = doc.getBlob("data")!
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
        
        XCTAssert(doc.getValue("data") as? Blob != nil)
        XCTAssertEqual(doc.getBlob("data")!.content!, content)
        
        try reopenDB()
        
        doc = db.getDocument("doc1")!
        doc.set("bar", forKey: "foo")
        try saveDocument(doc)
        
        XCTAssert(doc.getValue("data") as? Blob != nil)
        XCTAssertEqual(doc.getBlob("data")!.content!, content)
    }
}
