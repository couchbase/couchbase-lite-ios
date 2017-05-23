//
//  NotificationTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/23/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift


class NotificationTest: CBLTestCase, DocumentChangeListener {
    var testContext: String?
    var expectedDocumentChanges: Set<String>?
    var documentChangeExpectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        expectedDocumentChanges = nil
        documentChangeExpectation = nil
    }
    
    
    func testDatabaseChange() throws {
        expectation(forNotification: DatabaseChangeNotification, object: nil) { (n) -> Bool in
            let change = n.userInfo![DatabaseChangesUserInfoKey] as! DatabaseChange
            XCTAssertEqual(change.documentIDs.count, 10)
            return true
        }
        
        try db.inBatch {
            for i in 0...9 {
                let doc = createDocument("doc-\(i)")
                doc.set("demo", forKey: "type")
                try saveDocument(doc)
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    
    public func documentDidChange(_ change: CBLDocumentChange) {
        if let expectation = documentChangeExpectation {
            XCTAssertTrue(expectedDocumentChanges!.contains(change.documentID))
            expectedDocumentChanges!.remove(change.documentID)
            if (expectedDocumentChanges!.count == 0) {
                expectation.fulfill()
            }
        }
    }
    
    
    func testDocumentChange() throws {
        let doc1 = createDocument("doc1")
        doc1.set("Scott", forKey: "name")
        try saveDocument(doc1)
        
        let doc2 = createDocument("doc2")
        doc2.set("Daniel", forKey: "name")
        try saveDocument(doc2)
        
        // Add change listeners:
        db.addChangeListener(self, forDocumentID: "doc1")
        db.addChangeListener(self, forDocumentID: "doc2")
        db.addChangeListener(self, forDocumentID: "doc3")
        
        documentChangeExpectation = expectation(description: "document change")
        
        expectedDocumentChanges = Set()
        expectedDocumentChanges!.insert("doc1")
        expectedDocumentChanges!.insert("doc2")
        expectedDocumentChanges!.insert("doc3")
        
        // Update doc1:
        doc1.set("Scott Tiger", forKey: "name")
        try saveDocument(doc1)
        
        // Delete doc2:
        try db.delete(doc2)
        
        // Create doc3:
        let doc3 = createDocument("doc3")
        doc3.set("Jack", forKey: "name")
        try saveDocument(doc3)
        
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    
    func testAddSameChangeListeners() throws {
        let doc1 = createDocument("doc1")
        doc1.set("Scott", forKey: "name")
        try saveDocument(doc1)
        
        // Add change listeners:
        db.addChangeListener(self, forDocumentID: "doc1")
        db.addChangeListener(self, forDocumentID: "doc1")
        db.addChangeListener(self, forDocumentID: "doc1")
        db.addChangeListener(self, forDocumentID: "doc1")
        db.addChangeListener(self, forDocumentID: "doc1")
        
        documentChangeExpectation = expectation(description: "document change")
        
        expectedDocumentChanges = Set()
        expectedDocumentChanges!.insert("doc1")
        
        // Update doc1:
        doc1.set("Scott Tiger", forKey: "name")
        try saveDocument(doc1)
        
        let x = expectation(description: "No changes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            x.fulfill()
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    
    func testRemoveDocumentChangeListener() throws {
        let doc1 = createDocument("doc1")
        doc1.set("Scott", forKey: "name")
        try saveDocument(doc1)
        
        // Add change listener:
        db.addChangeListener(self, forDocumentID: "doc1")
        
        documentChangeExpectation = expectation(description: "document change")
        
        expectedDocumentChanges = Set()
        expectedDocumentChanges!.insert("doc1")
        
        // Update doc1:
        doc1.set("Scott Tiger", forKey: "name")
        try saveDocument(doc1)
        
        waitForExpectations(timeout: 5, handler: nil)
        
        // Remove change listener:
        db.removeChangeListener(self, forDocumentID: "doc1")
        
        testContext = "testRemoveDocumentChangeListener"
        doc1.set("Scott Tiger", forKey: "name")
        try saveDocument(doc1)
        
        // Let's wait for 0.5 seconds:
        let x = expectation(description: "No changes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            x.fulfill()
        }
        waitForExpectations(timeout: 5, handler: nil)
        
        // Remove again:
        db.removeChangeListener(self, forDocumentID: "doc1")
        
        // Remove before add:
        db.removeChangeListener(self, forDocumentID: "doc2")
    }
}
