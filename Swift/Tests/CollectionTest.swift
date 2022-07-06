//
//  CollectionTest.swift
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 7/6/22.
//  Copyright © 2022 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift

class CollectionTest: CBLTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }
    
    // MARK: Collection Management
    
    func testCreateCollection() throws {
        var collections = try self.db.collections(scope: Scope.defaultScopeName)
        XCTAssertEqual(collections.count, 1)
        guard let d = collections.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(d.name, Collection.defaultCollectionName)
        XCTAssertEqual(d.scope.name, Scope.defaultScopeName)
        
        let c2 = try self.db.createCollection(name: "collection1")
        XCTAssertNotNil(c2)
        
        collections = try self.db.collections(scope: Scope.defaultScopeName)
        XCTAssertEqual(collections.count, 2)
        let names = collections.map({ $0.name }).sorted()
        XCTAssertEqual(names, ["_default", "collection1"])
        
        let _ = try self.db.createCollection(name: "collection2", scope: "scope2")
        collections = try self.db.collections(scope: "scope2")
        XCTAssertEqual(collections.count, 1)
        guard let c3 = collections.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(c3.name, "collection2")
        XCTAssertEqual(c3.scope.name, "scope2")
    }
    
    func testDeleteCollection() throws {
        let _ = try self.db.createCollection(name: "collection1")
        let _ = try self.db.createCollection(name: "collection2")
        
        var collections = try self.db.collections()
        XCTAssertEqual(collections.count, 3)
        
        // delete without scope
        try self.db.deleteCollection(name: "collection1")
        collections = try self.db.collections()
        XCTAssertEqual(collections.count, 2)
        
        // delete without scope
        try self.db.deleteCollection(name: "collection2", scope: Scope.defaultScopeName)
        collections = try self.db.collections()
        XCTAssertEqual(collections.count, 1)
        XCTAssertEqual(collections.first!.name, Collection.defaultCollectionName)
    }
    
    func testCreateDuplicateCollection() throws {
        // Create in Default Scope
        let _ = try self.db.createCollection(name: "collection1")
        let _ = try self.db.createCollection(name: "collection1")
        
        // verify no duplicate is created.
        var collections = try self.db.collections()
        XCTAssertEqual(collections.count, 2)
        
        // Create in Custom Scope
        let _ = try self.db.createCollection(name: "collection2", scope: "scope1")
        let _ = try self.db.createCollection(name: "collection2", scope: "scope1")
        
        // verify no duplicate is created.
        collections = try self.db.collections(scope: "scope1")
        XCTAssertEqual(collections.count, 1)
    }
    
    // MARK: Index
    
    func testCollectionIndex() throws {
        guard let collection = try db.defaultCollection() else {
            XCTFail("default collection is missing")
            return
        }
        
        let config1 = ValueIndexConfiguration(["firstName", "lastName"])
        try collection.createIndex(withName: "index1", config: config1)
        
        let config2 = FullTextIndexConfiguration(["detail"])
        try collection.createIndex(withName: "index2", config: config2)
        
        let config3 = FullTextIndexConfiguration(["es_detail"], ignoreAccents: true, language: "es")
        try collection.createIndex(withName: "index3", config: config3)
        
        let config4 = FullTextIndexConfiguration(["name"], ignoreAccents: false, language: "en")
        try collection.createIndex(withName: "index4", config: config4)
        
        // use backtick in case of property name with hyphen
        let config5 = FullTextIndexConfiguration(["`es-detail`"], ignoreAccents: true, language: "es")
        try collection.createIndex(withName: "index5", config: config5)
        
        // same index twice: no-op
        let config6 = FullTextIndexConfiguration(["detail"])
        try collection.createIndex(withName: "index2", config: config6)
        
        XCTAssertEqual(try collection.indexes().count, 5)
        XCTAssertEqual(try collection.indexes(), ["index1", "index2", "index3", "index4", "index5"])
    }
    
    // MARK: change observer
    
    func testCollectionChangeEvent() throws {
        guard let collection = try db.defaultCollection() else {
            XCTFail("default collection is missing")
            return
        }
        let doc = try generateDocument(withID: "doc1")
        let x = self.expectation(description: "change")
        let token = collection.addChangeListener { (change) in
            XCTAssertEqual(change.documentIDs.count, 1)
            XCTAssertEqual(change.documentIDs.first, doc.id)
            x.fulfill()
        }
        
        let expiryDate = Date().addingTimeInterval(1)
        try collection.setDocumentExpiration(id: doc.id, expiration: expiryDate)
        
        // Wait for result
        waitForExpectations(timeout: 5.0)
        
        // Remove listener
        token.remove();
    }
}
