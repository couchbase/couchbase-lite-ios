//
//  ReplicatorTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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


class ReplicatorTest: CBLTestCase {
    var otherDB: Database!
    
    override func setUp() {
        super.setUp()
        otherDB = try! openDB(name: "otherdb")
        XCTAssertNotNil(otherDB)
    }
    
    override func tearDown() {
        try! otherDB.close()
        super.tearDown()
    }
    
    func run(type: ReplicatorType, target: Endpoint, expectedError: Int?) {
        let config = ReplicatorConfiguration(database: self.db, target: target)
        config.replicatorType = type
        run(config: config, expectedError: expectedError)
    }
    
    func run(config: ReplicatorConfiguration, expectedError: Int?) {
        let x = self.expectation(description: "change")
        let repl = Replicator(config: config)
        let token = repl.addChangeListener { (change) in
            let status = change.status
            if status.activity == .stopped {
                if let err = expectedError {
                    let error = status.error as NSError?
                    XCTAssertNotNil(error)
                    XCTAssertEqual(error!.code, err)
                }
                x.fulfill()
            }
        }
        
        repl.start()
        wait(for: [x], timeout: 5.0)
        repl.removeChangeListener(withToken: token)
    }

    #if COUCHBASE_ENTERPRISE
    func testEmptyPush() {
        let target = DatabaseEndpoint(database: otherDB)
        run(type: .push, target: target, expectedError: nil)
    }
    #endif
}
