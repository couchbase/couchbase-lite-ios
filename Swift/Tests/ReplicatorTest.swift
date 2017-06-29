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
    var otherDB: Database?
    
    override func setUp() {
        super.setUp()
        otherDB = try! openDB(name: "otherdb")
        XCTAssertNotNil(otherDB)
    }
    
    
    override func tearDown() {
        try! otherDB?.close()
        super.tearDown()
    }
    
    
    func run(push: Bool, pull: Bool, expectedError: Int?) {
        var config = ReplicatorConfiguration(database: db, targetDatabase: otherDB!)
        config.replicatorType = push && pull ? .pushAndPull : (push ? .push : .pull)
        run(config: config, expectedError: expectedError)
    }
    
    
    func run(push: Bool, pull: Bool, url: URL, expectedError: Int?) {
        var config = ReplicatorConfiguration(database: db, targetURL: url)
        config.replicatorType = push && pull ? .pushAndPull : (push ? .push : .pull)
        run(config: config, expectedError: expectedError)
    }
    
    
    func run(config: ReplicatorConfiguration, expectedError: Int?) {
        let x = self.expectation(description: "change")
        let repl = Replicator(config: config);
        let listener = repl.addChangeListener({ (change) in
            let status = change.status
            if status.activity == .stopped {
                if let err = expectedError {
                    let error = status.error as NSError?
                    XCTAssertNotNil(error)
                    XCTAssertEqual(error!.code, err)
                }
                x.fulfill()
            }
        })
        
        repl.start()
        wait(for: [x], timeout: 5.0)
        repl.removeChangeListener(listener)
    }
    
    
    func testEmptyPush() {
        run(push: true, pull: false, expectedError: nil)
    }
}
