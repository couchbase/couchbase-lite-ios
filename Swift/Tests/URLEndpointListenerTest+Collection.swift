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
@testable import CouchbaseLiteSwift_Private

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
        
        var rConfig = ReplicatorConfiguration(target: listener.localURLEndpoint)
        rConfig.pinnedServerCertificate = listener.tlsIdentity!.certs[0]
        rConfig.addCollections([col1a, col1b])
        
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
        
        var rConfig = ReplicatorConfiguration(target: listener.localURLEndpoint)
        rConfig.continuous = true
        rConfig.pinnedServerCertificate = listener.tlsIdentity!.certs[0]
        rConfig.addCollections([col1a, col1b])
        
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
        
        var rConfig = ReplicatorConfiguration(target: listener.localURLEndpoint)
        rConfig.pinnedServerCertificate = listener.tlsIdentity!.certs[0]
        rConfig.addCollections([col1a])
        
        run(config: rConfig, expectedError: CBLErrorHTTPNotFound)
        try stopListener()
    }
    
    // Note: testCreateListenerConfigWithEmptyCollection can't be tested due to fatalError
}
