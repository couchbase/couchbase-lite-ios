//
//  URLEndpointListenerTest+Collection.swift
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
@testable import CouchbaseLiteSwift

class URLEndpointListenerTest_Collection: URLEndpointListenerTest {
    override func setUpWithError() throws {
        try super.setUpWithError()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }
    
    func testCollectionsSingleShotPushPullReplication() throws {
        if !self.keyChainAccessAllowed { return }
        
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 3)
        try createDocNumbered(col1b, start: 10, num: 5)
        XCTAssertEqual(col1a.count, 3)
        XCTAssertEqual(col1b.count, 5)
        XCTAssertEqual(col2a.count, 0)
        XCTAssertEqual(col2b.count, 0)
        
        let config = URLEndpointListenerConfiguration(collections: [col2a, col2b])
        let listener = try startListener(withConfig: config)
        
        let collections = CollectionConfiguration.fromCollections([col1a, col1b])
        var rConfig = ReplicatorConfiguration(collections: collections, target: listener.localURLEndpoint)
        rConfig.pinnedServerCertificate = listener.tlsIdentity!.certs[0]
        
        run(config: rConfig, expectedError: nil)
        XCTAssertEqual(col1a.count, 3)
        XCTAssertEqual(col1b.count, 5)
        XCTAssertEqual(col2a.count, 3)
        XCTAssertEqual(col2b.count, 5)
        
        try stopListener()
    }
    
    func testCollectionsContinuousPushPullReplication() throws {
        if !self.keyChainAccessAllowed { return }
        
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col1b = try self.db.createCollection(name: "colB", scope: "scopeA")
        
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 10)
        try createDocNumbered(col1b, start: 10, num: 10)
        XCTAssertEqual(col1a.count, 10)
        XCTAssertEqual(col1b.count, 10)
        XCTAssertEqual(col2a.count, 0)
        XCTAssertEqual(col2b.count, 0)
        
        let config = URLEndpointListenerConfiguration(collections: [col2a, col2b])
        let listener = try startListener(withConfig: config)
        
        let collections = CollectionConfiguration.fromCollections([col1a, col1b])
        var rConfig = ReplicatorConfiguration(collections: collections, target: listener.localURLEndpoint)
        rConfig.continuous = true
        rConfig.pinnedServerCertificate = listener.tlsIdentity!.certs[0]
        
        run(config: rConfig, expectedError: nil)
        XCTAssertEqual(col1a.count, 10)
        XCTAssertEqual(col1b.count, 10)
        XCTAssertEqual(col2a.count, 10)
        XCTAssertEqual(col2b.count, 10)
        
        try stopListener()
    }
    
    func testMismatchedCollectionReplication() throws {
        if !self.keyChainAccessAllowed { return }
        
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col2b = try otherDB!.createCollection(name: "colB", scope: "scopeA")
        
        try createDocNumbered(col1a, start: 0, num: 10)
        
        let config = URLEndpointListenerConfiguration(collections: [col2b])
        let listener = try startListener(withConfig: config)
        
        let collections = CollectionConfiguration.fromCollections([col1a])
        var rConfig = ReplicatorConfiguration(collections: collections, target: listener.localURLEndpoint)
        rConfig.pinnedServerCertificate = listener.tlsIdentity!.certs[0]
        
        run(config: rConfig, expectedError: CBLError.httpNotFound)
        try stopListener()
    }
    
    func testCBL7347() throws {
        if !self.keyChainAccessAllowed { return }
        
        LogSinks.console = ConsoleLogSink(level: .info)
        
        let col1a = try self.db.createCollection(name: "colA", scope: "scopeA")
        let col2a = try otherDB!.createCollection(name: "colA", scope: "scopeA")
        
        let blobs = ["s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "l1", "l2", "l3"]
        var blobMap: [String: Data] = [:]
        
        let batchSize = 100
        let totalDocs = 10000
        for batchStart in stride(from: 0, to: totalDocs, by: batchSize) {
            try autoreleasepool {
                try col1a.database.inBatch {
                    let batchEnd = min(batchStart + batchSize, totalDocs)
                    NSLog("Saving : \(batchStart) ... \(batchEnd)")
                    for i in batchStart..<batchEnd {
                        let doc = MutableDocument(id: "doc-\(i)")
                        doc.setString("Document #\(i)", forKey: "name")
                        doc.setInt(i, forKey: "index")
                        doc.setDate(Date(), forKey: "createdAt")
                        
                        let count = Int.random(in: 1...3)
                        let chosenBlobs = blobs.shuffled().prefix(count)
                        
                        for (idx, blobName) in chosenBlobs.enumerated() {
                            var data = blobMap[blobName]
                            if data == nil {
                                data = try dataFromResource(name: "blobs/\(blobName)", ofType: "jpg")
                                blobMap[blobName] = data
                            }
                            if let data = data {
                                let blob = Blob(contentType: "image/jpeg", data: data)
                                doc.setBlob(blob, forKey: "image\(idx+1)")
                            }
                        }
                        
                        try col1a.save(document: doc)
                    }
                }
            }
        }
        
        NSLog("count : \(col1a.count)")
        
        let config = URLEndpointListenerConfiguration(collections: [col2a])
        let listener = try startListener(withConfig: config)
        
        let collections = CollectionConfiguration.fromCollections([col1a])
        var replicatorConfig = ReplicatorConfiguration(collections: collections, target: listener.localURLEndpoint)
        replicatorConfig.continuous = true
        replicatorConfig.pinnedServerCertificate = listener.tlsIdentity!.certs[0]
        
        let x = self.expectation(description: "stopped")

        let replicator = Replicator.init(config: replicatorConfig)
        _ = replicator.addChangeListener { (change) in
            let status = change.status
            if status.activity == .idle && status.progress.completed == status.progress.total {
                replicator.stop()
            }
            
            NSLog("\(status.progress.completed) / \(status.progress.total)")
            
            if (status.progress.completed > 40000) {
                replicator.stop()
            }
            
            if status.activity == .stopped {
                x.fulfill()
            }
        }
        
        replicator.start()
        wait(for: [x], timeout: 1000000)
        
        LogSinks.console = nil
    }
}
