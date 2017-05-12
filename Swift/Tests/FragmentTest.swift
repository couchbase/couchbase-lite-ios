//
//  FragmentTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift


class FragmentTest: CBLTestCase {
    func testGetDocFragmentWithID() throws {
        let dict: [String: Any] = ["address": [
                                    "street": "1 Main street",
                                    "city": "Mountain View",
                                    "state": "CA"]];
        try saveDocument(createDocument("doc1", dictionary: dict))
        
        let doc = db["doc1"]
        XCTAssertNotNil(doc)
        XCTAssertTrue(doc.exists)
        XCTAssertNotNil(doc.document)
        XCTAssertEqual(doc["address"]["street"].string!, "1 Main street")
        XCTAssertEqual(doc["address"]["city"].string!, "Mountain View")
        XCTAssertEqual(doc["address"]["state"].string!, "CA")
    }
    
    
    func testGetDocFragmentWithNonExistingID() throws {
        let doc = db["doc1"]
        XCTAssertNotNil(doc)
        XCTAssertFalse(doc.exists)
        XCTAssertNil(doc["address"]["street"].string)
        XCTAssertNil(doc["address"]["city"].string)
        XCTAssertNil(doc["address"]["state"].string)
    }
    
    
    
}
