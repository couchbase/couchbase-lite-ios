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
    
    var cancellable: AnyCancellable?
    
    func testCollectionPublisherAddsListener() throws {
        let expectation = self.expectation(description: "Got the change")
        
        cancellable = defaultCollection!.changePublisher()
            .sink { change in
                XCTAssertFalse(change.documentIDs.isEmpty, "THE change")
                expectation.fulfill()
        }

        let doc = MutableDocument(id: "doc1")
        try defaultCollection!.save(document: doc)

        wait(for: [expectation], timeout: 2.0)
    }
            
    func testCollectionChangePublisherRemovesListener() throws {
        cancellable = defaultCollection!.changePublisher()
            .sink { _ in }
        XCTAssertNotNil(cancellable)
        cancellable = nil
    }
    
    func testDocumentPublisherAddsListener() throws {
        let expectation = self.expectation(description: "Got the change")
        
        cancellable = defaultCollection!.documentChangePublisher(for: "doc1")
            .sink { change in
                XCTAssertEqual(change.documentID, "doc1")
                expectation.fulfill()
        }

        let doc = MutableDocument(id: "doc1")
        try defaultCollection!.save(document: doc)

        wait(for: [expectation], timeout: 2.0)
    }
            
    func testDocumentChangePublisherRemovesListener() throws {
        cancellable = defaultCollection!.documentChangePublisher(for: "doc1")
            .sink { _ in }
        XCTAssertNotNil(cancellable)
        cancellable = nil
    }
}
