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
    
    override func setUp() {
        super.setUp()
        try! openOtherDB()
    }
    
    func testCollectionPublishers() throws {
        let changeExpectation = self.expectation(description: "Change in collection")
        let documentExpectation = self.expectation(description: "Document changed")
        changeExpectation.expectedFulfillmentCount = 2
        changeExpectation.assertForOverFulfill = true
        documentExpectation.expectedFulfillmentCount = 2
        documentExpectation.assertForOverFulfill = true
        
        defaultCollection!.changePublisher()
            .sink { change in
                XCTAssertNotNil(try! self.defaultCollection!.document(id: "doc1"))
                changeExpectation.fulfill()
            }
            .store(in: &cancellables)

        defaultCollection!.documentChangePublisher(for: "doc1")
            .sink { change in
                XCTAssertNotNil(try! self.defaultCollection!.document(id: "doc1"))
                documentExpectation.fulfill()
            }
            .store(in: &cancellables)

        let doc = try generateDocument(withID: "doc1")
        try defaultCollection!.save(document: doc)
        XCTAssertNotNil(cancellables)
        wait(for: [changeExpectation, documentExpectation], timeout: 2.0)
        
        cancellables.removeAll()
        try defaultCollection!.save(document: doc)
    }
}
