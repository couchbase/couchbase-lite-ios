//
//  MultipeerReplicatorTest.swift
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

import XCTest
import CouchbaseLiteSwift

class MultipeerReplicatorTest: CBLTestCase {
    let kTestKeyUsages: KeyUsages = [.clientAuth, .serverAuth]
    
    let kTestPeerGroupID = "CBLMultipeerReplTestGroup"
    
    let kTestMaxIdentity = 2 // Increase this when testing more than two peers.
    
    let kTestIdentityCommonName = "CBLMultipeerReplTest"
    
    var identityCount = 0
    
    var isExecutionAllowed: Bool {
#if targetEnvironment(simulator)
    // Cannot be tested on the simulator as local network access permission is required.
    // See FAQ-12: https://developer.apple.com/forums/thread/663858
    return false
#else
    return keyChainAccessAllowed
#endif
    }
    
    override func setUp() {
        super.setUp()
        if (isExecutionAllowed) {
            try! cleanUpIdentities()
        }
    }
    
    override func tearDown() {
        if (isExecutionAllowed) {
            try! cleanUpIdentities()
        }
        super.tearDown()
    }
    
    func identityNameForNumber(_ num: Int) -> String {
        return "\(kTestIdentityCommonName)-\(num)"
    }
    
    func cleanUpIdentities() throws {
        for i in 1...kTestMaxIdentity {
            let label = identityNameForNumber(i)
            try TLSIdentity.deleteIdentity(withLabel: label)
        }
    }
    
    func createIdentity() throws -> TLSIdentity {
        assert(identityCount <= kTestMaxIdentity)
        identityCount += 1
        
        let name = identityNameForNumber(identityCount)
        let attrs = [certAttrCommonName: name]
        return try TLSIdentity.createIdentity(
            for: kTestKeyUsages,
            attributes: attrs,
            expiration: nil,
            label: name)
    }
    
    func multipeerReplicator(for db: Database) throws -> MultipeerReplicator {
        let collection = try db.defaultCollection()
        
        let collConfigs = [MultipeerCollectionConfiguration(collection: collection)]
        
        let auth = MultipeerCertificateAuthenticator { peerID, certs in
            return true
        }
        
        let identity = try createIdentity()
        
        let config = MultipeerReplicatorConfiguration(
            peerGroupID: kTestPeerGroupID,
            identity: identity,
            authenticator: auth,
            collections: collConfigs)
        
        return try MultipeerReplicator(config: config)
    }
    
    func testSanityStartStop() throws {
        try XCTSkipUnless(isExecutionAllowed)

        let repl = try multipeerReplicator(for: db)
        
        let xActive = expectation(description: "Active")
        let xInactive = expectation(description: "Inactive")

        _ = repl.addStatusListener(on: nil) { status in
            XCTAssertNil(status.error)
            if status.active {
                xActive.fulfill()
            } else {
                xInactive.fulfill()
            }
        }
        
        repl.start()
        wait(for: [xActive], timeout: 10.0)

        repl.stop()
        wait(for: [xInactive], timeout: 10.0)
    }
    
    func testSanityReplication() throws {
        try XCTSkipUnless(isExecutionAllowed)
        
        // Peer #1
        let repl1 = try multipeerReplicator(for: db)

        let xActive1 = expectation(description: "Active")
        let xUnactive1 = expectation(description: "Unactive")
        _ = repl1.addStatusListener { status in
            XCTAssertNil(status.error)
            if status.active {
                xActive1.fulfill()
            } else {
                xUnactive1.fulfill()
            }
        }

        let xOnline1 = expectation(description: "Online")
        _ = repl1.addPeerDiscoveryStatusListener { status in
            XCTAssertNotNil(status.peerID)
            if status.online {
                xOnline1.fulfill()
            }
        }

        let xIdle1 = expectation(description: "Idle")
        xIdle1.assertForOverFulfill = false // TODO: Investigate if it's an issue or not
        let xStopped1 = expectation(description: "Stopped")
        _ = repl1.addPeerReplicatorStatusListener { change in
            XCTAssertNotNil(change.peerID)
            switch change.status.activity {
            case .idle:
                xIdle1.fulfill()
            case .stopped:
                xStopped1.fulfill()
            default:
                break
            }
        }

        repl1.start()
        wait(for: [xActive1], timeout: 10.0)

        // Peer #2
        let repl2 = try multipeerReplicator(for: db)

        let xActive2 = expectation(description: "Active")
        let xUnactive2 = expectation(description: "Unactive")
        _ = repl2.addStatusListener { status in
            XCTAssertNil(status.error)
            if status.active {
                xActive2.fulfill()
            } else {
                xUnactive2.fulfill()
            }
        }

        let xOnline2 = expectation(description: "Online")
        let xOffline2 = expectation(description: "Offline")
        xOffline2.assertForOverFulfill = false // TODO: Investigate if it's an issue or not
        _ = repl2.addPeerDiscoveryStatusListener { status in
            XCTAssertNotNil(status.peerID)
            if status.online {
                xOnline2.fulfill()
            } else {
                xOffline2.fulfill()
            }
        }

        let xIdle2 = expectation(description: "Idle")
        xIdle2.assertForOverFulfill = false // TODO: Investigate if it's an issue or not
        let xStopped2 = expectation(description: "Stopped")
        _ = repl2.addPeerReplicatorStatusListener { change in
            XCTAssertNotNil(change.peerID)
            switch change.status.activity {
            case .idle:
                xIdle2.fulfill()
            case .stopped:
                xStopped2.fulfill()
            default:
                break
            }
        }

        repl2.start()
        wait(for: [xActive2], timeout: 10.0)
        wait(for: [xOnline1, xOnline2], timeout: 60.0)
        wait(for: [xIdle1, xIdle2], timeout: 10.0)

        repl1.stop()
        wait(for: [xStopped1, xStopped2], timeout: 10.0)
        wait(for: [xOffline2], timeout: 10.0)
        wait(for: [xUnactive1], timeout: 60.0)

        repl2.stop()
        wait(for: [xUnactive2], timeout: 10.0)
    }
}
