//
//  NotificationTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/23/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift


class NotificationTest: CBLTestCase {
    func testDatabaseChange() throws {
        let x = self.expectation(description: "change")
        
        let token = db.addChangeListener { (change) in
            XCTAssertEqual(change.documentIDs.count, 10)
            x.fulfill()
        }
       
        try db.inBatch {
            for i in 0...9 {
                let doc = createDocument("doc-\(i)")
                doc.setValue("demo", forKey: "type")
                try saveDocument(doc)
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
        
        db.removeChangeListener(withToken: token)
    }
    
    
    func testDocumentChange() throws {
        var doc1 = createDocument("doc1")
        doc1.setValue("Scott", forKey: "name")
        let savedDoc1 = try saveDocument(doc1)
        
        let doc2 = createDocument("doc2")
        doc2.setValue("Daniel", forKey: "name")
        let savedDoc2 = try saveDocument(doc2)
        
        let x = self.expectation(description: "Got all changes")
        
        var changes = Set<String>()
        changes.insert("doc1")
        changes.insert("doc2")
        changes.insert("doc3")
        
        let handler = { (change: DocumentChange) in
            changes.remove(change.documentID)
            if changes.count == 0 {
                x.fulfill()
            }
        }
        
        // Add change listeners:
        let listener1 = db.addDocumentChangeListener(withID: "doc1", listener: handler)
        let listener2 = db.addDocumentChangeListener(withID: "doc2", listener: handler)
        let listener3 = db.addDocumentChangeListener(withID: "doc3", listener: handler)
        
        // Update doc1:
        doc1 = savedDoc1.toMutable()
        doc1.setValue("Scott Tiger", forKey: "name")
        try saveDocument(doc1)
        
        // Delete doc2:
        try db.deleteDocument(savedDoc2)
        
        // Create doc3:
        let doc3 = createDocument("doc3")
        doc3.setValue("Jack", forKey: "name")
        try saveDocument(doc3)
        
        waitForExpectations(timeout: 5, handler: nil)
        
        db.removeChangeListener(withToken: listener1)
        db.removeChangeListener(withToken: listener2)
        db.removeChangeListener(withToken: listener3)
    }
    
    
    func testAddSameChangeListeners() throws {
        var doc1 = createDocument("doc1")
        doc1.setValue("Scott", forKey: "name")
        doc1 = try saveDocument(doc1).toMutable()
        
        let x = self.expectation(description: "Got all changes")
        
        var count = 0
        let handler = { (change: DocumentChange) in
            count = count + 1
            if count == 3 {
                x.fulfill()
            }
        }
        
        // Add change listeners:
        let listener1 = db.addDocumentChangeListener(withID: "doc1", listener: handler)
        let listener2 = db.addDocumentChangeListener(withID: "doc1", listener: handler)
        let listener3 = db.addDocumentChangeListener(withID: "doc1", listener: handler)
        
        // Update doc1:
        doc1.setValue("Scott Tiger", forKey: "name")
        try saveDocument(doc1)
        
        waitForExpectations(timeout: 5, handler: nil)
        
        db.removeChangeListener(withToken: listener1)
        db.removeChangeListener(withToken: listener2)
        db.removeChangeListener(withToken: listener3)
    }
    
    
    func testRemoveDocumentChangeListener() throws {
        var doc1 = createDocument("doc1")
        doc1.setValue("Scott", forKey: "name")
        doc1 = try saveDocument(doc1).toMutable()
        
        let x1 = self.expectation(description: "change")
        
        // Add change listener:
        
        let token = db.addDocumentChangeListener(withID: "doc1") { (change) in
            x1.fulfill()
        }
        
        // Update doc1:
        doc1.setValue("Scott Tiger", forKey: "name")
        doc1 = try saveDocument(doc1).toMutable()
        
        waitForExpectations(timeout: 5, handler: nil)
        
        // Remove change listener:
        db.removeChangeListener(withToken: token)
        
        doc1.setValue("Scott Tiger", forKey: "name")
        try saveDocument(doc1)
        
        // Let's wait for 0.5 seconds:
        let x2 = expectation(description: "No changes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            x2.fulfill()
        }
        waitForExpectations(timeout: 5, handler: nil)
        
        // Remove again:
        db.removeChangeListener(withToken: token)
    }
}
