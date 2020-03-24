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
    
    func validatePendingDocumentIDs(_ docIds: Set<String>,
                                    config rConfig: ReplicatorConfiguration? = nil) {
        var replConfig: ReplicatorConfiguration!
        if rConfig != nil {
            replConfig = rConfig
        } else {
            replConfig = config(target: DatabaseEndpoint(database: oDB),
                                type: .push, continuous: false)
        }
        
        var replicator: Replicator!
        var token: ListenerToken!
        run(config: replConfig, reset: false, expectedError: nil) { (r) in
            replicator = r
            
            // verify before starting the replicator
            XCTAssertEqual(try! replicator.pendingDocumentIds(), docIds)
            XCTAssertEqual(try! replicator.pendingDocumentIds().count, docIds.count)
            
            token = r.addChangeListener({ (change) in
                let pDocIds = try! replicator.pendingDocumentIds()
                
                if change.status.activity == .connecting {
                    XCTAssertEqual(pDocIds, docIds)
                    XCTAssertEqual(pDocIds.count, docIds.count)
                } else if change.status.activity == .stopped {
                    XCTAssertEqual(pDocIds.count, 0)
                }
            })
        }
        
        replicator.removeChangeListener(withToken: token)
    }
    
    /// expected: [docId: isPresent] e.g., @{"doc-1": true, "doc-2": false, "doc-3": false}
    func validateIsDocumentPending(_ expected: [String: Bool],
                                   config rConfig: ReplicatorConfiguration? = nil) throws {
        var replConfig: ReplicatorConfiguration!
        if rConfig != nil {
            replConfig = rConfig
        } else {
            replConfig = config(target: DatabaseEndpoint(database: oDB),
                                type: .push, continuous: false)
        }
        
        var replicator: Replicator!
        var token: ListenerToken!
        run(config: replConfig, reset: false, expectedError: nil) { (r) in
            replicator = r
            
            // verify before starting the replicator
            for (docId, present) in expected {
                XCTAssertEqual(try! r.isDocumentPending(docId), present)
            }
            
            token = r.addChangeListener({ (change) in
                if change.status.activity == .connecting {
                    for (docId, present) in expected {
                        XCTAssertEqual(try! r.isDocumentPending(docId), present)
                    }
                } else if change.status.activity == .stopped {
                    for (docId, _) in expected {
                        XCTAssertEqual(try! r.isDocumentPending(docId), false)
                    }
                }
            })
        }
        
        replicator.removeChangeListener(withToken: token)
    }
    
    // MARK: Unit Tests
    func testPendingDocIDsPullOnlyException() throws {
        let target = DatabaseEndpoint(database: oDB)
        let replConfig = config(target: target, type: .pull, continuous: false)
        
        var replicator: Replicator!
        var token: ListenerToken!
        var pullOnlyError: NSError!
        run(config: replConfig, reset: false, expectedError: nil) { (r) in
            replicator = r
            
            token = r.addChangeListener({ (change) in
                if change.status.activity == .connecting {
                    self.ignoreException {
                        do {
                            let _ = try replicator.pendingDocumentIds()
                        } catch {
                            pullOnlyError = error as NSError
                        }
                    }
                }
            })
        }
        
        XCTAssertEqual(pullOnlyError.code, CBLErrorUnsupported)
        replicator.removeChangeListener(withToken: token)
    }
    
    func testPendingDocIDsWithCreate() throws {
        let docIds = try createDocs()
        validatePendingDocumentIDs(docIds)
    }
    
    func testPendingDocIDsWithUpdate() throws {
        let _ = try createDocs()
        
        let target = DatabaseEndpoint(database: oDB)
        let replConfig = config(target: target, type: .push, continuous: false)
        run(config: replConfig, expectedError: nil)
        
        let updatedIds: Set = ["doc-2", "doc-4"]
        for docId in updatedIds {
            let doc = db.document(withID: docId)!.toMutable()
            doc.setString(kUpdateActionValue, forKey: kActionKey)
            try saveDocument(doc)
        }
        
        validatePendingDocumentIDs(updatedIds)
    }
    
    func testPendingDocIdsWithDelete() throws {
        let _ = try createDocs()
        
        let target = DatabaseEndpoint(database: oDB)
        let replConfig = config(target: target, type: .push, continuous: false)
        run(config: replConfig, expectedError: nil)
        
        let deletedIds: Set = ["doc-2", "doc-4"]
        for docId in deletedIds {
            let doc = db.document(withID: docId)!
            try db.deleteDocument(doc)
        }
        
        validatePendingDocumentIDs(deletedIds)
    }
    
    func testPendingDocIdsWithPurge() throws {
        var docs = try createDocs()
        
        try db.purgeDocument(withID: "doc-3")
        docs.remove("doc-3")
        
        validatePendingDocumentIDs(docs)
    }
    
    func testPendingDocIdsWithFilter() throws {
        let _ = try createDocs()
        
        let target = DatabaseEndpoint(database: oDB)
        let replConfig = config(target: target, type: .push, continuous: false)
        replConfig.pushFilter = { (doc, flags) -> Bool in
            return doc.id == "doc-3"
        }
        
        validatePendingDocumentIDs(["doc-3"], config: replConfig)
    }
    
    // MARK: isDocumentPending
    
    func testIsDocumentPendingPullOnlyException() throws {
        let target = DatabaseEndpoint(database: oDB)
        let replConfig = config(target: target, type: .pull, continuous: false)
        
        var replicator: Replicator!
        var token: ListenerToken!
        var pullOnlyError: NSError!
        run(config: replConfig, reset: false, expectedError: nil) { (r) in
            replicator = r
            
            token = r.addChangeListener({ (change) in
                if change.status.activity == .connecting {
                    self.ignoreException {
                        do {
                            let _ = try replicator.isDocumentPending("doc-1")
                        } catch {
                            pullOnlyError = error as NSError
                        }
                    }
                }
            })
        }
        
        XCTAssertEqual(pullOnlyError.code, CBLErrorUnsupported)
        replicator.removeChangeListener(withToken: token)
    }
    
    func testIsDocumentPendingWithCreate() throws {
        noOfDocument = 2
        let _ = try createDocs()
        
        try validateIsDocumentPending(["doc-0": true, "doc-1": true, "doc-3": false])
    }
    
    func testIsDocumentPendingWithUpdate() throws {
        let _ = try createDocs()
        
        let target = DatabaseEndpoint(database: oDB)
        let replConfig = config(target: target, type: .push, continuous: false)
        run(config: replConfig, expectedError: nil)
        
        let updatedIds: Set = ["doc-2", "doc-4"]
        for docId in updatedIds {
            let doc = db.document(withID: docId)!.toMutable()
            doc.setString(kUpdateActionValue, forKey: kActionKey)
            try saveDocument(doc)
        }
        
        try validateIsDocumentPending(["doc-2": true, "doc-4": true, "doc-1": false])
    }
    
    func testIsDocumentPendingWithDelete() throws {
        let _ = try createDocs()
        
        let target = DatabaseEndpoint(database: oDB)
        let replConfig = config(target: target, type: .push, continuous: false)
        run(config: replConfig, expectedError: nil)
        
        let deletedIds: Set = ["doc-2", "doc-4"]
        for docId in deletedIds {
            let doc = db.document(withID: docId)!
            try db.deleteDocument(doc)
        }
        
        try validateIsDocumentPending(["doc-2": true, "doc-4": true, "doc-1": false])
    }
    
    func testIsDocumentPendingWithPurge() throws {
        noOfDocument = 3
        let _ = try createDocs()
        
        try db.purgeDocument(withID: "doc-1")
        
        try validateIsDocumentPending(["doc-0": true, "doc-1": false, "doc-2": true])
    }
    
    func testIsDocumentPendingWithPushFilter() throws {
        let _ = try createDocs()
        
        let target = DatabaseEndpoint(database: oDB)
        let replConfig = config(target: target, type: .push, continuous: false)
        replConfig.pushFilter = { (doc, flags) -> Bool in
            return doc.id == "doc-3"
        }
    
        try validateIsDocumentPending(["doc-3": true, "doc-1": false], config: replConfig)
    }
}
