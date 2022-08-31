//
//  CollectionTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

class CollectionTest: CBLTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }
    
    // MARK: Default Scope/Collection
    
    func testDefaultCollectionExists() throws {
        guard let collection = try self.db.defaultCollection() else {
            XCTFail("Collection shouldn't be empty!")
            return
        }
        XCTAssertEqual(collection.name, Database.defaultCollectionName)
        
        let cols = try self.db.collections()
        XCTAssertTrue(cols.contains(where: { $0 == collection }))
        
        let scope = collection.scope
        XCTAssertNotNil(scope)
        XCTAssertEqual(scope.name, Scope.defaultScopeName)
        
        let col1 = try self.db.collection(name: Database.defaultCollectionName)
        XCTAssertEqual(collection, col1)
    }
    
    func testDefaultScopeExists() throws {
        let scope = try self.db.defaultScope()
        XCTAssertNotNil(scope)
        XCTAssertEqual(scope.name, Scope.defaultScopeName)
        
        let scopes = try self.db.scopes()
        XCTAssertEqual(scopes.count, 1)
        XCTAssertEqual(scopes[0].name, Scope.defaultScopeName)
        
        guard let scope1 = try self.db.scope(name: Scope.defaultScopeName) else {
            XCTFail("default scope shouldn't be empty!")
            return
        }
        XCTAssertEqual(scope1.name, Scope.defaultScopeName)
    }
    
    func testDeleteDefaultCollection() throws {
        try self.db.deleteCollection(name: Database.defaultCollectionName)
        
        var collection = try self.db.defaultCollection()
        XCTAssertNil(collection)
        
        self.expectError(domain: CBLErrorDomain, code: CBLError.invalidParameter) {
            let _ = try self.db.createCollection(name: Database.defaultCollectionName)
        }
        
        collection = try self.db.defaultCollection()
        XCTAssertNil(collection)
    }
    
    func testGetDefaultScopeAfterDeleteDefaultCollection() throws {
        try self.db.deleteCollection(name: Database.defaultCollectionName)
        
        let scope = try self.db.defaultScope()
        XCTAssertEqual(scope.name, Scope.defaultScopeName)
        
        let scopes = try self.db.scopes()
        XCTAssertEqual(scopes.count, 1)
        XCTAssertEqual(scopes[0].name, Scope.defaultScopeName)
    }
    
    // MARK: 8.2 Collections
    
    func testCreateAndGetCollectionsInDefaultScope() throws {
        let colA = try self.db.createCollection(name: "colA")
        let colB = try self.db.createCollection(name: "colB", scope: Scope.defaultScopeName)
        
        XCTAssertEqual(colA.name, "colA")
        XCTAssertEqual(colA.scope.name, Scope.defaultScopeName)
        XCTAssertEqual(colB.name, "colB")
        XCTAssertEqual(colB.scope.name, Scope.defaultScopeName)
        
        // created collections exist when calling database.collectionWithName:
        guard let colAa = try self.db.collection(name: "colA") else {
            XCTFail("Collection A is empty")
            return
        }
        XCTAssertEqual(colA.name, colAa.name)
        XCTAssertEqual(colA.scope.name, colAa.scope.name)
        
        guard let colBa = try self.db.collection(name: "colB") else {
            XCTFail("Collection B is empty")
            return
        }
        XCTAssertEqual(colB.name, colBa.name)
        XCTAssertEqual(colB.scope.name, colBa.scope.name)
        
        let collections = try self.db.collections()
        XCTAssertEqual(collections.count, 3)
        XCTAssert(collections.contains(where: { $0.name == "colA" }))
        XCTAssert(collections.contains(where: { $0.name == "colB" }))
        XCTAssert(collections.contains(where: { $0.name == Database.defaultCollectionName }))
    }
    
    func testCreateAndGetCollectionsInNamedScope() throws {
        let noScope = try self.db.scope(name: "scopeA")
        XCTAssertNil(noScope)
        
        let colA = try self.db.createCollection(name: "colA", scope: "scopeA")
        XCTAssertEqual(colA.name, "colA")
        XCTAssertEqual(colA.scope.name, "scopeA")
        
        guard let scopeA = try self.db.scope(name: "scopeA") else {
            XCTFail("scopeA is missing!")
            return
        }
        XCTAssertEqual(scopeA.name, "scopeA")
        
        guard let colAa = try self.db.collection(name: "colA", scope: "scopeA") else {
            XCTFail("Collection is missing!")
            return
        }
        XCTAssertEqual(colAa.name, "colA")
        XCTAssertEqual(colAa.scope.name, "scopeA")
        
        let scopes = try self.db.scopes()
        XCTAssertEqual(scopes.count, 2)
        XCTAssert(scopes.contains(where: { $0.name == "scopeA" }))
        XCTAssert(scopes.contains(where: { $0.name == Scope.defaultScopeName }))
    }
    
    func testCreateAnExistingCollection() throws {
        let colA = try self.db.createCollection(name: "colA", scope: "scopeA")
        
        let mdoc = MutableDocument(id: "doc1")
        mdoc.setString("string", forKey: "somekey")
        try colA.save(document: mdoc)
        
        let colB = try self.db.createCollection(name: "colA", scope: "scopeA")
        let doc1 = try colB.document(id: "doc1")
        XCTAssertNotNil(doc1)
    }
    
    func testGetNonExistingCollection() throws {
        XCTAssertNil(try self.db.collection(name: "colA", scope: "scopeA"))
    }
    
    func testDeleteCollection() throws {
        let colA = try self.db.createCollection(name: "colA", scope: "scopeA")
        
        let mdoc1 = MutableDocument(id: "doc1")
        mdoc1.setString("str", forKey: "str")
        try colA.save(document: mdoc1)
        
        let mdoc2 = MutableDocument(id: "doc2")
        mdoc2.setString("str2", forKey: "str")
        try colA.save(document: mdoc2)
        
        let mdoc3 = MutableDocument(id: "doc3")
        mdoc3.setString("str3", forKey: "str")
        try colA.save(document: mdoc3)
        
        XCTAssertEqual(colA.count, 3)
        
        try self.db.deleteCollection(name: "colA", scope: "scopeA")
        XCTAssertNil(try self.db.collection(name: "colA", scope: "scopeA"))
        
        let cols = try self.db.collections(scope: "scopeA")
        XCTAssertEqual(cols.count, 0)
        
        let colAa = try self.db.createCollection(name: "colA", scope: "scopeA")
        XCTAssertNotNil(colAa)
        XCTAssertEqual(colAa.count, 0)
    }
    
    func testGetCollectionsFromScope() throws {
        let _ = try self.db.createCollection(name: "colA", scope: "scopeA")
        let _ = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        guard let scopeA = try self.db.scope(name: "scopeA") else {
            XCTFail("ScopeA missing!")
            return
        }
        
        XCTAssertNotNil(try scopeA.collection(name: "colA"))
        XCTAssertNotNil(try scopeA.collection(name: "colB"))
        
        let cols = try self.db.collections(scope: "scopeA")
        XCTAssertEqual(cols.count, 2)
        XCTAssert(cols.contains(where: { $0.name == "colA" }))
        XCTAssert(cols.contains(where: { $0.name == "colB" }))
    }
    
    func testDeleteAllCollectionsInScope() throws {
        let _ = try self.db.createCollection(name: "colA", scope: "scopeA")
        let _ = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        guard let scopeA = try self.db.scope(name: "scopeA") else {
            XCTFail("scopeA is missing")
            return
        }
        var collectionsInScopeA = try scopeA.collections()
        XCTAssertEqual(collectionsInScopeA.count, 2)
        XCTAssert(collectionsInScopeA.contains(where: { $0.name == "colA" }))
        XCTAssert(collectionsInScopeA.contains(where: { $0.name == "colB" }))
        
        try self.db.deleteCollection(name: "colA", scope: "scopeA")
        collectionsInScopeA = try scopeA.collections()
        XCTAssertEqual(collectionsInScopeA.count, 1)
        try self.db.deleteCollection(name: "colB", scope: "scopeA")
        
        XCTAssertNil(try self.db.scope(name: "scopeA"))
        XCTAssertNil(try self.db.collection(name: "colA", scope: "scopeA"))
        XCTAssertNil(try self.db.collection(name: "colB", scope: "scopeA"))
    }
    
    func testScopeCollectionNameWithValidChars() throws {
        let names = ["a",
                     "A",
                     "0", "-",
                     "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_%"]
        
        for name in names {
            let col = try self.db.createCollection(name: name, scope: name)
            XCTAssertNotNil(col)
            
            guard let col2 = try self.db.collection(name: name, scope: name) else {
                XCTFail("Get collection not returning collection!")
                return
            }
            XCTAssertEqual(col.name, col2.name)
            XCTAssertEqual(col.scope.name, col2.scope.name)
        }
    }
    
    func testScopeCollectionNameWithIllegalChars() throws {
        self.expectError(domain: CBLErrorDomain, code: CBLError.invalidParameter) {
            let _ = try self.db.createCollection(name: "_")
        }
        
        self.expectError(domain: CBLErrorDomain, code: CBLError.invalidParameter) {
            let _ = try self.db.createCollection(name: "a", scope: "_")
        }
        
        self.expectError(domain: CBLErrorDomain, code: CBLError.invalidParameter) {
            let _ = try self.db.createCollection(name: "%")
        }
        
        self.expectError(domain: CBLErrorDomain, code: CBLError.invalidParameter) {
            let _ = try self.db.createCollection(name: "b", scope: "%")
        }
        
        for char in "!@#$^&*()+={}[]<>,.?/:;\"'\\|`~" {
            self.expectError(domain: CBLErrorDomain, code: CBLError.invalidParameter) {
                let _ = try self.db.createCollection(name: "a\(char)z")
            }
            
            self.expectError(domain: CBLErrorDomain, code: CBLError.invalidParameter) {
                let _ = try self.db.createCollection(name: "colA", scope: "a\(char)z")
            }
        }
    }
    
    func testScopeCollectionNameLength() throws {
        var names = [String]()
        var name = ""
        for i in 0..<251 {
            name.append("a")
            if i%4 == 0 { // without this, test might take ~20secs to finish
                names.append(name)
            }
        }
        names.append(name)
        
        for name in names {
            let col = try self.db.createCollection(name: name, scope: name)
            XCTAssertNotNil(col)
            XCTAssertEqual(col.name, name)
            XCTAssertEqual(col.scope.name, name)
        }
        
        name.append("a")
        self.expectError(domain: CBLErrorDomain, code: CBLError.invalidParameter) {
            let _ = try self.db.createCollection(name: name, scope: "scopeA")
        }
        
        self.expectError(domain: CBLErrorDomain, code: CBLError.invalidParameter) {
            let _ = try self.db.createCollection(name: "colA", scope: name)
        }
    }
    
    func testCollectionNameCaseSensitive() throws {
        let col1a = try self.db.createCollection(name: "COLLECTION1", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "collection1", scope: "scopeA")
        
        XCTAssertEqual(col1a.name, "COLLECTION1")
        XCTAssertEqual(col1b.name, "collection1")
        
        let cols = try self.db.collections(scope: "scopeA")
        XCTAssertEqual(cols.count, 2)
        XCTAssert(cols.contains(where: { $0.name == "COLLECTION1" }))
        XCTAssert(cols.contains(where: { $0.name == "collection1" }))
    }
    
    func testScopeNameCaseSensitive() throws {
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colA", scope: "SCOPEa")
        
        XCTAssertEqual(col1a.scope.name, "scopeA")
        XCTAssertEqual(col1b.scope.name, "SCOPEa")
        
        let scopes = try self.db.scopes()
        XCTAssertEqual(scopes.count, 3)
        XCTAssert(scopes.contains(where: { $0.name == "scopeA" }))
        XCTAssert(scopes.contains(where: { $0.name == "SCOPEa" }))
    }
    
    // MARK: Others
    
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
    
    // MARK: 8.3 Collections and Cross Database Instance
    
    func testCreateThenGetCollectionFromDifferentDatabaseInstance() throws {
        let col = try self.db.createCollection(name: "colA", scope: "scopeA")
        
        try createDocNumbered(col, start: 0, num: 10)
        
        let db2 = try openDB(name: databaseName)
        let col2 = try db2.createCollection(name: "colA", scope: "scopeA")
        
        XCTAssertEqual(col.name, col2.name)
        XCTAssertEqual(col.scope.name, col2.scope.name)
        XCTAssertEqual(col2.count, 10)
        
        let cols1 = try self.db.collections(scope: "scopeA")
        XCTAssertEqual(cols1.count, 1)
        let cols2 = try db2.collections(scope: "scopeA")
        XCTAssertEqual(cols2.count, 1)
        
        try createDocNumbered(col, start: 10, num: 10)
        XCTAssertEqual(col.count, 20)
        XCTAssertEqual(col2.count, 20)
    }
    
    func testDeleteThenGetCollectionFromDifferentDatabaseInstance() throws {
        let col = try self.db.createCollection(name: "colA", scope: "scopeA")
        
        try createDocNumbered(col, start: 0, num: 10)
        
        let db2 = try openDB(name: databaseName)
        let col2 = try db2.createCollection(name: "colA", scope: "scopeA")
        
        try self.db.deleteCollection(name: "colA", scope: "scopeA")
        XCTAssertEqual(col.count, 0)
        XCTAssertEqual(col2.count, 0)
        
        XCTAssertNil(try self.db.collection(name: "colA", scope: "scopeA"))
        XCTAssertNil(try db2.collection(name: "colA", scope: "scopeA"))
    }
    
    func testDeleteAndRecreateThenGetCollectionFromDifferentDatabaseInstance() throws {
        let col = try self.db.createCollection(name: "colA", scope: "scopeA")
        
        try createDocNumbered(col, start: 0, num: 10)
        XCTAssertEqual(col.count, 10)
        
        let db2 = try openDB(name: databaseName)
        let col2 = try db2.createCollection(name: "colA", scope: "scopeA")
        XCTAssertEqual(col2.count, 10)
        
        // Delete the collection from db
        try self.db.deleteCollection(name: "colA", scope: "scopeA")
        
        XCTAssertNil(try self.db.collection(name: "colA", scope: "scopeA"))
        XCTAssertNil(try db2.collection(name: "colA", scope: "scopeA"))
        
        // Recreate
        let col3 = try self.db.createCollection(name: "colA", scope: "scopeA")
        XCTAssertEqual(col3.count, 0)
        
        try createDocNumbered(col3, start: 0, num: 3)
        let col4 = try db2.createCollection(name: "colA", scope: "scopeA")
        XCTAssertEqual(col3.count, 3)
        XCTAssertEqual(col4.count, 3)
    }
    
    // MARK: 8.4 Listeners
    
    func testCollectionChangeListener() throws {
        let colA = try self.db.createCollection(name: "colA", scope: "scopeA")
        let colB = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let exp1 = expectation(description: "change listener 1")
        let exp2 = expectation(description: "change listener 2")
        let exp3 = expectation(description: "change listener 3")
        let exp4 = expectation(description: "change listener 4")
        
        var count1 = 0;
        var changeListenerFired = 0;
        let token1 = colA.addChangeListener { change in
            changeListenerFired += 1
            if change.collection.name == "colA" {
                count1 += change.documentIDs.count
                if count1 == 10 {
                    exp1.fulfill()
                }
            } else {
                XCTFail("CollectionB shouldn't receive any listener")
            }
        }
        
        var count2 = 0
        let token2 = colA.addChangeListener { change in
            changeListenerFired += 1
            if change.collection.name == "colA" {
                count2 += change.documentIDs.count
                if count2 == 10 {
                    exp2.fulfill()
                }
            } else {
                XCTFail("CollectionB shouldn't receive any listener")
            }
        }
        
        let q1 = DispatchQueue(label: "dispatch-queue-1")
        let q2 = DispatchQueue(label: "dispatch-queue-2")
        var count3 = 0
        let token3 = colA.addChangeListener(queue: q1) { change in
            changeListenerFired += 1
            if change.collection.name == "colA" {
                count3 += change.documentIDs.count
                if count3 == 10 {
                    exp3.fulfill()
                }
            } else {
                XCTFail("CollectionB shouldn't receive any listener")
            }
        }
        
        var count4 = 0
        let token4 = colA.addChangeListener(queue: q2) { change in
            changeListenerFired += 1
            if change.collection.name == "colA" {
                count4 += change.documentIDs.count
                if count4 == 10 {
                    exp4.fulfill()
                }
            } else {
                XCTFail("CollectionB shouldn't receive any listener")
            }
        }
        
        try createDocNumbered(colA, start: 0, num: 10)
        try createDocNumbered(colB, start: 0, num: 10)
        
        waitForExpectations(timeout: 10.0)
        changeListenerFired = 0
        token1.remove()
        token2.remove()
        token3.remove()
        token4.remove()
        
        try createDocNumbered(colA, start: 10, num: 10)
        try createDocNumbered(colB, start: 10, num: 10)
        XCTAssertEqual(changeListenerFired, 0)
    }
    
    func testCollectionDocumentChangeListener() throws {
        let colA = try self.db.createCollection(name: "colA", scope: "scopeA")
        let colB = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let exp1 = expectation(description: "doc change listener 1")
        let exp2 = expectation(description: "doc change listener 2")
        let exp3 = expectation(description: "doc change listener 3")
        let exp4 = expectation(description: "doc change listener 4")
        
        var count1 = 0;
        var changeListenerFired = 0;
        let token1 = colA.addDocumentChangeListener(id: "doc-1") { change in
            changeListenerFired += 1
            if change.collection.name == "colA" {
                count1 += 1
                if count1 == 2 {
                    exp1.fulfill()
                }
            } else {
                XCTFail("Collection-B shouldn't receive any listener")
            }
        }
        
        var count2 = 0
        let token2 = colA.addDocumentChangeListener(id: "doc-1") { change in
            changeListenerFired += 1
            if change.collection.name == "colA" {
                count2 += 1
                if count2 == 2 {
                    exp2.fulfill()
                }
            } else {
                XCTFail("Collection-B shouldn't receive any listener")
            }
        }
        
        let q1 = DispatchQueue(label: "dispatch-queue-1")
        let q2 = DispatchQueue(label: "dispatch-queue-2")
        var count3 = 0
        let token3 = colA.addDocumentChangeListener(id: "doc-1", queue: q1) { change in
            changeListenerFired += 1
            if change.collection.name == "colA" {
                count3 += 1
                if count3 == 2 {
                    exp3.fulfill()
                }
            } else {
                XCTFail("Collection-B shouldn't receive any listener")
            }
        }
        
        var count4 = 0
        let token4 = colA.addDocumentChangeListener(id: "doc-1", queue: q2) { change in
            changeListenerFired += 1
            if change.collection.name == "colA" {
                count4 += 1
                if count4 == 2 {
                    exp4.fulfill()
                }
            } else {
                XCTFail("Collection-B shouldn't receive any listener")
            }
        }
        
        var doc = MutableDocument(id: "doc-1")
        doc.setString("str", forKey: "key")
        try colA.save(document: doc)
        
        doc = try colA.document(id: "doc-1")!.toMutable()
        doc.setString("str2", forKey: "key")
        try colA.save(document: doc)
        
        try createDocNumbered(colB, start: 0, num: 10)
        
        waitForExpectations(timeout: 10.0)
        changeListenerFired = 0;
        token1.remove()
        token2.remove()
        token3.remove()
        token4.remove()
        
        doc = try colA.document(id: "doc-1")!.toMutable()
        doc.setString("str3", forKey: "key")
        try colA.save(document: doc)
        
        try createDocNumbered(colB, start: 10, num: 10)
        XCTAssertEqual(changeListenerFired, 0)
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
    
    // MARK: 8.5-6 Use collection APIs on deleted/closed scenarios
    
    func testUseCollectionAPIOnDeletedCollection() throws {
        try testUseInvalidCollection("colA") {
            try self.db.deleteCollection(name: "colA")
        }
    }
    
    func testUseCollectionAPIOnDeletedCollectionDeletedFromDifferentDBInstance() throws {
        let db2 = try openDB(name: databaseName)
        try testUseInvalidCollection("colA") {
            try db2.deleteCollection(name: "colA")
        }
    }
    
    func testUseCollectionAPIWhenDatabaseIsClosed() throws {
        try testUseInvalidCollection("colA") {
            try self.db.close()
        }
    }
    
    func testUseCollectionAPIWhenDatabaseIsDeleted() throws {
        try testUseInvalidCollection("colA") {
            try self.db.delete()
        }
    }
    
    func testUseInvalidCollection(_ collectionName: String, onAction: () throws -> Void) throws {
        let col = try self.db.createCollection(name: collectionName)
        
        try createDocNumbered(col, start: 0, num: 10)
        
        guard let doc = try col.document(id: "doc4") else {
            XCTFail("Doc doesn't exist!")
            return
        }
        
        try onAction()
        
        // document(id:)
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.document(id: "doc2")
        }
        
        // save document
        let mdoc = MutableDocument()
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.save(document: mdoc)
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.save(document: mdoc, conflictHandler: { doc, doc2 in
                return true
            })
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.save(document: mdoc, concurrencyControl: .lastWriteWins)
        }
        
        // delete functions
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.delete(document: doc)
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.delete(document: doc, concurrencyControl: .lastWriteWins)
        }
        
        // purge functions
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.purge(document: doc)
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.purge(id: "doc2")
        }
        
        // doc expiry
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.setDocumentExpiration(id: "doc6", expiration: Date())
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.getDocumentExpiration(id: "doc6")
        }
        
        // indexes
        let config = ValueIndexConfiguration.init(["firstName"])
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.createIndex(withName: "index1", config: config)
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.indexes()
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try col.deleteIndex(forName: "index2")
        }
    }
    
    // MARK: 8.7 Use Scope APIs on deleted/closed scenarios
    
    func testUseScopeWhenDatabaseIsClosed() throws {
        try testUseInvalidScope() {
            try self.db.close()
        }
    }
    
    func testUseScopeWhenDatabaseIsDeleted() throws {
        try testUseInvalidScope() {
            try self.db.delete()
        }
    }
    
    func testUseInvalidScope(_ onAction: () throws -> Void) throws {
        let colA = try self.db.createCollection(name: "colA")
        let scope = colA.scope
        
        try onAction()
        
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try scope.collection(name: "colA")
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try scope.collections()
        }
    }
    
    // MARK: 8.8 Get Scopes/Collections
    
    func testGetScopesOrCollectionsWhenDatabaseIsClosed() throws {
        try self.db.close()
        
        try getScopesOrCollectionsTest()
    }
    
    func testGetScopesOrCollectionsWhenDatabaseIsDeleted() throws {
        try self.db.delete()
        
        try getScopesOrCollectionsTest()
    }
    
    func getScopesOrCollectionsTest() throws {
        // default collection/scope
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try self.db.defaultCollection()
        }
        
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try self.db.defaultScope()
        }
        
        // collection(s)
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try self.db.collection(name: "colA", scope: "scopeA")
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try self.db.collections()
        }
        
        // scope(s)
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try self.db.scope(name: "scopeA")
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try self.db.scopes()
        }
        
        // create/delete collections
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try self.db.createCollection(name: "colA", scope: "scopeA")
        }
        expectError(domain: CBLErrorDomain, code: CBLError.notOpen) {
            let _ = try self.db.deleteCollection(name: "colA", scope: "scopeA")
        }
    }
    
    /// Note: 8.9 Default collection deleted test: Can't test, since it will return fatalError
    
    // MARK: 8.10 all collections deleted under scope
    
    func testUseScopeAPIAfterDeletingAllCollections() throws {
        try testUseScopeAPIAfterDeletingAllCollectionsFrom(self.db)
    }
    
    func testUseScopeAPIAfterDeletingAllCollectionsFromDifferentDBInstance() throws {
        let db2 = try openDB(name: databaseName)
        
        try testUseScopeAPIAfterDeletingAllCollectionsFrom(db2)
    }
    
    func testUseScopeAPIAfterDeletingAllCollectionsFrom(_ db: Database) throws {
        let col = try self.db.createCollection(name: "colA", scope: "scopeA")
        
        let scope = col.scope
        
        try self.db.deleteCollection(name: "colA", scope: "scopeA")
        
        XCTAssertNil(try scope.collection(name: "colA"))
        XCTAssertEqual(try scope.collections().count, 0)
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
