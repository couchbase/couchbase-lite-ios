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

    var doc: Document!

    override func setUp() {
        super.setUp()
        doc = db["doc1"]
    }
    
    override func tearDown() {
        doc.revert()      // Avoid "Closing database with 1 unsaved docs" warning
        super.tearDown()
    }

    override func reopenDB() throws {
        try super.reopenDB()
        doc = db["doc1"]
    }

    func testNewDoc() throws {
        XCTAssert(!doc["prop"])
        XCTAssertEqual(doc["prop"], 0)
        XCTAssertEqual(doc["prop"], 0.0)

        let d: Date? = doc["prop"]
        XCTAssertNil(d)

        let s: String? = doc["prop"]
        XCTAssertNil(s)

        let a: Any? = doc.property("prop")
        XCTAssertNil(a)

        try doc.save()
        XCTAssert(doc.exists);
        XCTAssertFalse(doc.isDeleted);
        XCTAssertNil(doc.properties);
    }

    func testPropertyAccessors() throws {
        doc["true"] = true
        doc["false"] = false
        doc["int"] = 123456
        doc["float"] = Float(3.14)
        doc["double"] = 3.141592654
        doc["string"] = "capybara"
        doc["array"] = [1, 2, "three", 4.4]
        doc["dict"] = ["eenie": 1, "meenie": 2.2, "miney": "moe"]
        doc["null"] = NSNull()
        doc["none"] = nil

        let checkProperties = {
            XCTAssert(self.doc["true"])
            XCTAssert(!self.doc["false"])
            XCTAssertEqual(self.doc["int"], 123456)
            XCTAssert(self.doc["int"])
            XCTAssertEqual(self.doc["float"], Float(3.14))
            XCTAssertEqual(self.doc["float"], 3)
            XCTAssertEqual(self.doc["double"], 3.141592654)
            XCTAssertEqual(self.doc["double"], 3)

            let array: [Any] = self.doc["array"]!
            XCTAssertEqual(array.count, 4)
            XCTAssert(array[0] as? Int == 1)

            let dict: CBLSubdocument = self.doc["dict"]!
            XCTAssertEqual(dict.properties?.count, 3)
            XCTAssert(dict["miney"] as? String == "moe")

            XCTAssert(self.doc.property("null") as? NSNull != nil)
            XCTAssertNil(self.doc.property("none"))
            XCTAssertFalse(self.doc.contains("none"))
        }

        // 1st pass: just read the unsaved properties back
        checkProperties()

        // 2nd pass: Save the doc, then check the properties
        try doc.save()
        checkProperties()

        // 3rd pass: Reopen the db, reload the doc, then check the properties
        try reopenDB()
        checkProperties()
    }

    func testRemoveProperties() throws {
        doc.properties = [ "type": "profile",
            "name": "Jason",
            "weight": 130.5,
            "address": [
                "street": "1 milky way.",
                "city": "galaxy city",
                "zip" : 12345
            ]
        ]

        XCTAssertEqual(doc["weight"], 130.5)
        XCTAssertEqual(doc["address"]?["zip"] as? Int, 12345)

        try doc.save()
        try reopenDB()

        XCTAssertEqual(doc["weight"], 130.5)
        XCTAssertEqual(doc["address"]?["zip"] as? Int, 12345)

        doc["name"] = nil

        XCTAssert(!doc.contains("name"))
        XCTAssertNil(doc.property("name"))

        try doc.save()
        try reopenDB()

        XCTAssert(!doc.contains("name"))
        XCTAssertNil(doc.property("name"))
    }

    func testBlob() throws {
        let content = "12345".data(using: String.Encoding.utf8)!
        let data = Blob(contentType: "text/plain", data: content)
        doc["data"] = data
        doc["name"] = "Jim"
        try doc.save()

        try reopenDB()

        XCTAssertEqual(doc["name"], "Jim")
        XCTAssert(doc.property("data") as? Blob != nil)
        let data2: Blob? = doc["data"]
        XCTAssert(data2 != nil)
        XCTAssertEqual(data2?.contentType, "text/plain")
        XCTAssertEqual(data2?.length, 5)
        XCTAssertEqual(data2?.content, content)

        //TODO: Reading from NSInputStream in Swift is ugly. Define our own API?
        let input = data2!.contentStream!
        input.open()
        var buffer = Array<UInt8>(repeating: 0, count: 10)
        let bytesRead = input.read(&buffer, maxLength: 10)
        XCTAssertEqual(bytesRead, 5)
        XCTAssertEqual(buffer[0...4], [49, 50, 51, 52, 53])
    }

}
