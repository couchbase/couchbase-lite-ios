//
//  ReplicatorTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/26/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
        let config = ReplicatorConfiguration(withDatabase: self.db, target: target)
        config.replicatorType = type
        run(config: config, expectedError: expectedError)
    }
    
    func run(config: ReplicatorConfiguration, expectedError: Int?) {
        let x = self.expectation(description: "change")
        let repl = Replicator(withConfig: config)
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
    
    func testEmptyPush() {
        let target = DatabaseEndpoint(withDatabase: otherDB)
        run(type: .push, target: target, expectedError: nil)
    }
    
}
