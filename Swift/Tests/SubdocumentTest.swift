//
//  SubdocumentTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift

class SubdocumentTest: CBLTestCase {
    
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
    
    func testNewSubdoc() throws {
        let s: Subdocument? = doc["address"]
        XCTAssertNil(s)
        XCTAssertNil(doc.getValue("address"))
        
        var address = Subdocument()
        XCTAssertFalse(address.exists)
        XCTAssertNil(address.document)
        XCTAssertNil(address.properties)
        
        address["street"] = "1 Space Ave."
        XCTAssertEqual(address["street"], "1 Space Ave.")
        XCTAssertEqual(address.properties?["street"] as? String, "1 Space Ave.")
        
        doc["address"] = address
        XCTAssert(doc.getValue("address") as? Subdocument === address)
        XCTAssert(address.document === doc)
        
        try doc.save()
        XCTAssert(address.exists)
        XCTAssert(address.document === doc)
        XCTAssertEqual(address["street"], "1 Space Ave.")
        XCTAssertEqual(address.properties?["street"] as? String, "1 Space Ave.")
        
        try reopenDB()
        address = doc["address"]!
        XCTAssert(address.exists)
        XCTAssert(address.document === doc)
        XCTAssertEqual(address["street"], "1 Space Ave.")
        XCTAssertEqual(address.properties?["street"] as? String, "1 Space Ave.")
    }
    
    func testGetSubdocument() throws {
        var address: Subdocument? = doc["address"]
        XCTAssertNil(address)
        XCTAssertNil(doc.getValue("address"))
        
        doc.properties = ["address": ["street": "1 Space Ave."]]
        
        address = doc["address"]
        XCTAssertNotNil(address)
        XCTAssert(address! === doc.getValue("address") as? Subdocument)
        XCTAssertFalse(address!.exists)
        XCTAssert(address!.document === doc)
        XCTAssertEqual(address!["street"], "1 Space Ave.")
        XCTAssertEqual(address!.properties?["street"] as? String, "1 Space Ave.")
        
        try doc.save()
        XCTAssert(address!.exists)
        XCTAssert(address?.document === doc)
        XCTAssertEqual(address?["street"], "1 Space Ave.")
        XCTAssertEqual(address?.properties?["street"] as? String, "1 Space Ave.")
        
        try reopenDB()
        address = doc["address"]!
        XCTAssert(address! === doc.getValue("address") as? Subdocument)
        XCTAssert(address!.exists)
        XCTAssert(address!.document === doc)
        XCTAssertEqual(address!["street"], "1 Space Ave.")
        XCTAssertEqual(address!.properties?["street"] as? String, "1 Space Ave.")
    }
    
    func testNestedSubdocuments() {
        doc["level1"] = Subdocument()
        doc["level1"]!["name"] = "n1"
        
        doc["level1"]!["level2"] = Subdocument()
        doc["level1"]!["level2"]!["name"] = "n2"
        
        doc["level1"]!["level2"]!["level3"] = Subdocument()
        doc["level1"]!["level2"]!["level3"]!["name"] = "n3"
        
        let level1: Subdocument? = doc["level1"]
        let level2: Subdocument? = doc["level1"]?["level2"]
        let level3: Subdocument? = doc["level1"]?["level2"]?["level3"]
        
        XCTAssertNotNil(level1)
        XCTAssertNotNil(level2)
        XCTAssertNotNil(level3)
        
        XCTAssertFalse(level1!.exists)
        XCTAssertFalse(level2!.exists)
        XCTAssertFalse(level3!.exists)
        
        XCTAssertEqual(level1!["name"], "n1")
        XCTAssert(level1!.getValue("level2") as? Subdocument === level2)
        XCTAssertEqual(level2!["name"], "n2")
        XCTAssert(level2!.getValue("level3") as? Subdocument === level3)
        XCTAssertEqual(level3!["name"], "n3")
    }
    
    func testSetDictionary() throws {
        doc["address"] = ["street": "1 Space Ave."]
        
        var address: Subdocument? = doc["address"]
        XCTAssertEqual(address?.properties?.count, 1)
        XCTAssertEqual(address?.properties?["street"] as? String, "1 Space Ave.")
        
        try doc.save()
        try reopenDB()
        
        address = doc["address"]
        XCTAssertEqual(address?.properties?.count, 1)
        XCTAssertEqual(address?.properties?["street"] as? String, "1 Space Ave.")
    }
    
    func testSetDocumentProperties() throws {
        doc.properties = ["name": "Jason",
                          "address": [
                            "street": "1 Star Way.",
                            "phones":["mobile": "650-123-4567"]],
                          "references": [["name": "Scott"], ["name": "Sam"]]]
        
        let address: Subdocument? = doc["address"]
        XCTAssertNotNil(address)
        XCTAssert(address?.document === doc)
        XCTAssertEqual(address?["street"], "1 Star Way.")
        
        let phones: Subdocument? = address?["phones"]
        XCTAssertNotNil(phones)
        XCTAssert(phones?.document === doc)
        XCTAssertEqual(phones?["mobile"], "650-123-4567")
        
        let references: [Any]? = doc["references"]
        XCTAssertNotNil(references)
        XCTAssertEqual(references?.count, 2)
        
        let r1: Subdocument? = references?[0] as? Subdocument
        XCTAssertNotNil(r1)
        XCTAssertEqual(r1?["name"], "Scott")
        
        let r2: Subdocument? = references?[1] as? Subdocument
        XCTAssertNotNil(r2)
        XCTAssertEqual(r2?["name"], "Sam")
    }
    
    func testCopySubdocument() throws {
        doc.properties = ["name": "Jason",
                          "address": [
                            "street": "1 Star Way.",
                            "phones":["mobile": "650-123-4567"]]]
        
        let address: Subdocument = doc["address"]!
        XCTAssert(address.document === doc)
        let street: String = address["street"]!
        
        let phones: Subdocument = address["phones"]!
        XCTAssert(phones.document === doc)
        let mobile: String = phones["mobile"]!
        
        let address2: Subdocument? = address.copy() as? Subdocument
        XCTAssertNotNil(address2);
        XCTAssert(address !== address2)
        XCTAssertNil(address2!.document)
        XCTAssertEqual(street, address2!.getValue("street") as? String)
        
        let phone2: Subdocument? = address2!["phones"]
        XCTAssertNotNil(phone2)
        XCTAssertNil(phone2?.document)
        XCTAssertEqual(mobile, phone2?.getValue("mobile") as? String)
    }
    
    func testSetSubdocumentFromAnotherKey() {
        doc.properties = ["name": "Jason",
                          "address": [
                            "street": "1 Star Way.",
                            "phones":["mobile": "650-123-4567"]]]
        
        let address: Subdocument = doc["address"]!
        XCTAssert(address.document === doc)
        let street: String = address["street"]!
        
        let phones: Subdocument = address["phones"]!
        XCTAssert(phones.document === doc)
        let mobile: String = phones["mobile"]!
        
        doc["address2"] = address
        let address2: Subdocument? = doc["address2"]
        XCTAssertNotNil(address2)
        XCTAssert(address !== address2)
        XCTAssert(address2?.document === doc)
        XCTAssertEqual(street, address2?.getValue("street") as? String)
        
        let phones2: Subdocument? = address2?["phones"];
        XCTAssertNotNil(phones2)
        XCTAssert(phones !== phones2)
        XCTAssert(phones2?.document === doc)
        XCTAssertEqual(mobile, phones2?.getValue("mobile") as? String)
    }
    
    func testSubdocumentArray() {
        let dicts = [["name": "1"], ["name": "2"], ["name": "3"], ["name": "4"]]
        doc.properties = ["subdocs": dicts]
        
        var subdocs: [Any]? = doc["subdocs"]
        XCTAssertEqual(subdocs?.count, 4)
        
        let s1 = subdocs?[0] as? Subdocument
        let s2 = subdocs?[1] as? Subdocument
        let s3 = subdocs?[2] as? Subdocument
        let s4 = subdocs?[3] as? Subdocument
        
        XCTAssertEqual(s1?.getValue("name") as? String, "1")
        XCTAssertEqual(s2?.getValue("name") as? String, "2")
        XCTAssertEqual(s3?.getValue("name") as? String, "3")
        XCTAssertEqual(s4?.getValue("name") as? String, "4")
        
        // Make changes
        
        let s5 = Subdocument()
        s5["name"] = "5"
        
        doc["subdocs"] = [s5, "dummy", s2!, ["name": "6"], s1!] as [Any]
        
        var subdocs2: [Any]? = doc["subdocs"]
        XCTAssertEqual(subdocs2?.count, 5)
        
        XCTAssert(subdocs2?[0] as? Subdocument === s5)
        XCTAssertEqual(subdocs2?[1] as? String, "dummy");
        XCTAssert(subdocs2?[2] as? Subdocument === s2)
        XCTAssert(subdocs2?[3] as? Subdocument === s4)
        XCTAssert(subdocs2?[4] as? Subdocument === s1)
    }
    
    func testSetSubdocumentPropertiesNil() {
        doc.properties = ["name": "Jason",
                          "address": [
                            "street": "1 Star Way.",
                            "phones":["mobile": "650-123-4567"]],
                          "references": [["name": "Scott"], ["name": "Sam"]]]
        
        let address: Subdocument = doc["address"]!
        XCTAssert(address.document === doc)
        
        let phones: Subdocument = address["phones"]!
        XCTAssert(phones.document === doc)
        
        let references: [Any] = doc["references"]!
        let r1 = references[0] as! Subdocument
        let r2 = references[1] as! Subdocument
        
        doc["address"] = nil
        doc["references"] = nil
        
        // Check address:
        XCTAssertNil(doc.getValue("address"))
        XCTAssertNil(address.document)
        XCTAssertNil(address.properties)
        XCTAssertNil(address.getValue("street"))
        XCTAssertNil(address.getValue("phones"))
        
        // Check phones:
        XCTAssertNil(phones.document)
        XCTAssertNil(phones.properties)
        XCTAssertNil(phones.getValue("mobile"))
        
        // Check references:
        XCTAssertNil(doc.getValue("references"))
        XCTAssertNil(r1.document)
        XCTAssertNil(r1.properties)
        XCTAssertNil(r1.getValue("name"))
        XCTAssertNil(r2.document)
        XCTAssertNil(r2.properties)
        XCTAssertNil(r2.getValue("name"))
    }
    
    func testSetDocumentPropertiesNil() {
        doc.properties = ["name": "Jason",
                          "address": [
                            "street": "1 Star Way.",
                            "phones":["mobile": "650-123-4567"]],
                          "references": [["name": "Scott"], ["name": "Sam"]]]
        
        let address: Subdocument = doc["address"]!
        XCTAssert(address.document === doc)
        
        let phones: Subdocument = address["phones"]!
        XCTAssert(phones.document === doc)
        
        let references: [Any] = doc["references"]!
        let r1 = references[0] as! Subdocument
        let r2 = references[1] as! Subdocument
        
        doc.properties = nil
        
        // Check address:
        XCTAssertNil(doc.getValue("address"))
        XCTAssertNil(address.document)
        XCTAssertNil(address.properties)
        XCTAssertNil(address.getValue("street"))
        XCTAssertNil(address.getValue("phones"))
        
        // Check phones:
        XCTAssertNil(phones.document)
        XCTAssertNil(phones.properties)
        XCTAssertNil(phones.getValue("mobile"))
        
        // Check references:
        XCTAssertNil(doc.getValue("references"))
        XCTAssertNil(r1.document)
        XCTAssertNil(r1.properties)
        XCTAssertNil(r1.getValue("name"))
        XCTAssertNil(r2.document)
        XCTAssertNil(r2.properties)
        XCTAssertNil(r2.getValue("name"))
    }
    
    func testReplaceWithNonDict() {
        let address = Subdocument()
        address["street"] = "1 Star Way."
        
        doc["address"] = address
        XCTAssert(doc.getValue("address") as? Subdocument === address)
        XCTAssert(address.document === doc)
        
        doc["address"] = "123 Space Dr."
        XCTAssertEqual(doc["address"], "123 Space Dr.")
        XCTAssertNil(address.document)
        XCTAssertNil(address.properties)
    }
    
    func testReplaceWithNewSubdocument() {
        let address = Subdocument()
        address["street"] = "1 Star Way."
        
        doc["address"] = address
        XCTAssert(doc.getValue("address") as? Subdocument === address)
        XCTAssert(address.document === doc)
        
        let nuAddress = Subdocument()
        nuAddress["street"] = "123 Space Dr."
        doc["address"] = nuAddress
        
        XCTAssert(doc.getValue("address") as? Subdocument === nuAddress)
        XCTAssertNil(address.document)
        XCTAssertNil(address.properties)
    }
    
    func testReplaceWithNewDocProperties() {
        doc.properties = ["name": "Jason",
                          "address": [
                            "street": "1 Star Way.",
                            "phones":["mobile": "650-123-4567"]],
                          "work": ["company": "Couchbase"],
                          "subscription": ["type": "silver"],
                          "expiration": ["date": "2017-03-03T07:13:46.536Z"],
                          "references": [["name": "Scott"], ["name": "Sam"]]]
        
        let address: Subdocument = doc["address"]!
        let phones: Subdocument = address["phones"]!
        let work: Subdocument = doc["work"]!
        let subscription: Subdocument = doc["subscription"]!
        let expiration: Subdocument = doc["expiration"]!
        
        var references: [Any] = doc["references"]!
        let r1 = references[0] as! Subdocument
        let r2 = references[1] as! Subdocument
        
        let nuSubscription = Subdocument()
        nuSubscription["type"] = "platinum"
        
        let date = Date()
        doc.properties = ["name": "Jason",
                          "address": "1 Star Way.",
                          "work": ["company": "Couchbase", "position": "Engineer"],
                          "subscription": nuSubscription,
                          "expiration": date,
                          "references": [["name": "Smith"]]]
        
        XCTAssertEqual(doc["address"], "1 Star Way.")
        XCTAssertNil(address.document)
        XCTAssertNil(address.properties)
        
        XCTAssertNil(phones.document)
        XCTAssertNil(phones.properties)
        
        XCTAssert(doc.getValue("work") as? Subdocument === work)
        XCTAssertEqual(work["company"], "Couchbase")
        XCTAssertEqual(work["position"], "Engineer")
        
        XCTAssert(doc.getValue("subscription") as? Subdocument === nuSubscription)
        XCTAssertNil(subscription.document)
        XCTAssertNil(subscription.properties)
        
        XCTAssertNotNil(doc.getValue("expiration"))
        XCTAssertNil(doc.getValue("expiration") as? Subdocument)
        XCTAssertNil(expiration.document)
        XCTAssertNil(expiration.properties)
        
        references = doc["references"]!
        XCTAssertEqual(references.count, 1)
        XCTAssert(references[0] as! Subdocument === r1)
        XCTAssertEqual(r1["name"], "Smith")
        XCTAssertNil(r2.document)
        XCTAssertNil(r2.properties)
    }
    
    func testDeleteDocument() throws {
        doc.properties = ["name": "Jason",
                          "address": [
                            "street": "1 Star Way.",
                            "phones":["mobile": "650-123-4567"]],
                          "references": [["name": "Scott"], ["name": "Sam"]]]
        
        try doc.save()
        
        let address: Subdocument = doc["address"]!
        XCTAssert(address.document === doc)
        
        let phones: Subdocument = address["phones"]!
        XCTAssert(phones.document === doc)
        
        let references: [Any] = doc["references"]!
        let r1 = references[0] as! Subdocument
        let r2 = references[1] as! Subdocument
        
        try doc.delete()
        
        // Check doc:
        XCTAssertNil(doc.properties)
        XCTAssertNil(doc.getValue("name"))
        XCTAssertNil(doc.getValue("address"))
        XCTAssertNil(doc.getValue("references"))
        
        // Check address:
        XCTAssertNil(doc.getValue("address"))
        XCTAssertNil(address.document)
        XCTAssertFalse(address.exists)
        XCTAssertNil(address.properties)
        XCTAssertNil(address.getValue("street"))
        XCTAssertNil(address.getValue("phones"))
        
        // Check phones:
        XCTAssertNil(phones.document)
        XCTAssertFalse(phones.exists)
        XCTAssertNil(phones.properties)
        XCTAssertNil(phones.getValue("mobile"))
        
        // Check references:
        XCTAssertNil(doc.getValue("references"))
        XCTAssertNil(r1.document)
        XCTAssertFalse(r1.exists)
        XCTAssertNil(r1.properties)
        XCTAssertNil(r1.getValue("name"))
        XCTAssertNil(r2.document)
        XCTAssertFalse(r2.exists)
        XCTAssertNil(r2.properties)
        XCTAssertNil(r2.getValue("name"))
    }
}
