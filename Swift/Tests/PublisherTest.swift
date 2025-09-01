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

        defaultCollection!.changePublisher()
            .sink { change in
                XCTAssert(change.documentIDs.first == "doc1")
                expect.fulfill()
            }
            .store(in: &cancellables)

        // it also saves the document into the db
        try generateDocument(withID: "doc1")
        
        XCTAssert(cancellables.count == 1)
        waitForExpectations(timeout: expTimeout)
    }
    
    func testCollectionDocumentChangePublisher() throws {
        let expect = self.expectation(description: "Document changed")

        defaultCollection!.documentChangePublisher(for: "doc1")
            .sink { change in
                XCTAssert(change.documentID == "doc1")
                expect.fulfill()
            }
            .store(in: &cancellables)

        // it also saves the document into the db
        try generateDocument(withID: "doc1")
        
        XCTAssert(cancellables.count == 1)
        waitForExpectations(timeout: expTimeout)
    }
    
#if COUCHBASE_ENTERPRISE
    func testReplicatorChangePublisher() throws {
        // Replicator will go through a minimum of 3 states: connecting, busy, stopped. Will only then fulfill.
        var activity: Set<Replicator.ActivityLevel> = []
        let expect = self.expectation(description: "Replicator changed")
        
        try createDocNumbered(defaultCollection!, start: 0, num: 10)
        
        let target = DatabaseEndpoint(database: otherDB!)
        let colConfig = CollectionConfiguration(collection: self.defaultCollection!)
        var config = ReplicatorConfiguration(collections: [colConfig], target: target)
        config.replicatorType = .push
        
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
        waitForExpectations(timeout: expTimeout)
    }
    
    func testReplicatorDocumentPublisher() throws {
        let expect = self.expectation(description: "Documents replicated")
        try createDocNumbered(defaultCollection!, start: 0, num: 10)
        
        let target = DatabaseEndpoint(database: otherDB!)
        let colConfig = CollectionConfiguration(collection: self.defaultCollection!)
        var config = ReplicatorConfiguration(collections: [colConfig], target: target)
        config.replicatorType = .push
        
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
        waitForExpectations(timeout: expTimeout)
    }
#endif
    
    func testQueryChangePublisher() throws {
        let expect1 = self.expectation(description: "10 rows")
        let expect2 = self.expectation(description: "11 rows")
        expect1.assertForOverFulfill = true
        expect2.assertForOverFulfill = true
        
        try createDocNumbered(defaultCollection!, start: 0, num: 10)
        let query = try self.db.createQuery("select * from _ where number1 < 10")
        
        query.changePublisher()
            .sink { change in
                XCTAssertNotNil(change.query)
                XCTAssertNil(change.error)
                let rows = Array(change.results!)

                switch rows.count {
                    case 10: expect1.fulfill()
                    case 11: expect2.fulfill()
                    default: XCTFail("Unexpected number of results: \(rows.count)")
                }
            }
            .store(in: &cancellables)
        
        XCTAssert(cancellables.count == 1)
        
        wait(for: [expect1], timeout: expTimeout)
        try createDocNumbered(defaultCollection!, start: -1, num: 10)
        
        wait(for: [expect2], timeout: expTimeout)
    }
}
