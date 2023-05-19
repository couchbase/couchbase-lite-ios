//
//  ReplicatorTest+PendingDocIds.swift
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc All rights reserved.
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

class ReplicatorTest_PendingDocIds: ReplicatorTest {
    
    #if COUCHBASE_ENTERPRISE
    
    let kActionKey = "action-key"
    var noOfDocument = 5
    let kCreateActionValue = "doc-create"
    let kUpdateActionValue = "doc-update"
    
    // MARK: Helper methods
    
    /// create docs : [doc-1, doc-2, ...] upto `noOfDocument` docs.
    func createDocs() throws -> Set<String> {
        var docIds = Set<String>();
        for i in 0..<noOfDocument {
            let doc = createDocument("doc-\(i)")
            doc.setValue(kCreateActionValue, forKey: kActionKey)
            try saveDocument(doc)
            docIds.insert("doc-\(i)")
        }
        return docIds
    }
    
    func validatePendingDocumentIDs(_ docIds: Set<String>, pushOnlyDocIds: Set<String>? = nil) throws {
        var replConfig = config(target: DatabaseEndpoint(database: otherDB!), type: .push, continuous: false)
        var colConfig = CollectionConfiguration()
        if let pushOnlyDocIds = pushOnlyDocIds, pushOnlyDocIds.count > 0 {
            colConfig.pushFilter = { (doc, flags) -> Bool in
                return pushOnlyDocIds.contains(doc.id)
            }
        }
        replConfig.addCollection(defaultCollection!, config: colConfig)
        let replicator = Replicator(config: replConfig)
        
        // Check document pending:
        let defaultCollection = try self.db.defaultCollection()
        var pendingIds = try replicator.pendingDocumentIds(collection: defaultCollection)
        
        if let pushOnlyDocIds = pushOnlyDocIds, pushOnlyDocIds.count > 0 {
            XCTAssertEqual(pendingIds.count, pushOnlyDocIds.count)
        } else {
            XCTAssertEqual(pendingIds.count, docIds.count)
        }
        
        for docId in docIds {
            var willBePush = true
            if let pushOnlyDocIds = pushOnlyDocIds {
                willBePush = pushOnlyDocIds.contains(docId)
            }
            
            if willBePush {
                XCTAssertTrue(pendingIds.contains(docId))
                XCTAssertTrue(try replicator.isDocumentPending(docId, collection: defaultCollection))
            }
        }
        
        // Run replicator:
        run(replicator: replicator)
        
        // Check document pending:
        pendingIds = try replicator.pendingDocumentIds(collection: defaultCollection)
        XCTAssertEqual(pendingIds.count, 0)
        
        for docId in docIds {
            XCTAssertFalse(try replicator.isDocumentPending(docId, collection: defaultCollection))
        }
    }
    
    // MARK: Unit Tests
    
    func testPendingDocIDsPullOnlyException() throws {
        let target = DatabaseEndpoint(database: otherDB!)
        var replConfig = config(target: target, type: .pull, continuous: false)
        replConfig.addCollection(defaultCollection!)
        let replicator = Replicator(config: replConfig)
        
        var pullOnlyError: NSError? = nil
        do {
            let defaultCollection = try self.db.defaultCollection()
            let _ = try replicator.pendingDocumentIds(collection: defaultCollection)
        } catch {
            pullOnlyError = error as NSError
        }
        
        XCTAssertEqual(pullOnlyError?.code, CBLErrorUnsupported)
    }
    
    func testPendingDocIDsWithCreate() throws {
        let docIds = try createDocs()
        try validatePendingDocumentIDs(docIds)
    }
    
    func testPendingDocIDsWithUpdate() throws {
        let _ = try createDocs()
        
        let target = DatabaseEndpoint(database: otherDB!)
        var replConfig = config(target: target, type: .push, continuous: false)
        replConfig.addCollection(defaultCollection!)
        run(config: replConfig, expectedError: nil)
        
        let updatedIds: Set<String> = ["doc-2", "doc-4"]
        for docId in updatedIds {
            let defaultCollection = try self.db.defaultCollection()
            let doc = try defaultCollection.document(id: docId)!.toMutable()
            doc.setString(kUpdateActionValue, forKey: kActionKey)
            try saveDocument(doc, collection: defaultCollection)
        }
        
        try validatePendingDocumentIDs(updatedIds)
    }
    
    func testPendingDocIdsWithDelete() throws {
        let _ = try createDocs()
        
        let target = DatabaseEndpoint(database: otherDB!)
        var replConfig = config(target: target, type: .push, continuous: false)
        replConfig.addCollection(defaultCollection!)
        run(config: replConfig, expectedError: nil)
        
        let deletedIds: Set<String> = ["doc-2", "doc-4"]
        for docId in deletedIds {
            let doc = try defaultCollection!.document(id: docId)!
            try defaultCollection!.delete(document: doc)
        }
        
        try validatePendingDocumentIDs(deletedIds)
    }
    
    func testPendingDocIdsWithPurge() throws {
        var docs = try createDocs()
        
        let col = try self.db.defaultCollection()
        try col.purge(id: "doc-3")
        docs.remove("doc-3")
        
        try validatePendingDocumentIDs(docs)
    }
    
    func testPendingDocIdsWithFilter() throws {
        let docIds = try createDocs()
        
        let pushOnlyIds: Set<String> = ["doc-2", "doc-4"]
        try validatePendingDocumentIDs(docIds, pushOnlyDocIds: pushOnlyIds)
    }

    #endif
}
