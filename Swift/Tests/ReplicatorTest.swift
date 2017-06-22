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
    var repl: Replicator?
    
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
        var config = ReplicatorConfiguration()
        config.database = db
        config.target = .database(otherDB!)
        config.replicatorType = push && pull ? .pushAndPull : (push ? .push : .pull)
        run(config: config, expectedError: expectedError)
    }
    
    
    func run(push: Bool, pull: Bool, url: URL, expectedError: Int?) {
        var config = ReplicatorConfiguration()
        config.database = db
        config.target = .url(url)
        config.replicatorType = push && pull ? .pushAndPull : (push ? .push : .pull)
        run(config: config, expectedError: expectedError)
    }
    
    
    func run(config: ReplicatorConfiguration, expectedError: Int?) {
        repl = Replicator(config: config);
        let x = self.expectation(forNotification: Notification.Name.ReplicatorChange.rawValue, object: repl!)
        { (n) -> Bool in
            let status = n.userInfo![ReplicatorStatusUserInfoKey] as! Replicator.Status
            if status.activity == .stopped {
                if let err = expectedError {
                    let error = n.userInfo![ReplicatorErrorUserInfoKey] as! NSError
                    XCTAssertEqual(error.code, err)
                }
                return true
            }
            return false
        }
        repl!.start()
        wait(for: [x], timeout: 5.0)
    }
    
    
    func testEmptyPush() {
        run(push: true, pull: false, expectedError: nil)
    }
}
