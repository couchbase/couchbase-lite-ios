//
//  ReplicatorTest+CustomConflict.swift
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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

class ReplicatorTest_CustomConflict: ReplicatorTest {
    
    func testConflictResolverConfigProperty() {
        let target = URLEndpoint(url: URL(string: "wss://foo")!)
        let pullConfig = config(target: target, type: .pull, continuous: false)
        
        let conflictResolver = TestConflictResolver { (con) -> Document? in
            return con.remoteDocument
        }
        pullConfig.conflictResolver = conflictResolver
        repl = Replicator(config: pullConfig)
        
        XCTAssertNotNil(pullConfig.conflictResolver)
        XCTAssertNotNil(repl.config.conflictResolver)
    }
    
    #if COUCHBASE_ENTERPRISE
    
    func getConfig(_ type: ReplicatorType) -> ReplicatorConfiguration {
        let target = DatabaseEndpoint(database: oDB)
        return config(target: target, type: type, continuous: false)
    }
    
    func makeConflict(forID docID: String,
                      withLocal localData: [String: Any]?,
                      withRemote remoteData: [String: Any]?) throws {
        // create doc
        let doc = createDocument(docID)
        try saveDocument(doc)
        
        // sync the doc in both DBs.
        let config = getConfig(.push)
        run(config: config, expectedError: nil)
        
        // Now make different changes in db and oDBs
        if let data = localData {
            let doc1a = db.document(withID: docID)!.toMutable()
            doc1a.setData(data)
            try saveDocument(doc1a)
        } else {
            try db.deleteDocument(db.document(withID: docID)!)
        }
        
        if let data = remoteData {
            let doc1b = oDB.document(withID: docID)!.toMutable()
            doc1b.setData(data)
            try oDB.saveDocument(doc1b)
        } else {
            try oDB.deleteDocument(oDB.document(withID: docID)!)
        }
    }
    
    func testConflictResolverRemoteWins() throws {
        let localData = ["name": "Hobbes"]
        let remoteData = ["pattern": "striped"]
        try makeConflict(forID: "doc", withLocal: localData, withRemote: remoteData)
        
        let config = getConfig(.pull)
        let resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.remoteDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(db.count, 1)
        XCTAssertEqual(resolver.winner!, db.document(withID: "doc")!)
        XCTAssert(db.document(withID: "doc")!.toDictionary() == remoteData)
    }
    
    func testConflictResolverLocalWins() throws {
        let localData = ["name": "Hobbes"]
        let remoteData = ["pattern": "striped"]
        try makeConflict(forID: "doc", withLocal: localData, withRemote: remoteData)
        
        let config = getConfig(.pull)
        let resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.localDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(db.count, 1)
        XCTAssertEqual(resolver.winner!, db.document(withID: "doc")!)
        XCTAssert(db.document(withID: "doc")!.toDictionary() == localData)
    }
    
    func testConflictResolverNullDoc() throws {
        let localData = ["name": "Hobbes"]
        let remoteData = ["pattern": "striped"]
        try makeConflict(forID: "doc", withLocal: localData, withRemote: remoteData)
        
        let config = getConfig(.pull)
        let resolver = TestConflictResolver() { (conflict) -> Document? in
            return nil
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertNil(resolver.winner)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: "doc"))
    }
    
    func testConflictResolverDeletedLocalWins() throws {
        let remoteData = ["key2": "value2"]
        try makeConflict(forID: "doc", withLocal: nil, withRemote: remoteData)
        
        let config = getConfig(.pull)
        let resolver = TestConflictResolver() { (conflict) -> Document? in
            XCTAssertNil(conflict.localDocument)
            XCTAssertNotNil(conflict.remoteDocument)
            return nil
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertNil(resolver.winner)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: "doc"))
    }
    
    func testConflictResolverDeletedRemoteWins() throws {
        let localData = ["key1": "value1"]
        try makeConflict(forID: "doc", withLocal: localData, withRemote: nil)
        
        let config = getConfig(.pull)
        let resolver = TestConflictResolver() { (conflict) -> Document? in
            XCTAssertNotNil(conflict.localDocument)
            XCTAssertNil(conflict.remoteDocument)
            return nil
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertNil(resolver.winner)
        XCTAssertEqual(db.count, 0)
        XCTAssertNil(db.document(withID: "doc"))
    }
    
    func testConflictResolverCalledTwice() throws {
        let docID = "doc"
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        let config = getConfig(.pull)
        
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        var count = 0;
        let resolver = TestConflictResolver() { [unowned self] (conflict) -> Document? in
            count += 1
            
            // update the doc will cause a second conflict
            let savedDoc = self.db.document(withID: docID)!.toMutable()
            if !savedDoc["secondUpdate"].exists {
                savedDoc.setBoolean(true, forKey: "secondUpdate")
                try! self.db.saveDocument(savedDoc)
            }
            
            let mDoc = conflict.localDocument!.toMutable()
            mDoc.setString("local", forKey: "edit")
            return mDoc
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(count, 2)
        XCTAssertEqual(self.db.count, 1)
        var expectedDocDict: [String: Any] = localData
        expectedDocDict["edit"] = "local"
        expectedDocDict["secondUpdate"] = true
        XCTAssert(self.db.document(withID: docID)!.toDictionary() == expectedDocDict)
    }
    
    func testConflictResolverMergeDoc() throws {
        let docID = "doc"
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        var resolver: TestConflictResolver!
        let config = getConfig(.pull)
        
        // EDIT LOCAL DOCUMENT
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict: Conflict) -> Document? in
            let doc = conflict.localDocument?.toMutable()
            doc?.setString("local", forKey: "edit")
            return doc
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        var expectedDocDict = localData
        expectedDocDict["edit"] = "local"
        XCTAssert(expectedDocDict == db.document(withID: docID)!.toDictionary())
        
        // EDIT REMOTE DOCUMENT
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict: Conflict) -> Document? in
            let doc = conflict.remoteDocument?.toMutable()
            doc?.setString("remote", forKey: "edit")
            return doc
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        expectedDocDict = remoteData
        expectedDocDict["edit"] = "remote"
        XCTAssert(expectedDocDict == db.document(withID: docID)!.toDictionary())
        
        // CREATE NEW DOCUMENT
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict: Conflict) -> Document? in
            let doc = MutableDocument(id: conflict.localDocument!.id)
            doc.setString("new-with-same-ID", forKey: "docType")
            return doc
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssert(["docType": "new-with-same-ID"] == db.document(withID: docID)!.toDictionary())
    }
    
    func testDocumentReplicationEventForConflictedDocs() throws {
        var resolver: TestConflictResolver!
        
        // when resolution is skipped: here doc from oDB throws an exception & skips it
        resolver = TestConflictResolver() { [unowned self] (conflict) -> Document? in
            return self.oDB.document(withID: "doc")
        }
        ignoreException {
            try self.validateDocumentReplicationEventForConflictedDocs(resolver)
        }
        
        // when resolution is successfull but wrong docID
        resolver = TestConflictResolver() { (conflict) -> Document? in
            return MutableDocument()
        }
        try validateDocumentReplicationEventForConflictedDocs(resolver)
        
        // when resolution is successfull.
        resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.remoteDocument
        }
        try validateDocumentReplicationEventForConflictedDocs(resolver)
    }
    
    func validateDocumentReplicationEventForConflictedDocs(_ resolver: TestConflictResolver) throws {
        let docID = "doc"
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        let config = getConfig(.pull)
        
        config.conflictResolver = resolver
        
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        
        var token: ListenerToken!
        var replicator: Replicator!
        var docIds = [String]()
        run(config: config, reset: false, expectedError: nil, onReplicatorReady: { (r) in
            replicator = r
            token = r.addDocumentReplicationListener({ (docRepl) in
                for doc in docRepl.documents {
                    docIds.append(doc.id)
                }
            })
        })
        
        // make sure only single listener event is fired when conflict occured.
        XCTAssertEqual(docIds.count, 1)
        XCTAssertEqual(docIds.first!, docID)
        replicator.removeChangeListener(withToken: token)
        
        // resolve any un-resolved conflict through pull replication.
        run(config: getConfig(.pull), expectedError: nil)
    }
    
    
    func testConflictResolverWrongDocID() throws {
        // use this to verify the logs generated during the conflict resolution.
        let customLogger = CustomLogger()
        customLogger.level = .warning
        Database.log.custom = customLogger
        
        let docID = "doc"
        let wrongDocID = "wrong-doc-id"
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        let config = getConfig(.pull)
        var resolver: TestConflictResolver!
        
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            let mDoc = MutableDocument(id: wrongDocID)
            mDoc.setString("update", forKey: "edit")
            return mDoc
        }
        config.conflictResolver = resolver
        var token: ListenerToken!
        var replicator: Replicator!
        var docIds = Set<String>()
        run(config: config, reset: false, expectedError: nil, onReplicatorReady: {(repl) in
            replicator = repl
            token = repl.addDocumentReplicationListener()  { (docRepl) in
                if docRepl.documents.count != 0 {
                    XCTAssertEqual(docRepl.documents.count, 1)
                    docIds.insert(docRepl.documents.first!.id)
                }
                
                // shouldn't report an error from replicator
                XCTAssertNil(docRepl.documents.first?.error)
            }
        })
        replicator.removeChangeListener(withToken: token)
        
        // validate wrong doc-id is resolved successfully
        XCTAssertEqual(db.count, 1)
        XCTAssert(docIds.contains(docID))
        XCTAssert(db.document(withID: docID)!.toDictionary() == ["edit": "update"])
        
        // validate the warning log
        XCTAssertEqual(customLogger.lines.last,
                       "The document ID of the resolved document '\(wrongDocID)' is not matching " +
            "with the document ID of the conflicting document '\(docID)'.")
    }
    
    func testConflictResolverDifferentDBDoc() throws {
        let docID = "doc"
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        let config = getConfig(.pull)
        var resolver: TestConflictResolver!
        
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { [unowned self] (conflict) -> Document? in
            return self.oDB.document(withID: docID) // doc from different DB!!
        }
        config.conflictResolver = resolver
        var token: ListenerToken!
        var replicator: Replicator!
        var error: NSError!
        
        ignoreException {
            self.run(config: config, reset: false, expectedError: nil, onReplicatorReady: {(repl) in
                replicator = repl
                token = repl.addDocumentReplicationListener({ (docRepl) in
                    if let err = docRepl.documents.first?.error as NSError? {
                        error = err
                    }
                })
            })
        }
        XCTAssertNotNil(error)
        XCTAssertEqual(error.code, CBLErrorConflict)
        XCTAssertEqual(error.domain, CBLErrorDomain)
        
        replicator.removeChangeListener(withToken: token)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.remoteDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        XCTAssert(db.document(withID: docID)!.toDictionary() == remoteData)
    }
    
    /// disabling since, exceptions inside conflict handler will leak, since objc doesn't perform release
    /// when exception happens
    func _testConflictResolverThrowingException() throws {
        let docID = "doc"
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        let config = getConfig(.pull)
        var resolver: TestConflictResolver!
        
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            NSException(name: .internalInconsistencyException,
                        reason: "some exception happened inside custom conflict resolution",
                        userInfo: nil).raise()
            return nil
        }
        config.conflictResolver = resolver
        var token: ListenerToken!
        var replicator: Replicator!
        var error: NSError?
        
        ignoreException {
            self.run(config: config, reset: false, expectedError: nil, onReplicatorReady: {(repl) in
                replicator = repl
                token = repl.addDocumentReplicationListener({ (docRepl) in
                    if let err = docRepl.documents.first?.error as NSError? {
                        error = err
                        XCTAssertEqual(err.code, CBLErrorConflict)
                        XCTAssertEqual(err.domain, CBLErrorDomain)
                    }
                })
            })
        }
        
        XCTAssertNotNil(error)
        replicator.removeChangeListener(withToken: token)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.remoteDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        XCTAssert(db.document(withID: docID)!.toDictionary() == remoteData)
    }
    
    func testConflictResolutionDefault() throws {
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        
        // higher generation-id
        var docID = "doc1"
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        var doc = db.document(withID: docID)!.toMutable()
        doc.setString("value3", forKey: "key3")
        try saveDocument(doc)
        
        // delete local
        docID = "doc2"
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        try db.deleteDocument(db.document(withID: docID)!)
        doc = oDB.document(withID: docID)!.toMutable()
        doc.setString("value3", forKey: "key3")
        try oDB.saveDocument(doc)
        
        // delete remote
        docID = "doc3"
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        doc = db.document(withID: docID)!.toMutable()
        doc.setString("value3", forKey: "key3")
        try db.saveDocument(doc)
        try oDB.deleteDocument(oDB.document(withID: docID)!)
        
        // delete local but higher remote generation
        docID = "doc4"
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        try db.deleteDocument(db.document(withID: docID)!)
        doc = oDB.document(withID: docID)!.toMutable()
        doc.setString("value3", forKey: "key3")
        try oDB.saveDocument(doc)
        doc = oDB.document(withID: docID)!.toMutable()
        doc.setString("value4", forKey: "key4")
        try oDB.saveDocument(doc)
        
        let config = getConfig(.pull)
        config.conflictResolver = ConflictResolver.default
        run(config: config, expectedError: nil)
        
        // validate saved doc includes the key3, which is the highest generation.
        XCTAssertEqual(db.document(withID: "doc1")?.string(forKey: "key3"), "value3")
        
        // validates the deleted doc is choosen for its counterpart doc which saved
        XCTAssertNil(db.document(withID: "doc2"))
        XCTAssertNil(db.document(withID: "doc3"))
        
        // validates the deleted doc is choosen without considering the genaration.
        XCTAssertNil(db.document(withID: "doc4"))
    }
    
    func testConflictResolverReturningBlob() throws {
        let docID = "doc"
        let content = "I am a blob".data(using: .utf8)!
        var blob = Blob(contentType: "text/plain", data: content)
        
        let config = getConfig(.pull)
        var resolver: TestConflictResolver!
        
        // RESOLVE WITH REMOTE and BLOB data in LOCAL
        var localData: [String: Any] = ["key1": "value1", "blob": blob]
        var remoteData: [String: Any] = ["key2": "value2"]
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.remoteDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertNil(db.document(withID: docID)?.blob(forKey: "blob"))
        XCTAssert(db.document(withID: docID)!.toDictionary() == remoteData)
        
        // RESOLVE WITH LOCAL with BLOB data
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.localDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(db.document(withID: docID)?.blob(forKey: "blob"), blob)
        XCTAssertEqual(db.document(withID: docID)?.string(forKey: "key1"), "value1")
        
        // RESOLVE WITH LOCAL and BLOB data in REMOTE
        blob = Blob(contentType: "text/plain", data: content)
        localData = ["key1": "value1"]
        remoteData = ["key2": "value2", "blob": blob]
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.localDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertNil(db.document(withID: docID)?.blob(forKey: "blob"))
        XCTAssert(db.document(withID: docID)!.toDictionary() == localData)
        
        // RESOLVE WITH REMOTE with BLOB data
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            return conflict.remoteDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(db.document(withID: docID)?.blob(forKey: "blob"), blob)
        XCTAssertEqual(db.document(withID: docID)?.string(forKey: "key2"), "value2")
    }
    
    func testConflictResolverReturningBlobFromDifferentDB() throws {
        let docID = "doc"
        let content = "I am a blob".data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        let localData: [String: Any] = ["key1": "value1"]
        let remoteData: [String: Any] = ["key2": "value2", "blob": blob]
        let config = getConfig(.pull)
        var resolver: TestConflictResolver!
        
        // using remote document blob is okay to use!
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            let mDoc = conflict.localDocument?.toMutable()
            mDoc?.setBlob(conflict.remoteDocument?.blob(forKey: "blob"), forKey: "blob")
            return mDoc
        }
        config.conflictResolver = resolver
        var token: ListenerToken!
        var replicator: Replicator!
        run(config: config, reset: false, expectedError: nil, onReplicatorReady: {(repl) in
            replicator = repl
            token = repl.addDocumentReplicationListener({ (docRepl) in
                XCTAssertNil(docRepl.documents.first?.error)
            })
        })
        replicator.removeChangeListener(withToken: token)
        
        // using blob from remote document of user's- which is a different database
        let oDBDoc = oDB.document(withID: docID)!
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            let mDoc = conflict.localDocument?.toMutable()
            mDoc?.setBlob(oDBDoc.blob(forKey: "blob"), forKey: "blob")
            return mDoc
        }
        config.conflictResolver = resolver
        var error: NSError? = nil
        ignoreException {
            self.run(config: config, reset: false, expectedError: nil, onReplicatorReady: {(repl) in
                replicator = repl
                token = repl.addDocumentReplicationListener({ (docRepl) in
                    if let err = docRepl.documents.first?.error as NSError? {
                        error = err
                    }
                })
            })
        }
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, CBLErrorUnexpectedError)
        XCTAssert((error?.userInfo[NSLocalizedDescriptionKey] as! String) ==
            "A document contains a blob that was saved to a different " +
            "database. The save operation cannot complete.")
        replicator.removeChangeListener(withToken: token)
    }
    
    func testNonBlockingDatabaseOperationConflictResolver() throws {
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        let config = getConfig(.pull)
        var resolver: TestConflictResolver!
        try makeConflict(forID: "doc1", withLocal: localData, withRemote: remoteData)
        
        var count = 0;
        resolver = TestConflictResolver() { (conflict) -> Document? in
            count += 1
            
            let timestamp = "\(Date())"
            let mDoc = self.createDocument("doc2", data: ["timestamp": timestamp])
            XCTAssertNotNil(mDoc)
            XCTAssert(try! self.db.saveDocument(mDoc, concurrencyControl: .failOnConflict))
            
            let doc2 = self.db.document(withID: "doc2")
            XCTAssertNotNil(doc2)
            XCTAssertEqual(doc2?.string(forKey: "timestamp"), timestamp)
            return conflict.remoteDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        XCTAssertEqual(count, 1) // make sure, it entered the conflict resolver
    }
    
    func testNonBlockingConflictResolver() throws {
        let expectation = XCTestExpectation(description: "testNonBlockingConflictResolver")
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        try makeConflict(forID: "doc1", withLocal: localData, withRemote: remoteData)
        try makeConflict(forID: "doc2", withLocal: localData, withRemote: remoteData)
        
        let config = getConfig(.pull)
        var resolver: TestConflictResolver!
        var order = [String]()
        resolver = TestConflictResolver() { (conflict) -> Document? in
            order.append(conflict.documentID)
            
            if order.count == 1 {
                Thread.sleep(forTimeInterval: 0.5)
            }
            
            order.append(conflict.documentID)
            if order.count == 4 {
                expectation.fulfill()
            }
            
            return conflict.remoteDocument
        }
        config.conflictResolver = resolver
        run(config: config, expectedError: nil)
        
        wait(for: [expectation], timeout: 5.0)
        
        // make sure, first doc starts resolution but finishes last.
        // in between second doc starts and finishes it.
        XCTAssertEqual(order.first, order.last)
        XCTAssertEqual(order[1], order[2])
    }
    
    func testConflictResolverWhenDocumentIsPurged() throws {
        let docID = "doc"
        let localData = ["key1": "value1"]
        let remoteData = ["key2": "value2"]
        let config = getConfig(.pull)
        var resolver: TestConflictResolver!
        
        try makeConflict(forID: docID, withLocal: localData, withRemote: remoteData)
        resolver = TestConflictResolver() { (conflict) -> Document? in
            try! self.db.purgeDocument(withID: conflict.documentID)
            return conflict.remoteDocument
        }
        config.conflictResolver = resolver
        var error: NSError? = nil
        var replicator: Replicator!
        var token: ListenerToken!
        self.run(config: config, reset: false, expectedError: nil, onReplicatorReady: {(repl) in
            replicator = repl
            token = repl.addDocumentReplicationListener({ (docRepl) in
                if let err = docRepl.documents.first?.error as NSError? {
                    error = err
                }
            })
        })
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, CBLErrorNotFound)
        replicator.removeChangeListener(withToken: token)
    }
    
    #endif
    
}


class TestConflictResolver: ConflictResolverProtocol {
    
    var winner: Document? = nil
    let _resolver: (Conflict) -> Document?
    
    // set this resolver, which will be used while resolving the conflict
    init(_ resolver: @escaping (Conflict) -> Document?) {
        _resolver = resolver
    }
    
    func resolve(conflict: Conflict) -> Document? {
        winner = _resolver(conflict)
        return winner
    }
    
}
