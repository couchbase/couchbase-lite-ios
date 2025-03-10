//
//  PublisherTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Combine
import XCTest
@testable import CouchbaseLiteSwift

@available(iOS 13.0, *)
class PublisherTest: CBLTestCase {
    
    var cancellables = Set<AnyCancellable>()
    var replicator: Replicator?
    
    override func setUp() {
        super.setUp()
        try! openOtherDB()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }
    
    func testCollectionChangePublisher() throws {
        let expect = self.expectation(description: "Collection changed")
        expect.expectedFulfillmentCount = 2

        defaultCollection!.changePublisher()
            .sink { change in
                XCTAssert(change.documentIDs.first == "doc1")
                expect.fulfill()
            }
            .store(in: &cancellables)

        // it also saves the document into the db
        let doc = try generateDocument(withID: "doc1")
        
        try defaultCollection!.save(document: doc)
        XCTAssert(cancellables.count == 1)
        waitForExpectations(timeout: 10.0)
    }
    
    func testCollectionDocumentChangePublisher() throws {
        let expect = self.expectation(description: "Document changed")
        expect.expectedFulfillmentCount = 2

        defaultCollection!.documentChangePublisher(for: "doc1")
            .sink { change in
                XCTAssert(change.documentID == "doc1")
                expect.fulfill()
            }
            .store(in: &cancellables)

        // it also saves the document into the db
        let doc = try generateDocument(withID: "doc1")
        
        try defaultCollection!.save(document: doc)
        XCTAssert(cancellables.count == 1)
        waitForExpectations(timeout: 10.0)
    }
    
#if COUCHBASE_ENTERPRISE
    func testReplicatorChangePublisher() throws {
        // Replicator will go through a minimum of 3 states: connecting, busy, stopped. Will only then fulfill.
        var activity: Set<Replicator.ActivityLevel> = []
        let expect = self.expectation(description: "Replicator changed")
        
        try createDocNumbered(defaultCollection!, start: 0, num: 10)
        
        let target = DatabaseEndpoint(database: otherDB!)
        var config = ReplicatorConfiguration(target: target)
        config.replicatorType = .push
        config.addCollection(defaultCollection!)
        let replicator = Replicator(config: config)
        
        replicator.changePublisher()
            .sink { change in
                let level = change.status.activity
                activity.insert(level)
                
                if activity.count == 3 {
                    expect.fulfill()
                }
            }
            .store(in: &cancellables)
        
        self.replicator = replicator
        replicator.start()
        
        XCTAssert(cancellables.count == 1)
        waitForExpectations(timeout: 10.0)
    }
    
    func testReplicatorDocumentPublisher() throws {
        let expect = self.expectation(description: "Documents replicated")
        try createDocNumbered(defaultCollection!, start: 0, num: 10)
        
        let target = DatabaseEndpoint(database: otherDB!)
        var config = ReplicatorConfiguration(target: target)
        config.replicatorType = .push
        config.addCollection(defaultCollection!)
        let replicator = Replicator(config: config)
        
        replicator.documentReplicationPublisher()
            .first()
            .sink { change in
                XCTAssert(change.documents.count == 10)
                expect.fulfill()
            }
            .store(in: &cancellables)
        
        replicator.start()
        
        XCTAssert(cancellables.count == 1)
        waitForExpectations(timeout: 10.0)
    }
#endif
}
