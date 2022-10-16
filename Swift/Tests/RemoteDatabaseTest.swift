//
//  RemoteDatabaseTest.swift
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

final class RemoteDatabaseTest: URLEndpontListenerTest {
    var client: RemoteDatabase!

    override func setUpWithError() throws {
        try super.setUpWithError()
        
        timeout = 10.0
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }
    
    func start() throws {
        var config = URLEndpointListenerConfiguration(database: self.oDB)
        config.disableTLS = true
        config.allowConnectedClient = true
        let list = URLEndpointListener(config: config)
        try list.start()
        
        client = RemoteDatabase(url: list.localURL)
    }

    func testConnectedClient() throws {
        try start()
        
        let x = self.expectation(description: "Document receive")
        
        // create a doc in server (listener)
        let doc1 = MutableDocument(id: "doc-1")
        doc1.setString("someString", forKey: "someKeyString")
        try self.oDB.saveDocument(doc1)
        
        client.document(withID: "doc-1") { doc in
            
            guard let doc = doc else {
                XCTFail("Document not present")
                return
            }
            
            XCTAssertEqual(doc.id, "doc-1")
            XCTAssertEqual(doc.revisionID, "1-32a289db92b52a11cc4fe04216ada40c17296b45")
            XCTAssert(doc.toDictionary() == ["someKeyString": "someString"])
            
            x.fulfill()
        }
        
        wait(for: [x], timeout: timeout)
    }
    
    func testConnectedClientUnknownHostname() throws {
        let x = self.expectation(description: "Document receive")
        
        client = RemoteDatabase(url: URL(string: "ws://foo")!)
        
        client.document(withID: "doc-1") { doc in
            
            XCTAssertNil(doc)
            
            x.fulfill()
        }
        
        wait(for: [x], timeout: timeout)
    }
}
