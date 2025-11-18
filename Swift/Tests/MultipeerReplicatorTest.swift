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
@testable import CouchbaseLiteSwift

/// Test Spec : https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0012-MultipeerReplicator.md
/// Version : 1.1.0
class MultipeerReplicatorTest: CBLTestCase {
    class AnyMultipeerConflictResolver: MultipeerConflictResolver {
        private let resolver: (PeerID, Conflict) -> Document?

        init(resolver: @escaping (PeerID, Conflict) -> Document?) {
            self.resolver = resolver
        }

        func resolve(peerID: PeerID, conflict: Conflict) -> Document? {
            return resolver(peerID, conflict)
        }
    }
    
    let kTestKeyUsages: KeyUsages = [.clientAuth, .serverAuth]
    
    let kTestPeerGroupID = "CBLMultipeerReplTestGroup"
    
    let kTestMaxIdentity = 10
    
    let kTestIdentityCommonName = "CBLMultipeerReplTest"
    
    var identityCount = 0
    
    let listenerQueue = DispatchQueue(label: "MultipeerReplicatorTest.ListenerQueue")
    
    var listenerTokens: [String: [ListenerToken]] = [:]
    
    typealias PeerReplicatorStatusMap = [PeerID: PeerReplicatorStatus]
    
    var replicatorStatuses: [String: PeerReplicatorStatusMap] = [:]
    
    // TODO: Too flaky, enable after all LiteCore issues have been handled.
    var isExecutionAllowed: Bool {
#if targetEnvironment(simulator)
        // Cannot be tested on the simulator as local network access permission is required.
        // See FAQ-12: https://developer.apple.com/forums/thread/663858
        return false
#else
        // Disable as cannot be run on the build VM (Got POSIX Error 50, Network is down)
        return keyChainAccessAllowed && false
#endif
    }
    
    private var _issuer: TLSIdentity?
    
    var issuer: TLSIdentity {
        get throws {
            if let existing = _issuer {
                return existing
            }

            let caKeyData = try dataFromResource(name: "identity/ca-key", ofType: "der")
            let caCertData = try dataFromResource(name: "identity/ca-cert", ofType: "der")

            let newIssuer = try TLSIdentity.createIssuer(withPrivateKey: caKeyData, certificate: caCertData)
            _issuer = newIssuer
            return newIssuer
        }
    }
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(isExecutionAllowed)
    }
    
    override func setUp() {
        super.setUp()
        
        try! cleanUpIdentities()
        
        try! openOtherDB()
        
        replicatorStatuses.removeAll()
        listenerTokens.removeAll()
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
        _issuer = nil
        
    }
    
    func createIdentity() throws -> TLSIdentity {
        assert(identityCount <= kTestMaxIdentity)
        identityCount += 1
        
        let label = identityNameForNumber(identityCount)
        
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let cn = "\(label)-\(timestamp)"
        let attrs = [certAttrCommonName: cn]
        
        return try TLSIdentity.createIdentity(
            for: kTestKeyUsages,
            attributes: attrs,
            expiration: nil,
            issuer: self.issuer,
            label: label)
    }
    
    typealias CollectionConfigBlock = (inout MultipeerCollectionConfiguration) -> Void
    
    func multipeerReplicator(for database: Database,
                             authenticator: MultipeerAuthenticator? = nil,
                             collectionConfigBlock: CollectionConfigBlock? = nil) throws -> MultipeerReplicator {
        let collection = try database.defaultCollection()
        
        var collConfigs = MultipeerCollectionConfiguration(collection: collection)
        if let block = collectionConfigBlock {
            block(&collConfigs)
        }
        
        let auth = authenticator ?? MultipeerCertificateAuthenticator { _, _ in true }
        
        let identity = try createIdentity()
        
        let config = MultipeerReplicatorConfiguration(
            peerGroupID: kTestPeerGroupID,
            identity: identity,
            authenticator: auth,
            collections: [collConfigs])
        
        return try MultipeerReplicator(config: config)
    }
    
    func replicatorID(for repl: MultipeerReplicator) -> String {
        return "\(Unmanaged.passUnretained(repl).toOpaque())"
    }
    
    func addListenerToken(_ token: ListenerToken, for repl: MultipeerReplicator) {
        let id = replicatorID(for: repl)
        listenerTokens[id, default: []].append(token)
    }
    
    func resetListenerTokens(for repl: MultipeerReplicator) {
        let id = replicatorID(for: repl)
        listenerTokens[id]?.forEach { $0.remove() }
        listenerTokens[id] = nil
    }
    
    func startMultipeerReplicator(_ repl: MultipeerReplicator) {
        let xActive = expectation(description: "Active")
        let token1 = repl.addStatusListener(on: listenerQueue) { status in
            XCTAssertNil(status.error)
            if status.active {
                xActive.fulfill()
            }
        }
        
        let id = replicatorID(for: repl)
        let token2 = repl.addPeerReplicatorStatusListener(on: listenerQueue) { status in
            var statusMap = self.replicatorStatuses[id] ?? [:]
            statusMap[status.peerID] = status
            self.replicatorStatuses[id] = statusMap
        }
        addListenerToken(token2, for: repl)
        
        repl.start()
        wait(for: [xActive], timeout: expTimeout)
        token1.remove()
    }
    
    func stopMultipeerReplicator(_ repl: MultipeerReplicator) {
        let xInactive = expectation(description: "Inactive")
        let token = repl.addStatusListener(on: nil) { status in
            XCTAssertNil(status.error)
            if !status.active {
                xInactive.fulfill()
            }
        }
        
        repl.stop()
        wait(for: [xInactive], timeout: expTimeout)
        token.remove()
        
        resetListenerTokens(for: repl)
    }
    
    func replicatorStatus(for repl: MultipeerReplicator, peerID: PeerID) -> PeerReplicatorStatus? {
        let id = replicatorID(for: repl)
        var status: PeerReplicatorStatus?
        listenerQueue.sync {
            if let map = replicatorStatuses[id] {
                status = map[peerID]
            }
        }
        return status
    }
    
    func waitForReplicatorStatus(for repl: MultipeerReplicator,
                                 peerID: PeerID,
                                 activityLevel: Replicator.ActivityLevel,
                                 errorCode: Int = 0,
                                 errorDomain: String? = nil) {
        var idleCount = 0
        let deadline = Date().addingTimeInterval(expTimeout)
        while Date() < deadline {
            if let status = replicatorStatus(for: repl, peerID: peerID),
                status.status.activity == activityLevel {
                switch activityLevel {
                case .idle:
                    idleCount += 1
                    if idleCount >= 3 {
                        return // IDLE confirmed
                    }
                    Thread.sleep(forTimeInterval: 0.5)
                    continue
                case .stopped:
                    if errorCode != 0 {
                        let error = status.status.error as NSError?
                        XCTAssertEqual(error?.code, errorCode)
                        if let domain = errorDomain {
                            XCTAssertEqual(error?.domain, domain)
                        }
                    } else {
                        XCTAssertNil(status.status.error)
                    }
                    return
                default:
                    return
                }
            }
            idleCount = 0 // Reset if not idle
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        XCTFail("Timeout waiting for activity level: \(activityLevel.rawValue)")
    }
    
    // MARK: - Configuration
    
    /**
     ### 1. TestConfiguration

     #### Description
     Test that the configuration can be created successfully.

     #### Steps
     1. Create the configuration with the following:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback returning true.
         - collections: Collection configs containing a default collection
             - documentIDs: ["doc1"]
             - push/pull filter that returns true
             - a custom conflict resolver
     2. Check that the configuration is created successfully.
     3. Check that each property returns the correct value.
     */
    func testConfiguration() throws {
        // Create the collection
        let collection = try db.defaultCollection()

        // Create the identity
        let identity = try createIdentity()

        // Authenticator with a callback returning true
        let auth = MultipeerCertificateAuthenticator { _, _ in true }

        // Collection config
        var collConfig = MultipeerCollectionConfiguration(collection: collection)
        collConfig.documentIDs = ["doc1"]
        collConfig.pushFilter = { _, doc, _ in doc.id == "doc1" }
        collConfig.pullFilter = { _, doc, _ in doc.id == "doc4" }
        collConfig.conflictResolver = AnyMultipeerConflictResolver { _, conflict in
            conflict.remoteDocument
        }

        // Replicator config
        let config = MultipeerReplicatorConfiguration(
            peerGroupID: kTestPeerGroupID,
            identity: identity,
            authenticator: auth,
            collections: [collConfig]
        )

        // Check that the configuration is created successfully
        XCTAssertNotNil(config)

        // Check that each property returns the correct value
        XCTAssertEqual(config.peerGroupID, kTestPeerGroupID)
        XCTAssert(config.identity === identity)
        XCTAssert((config.authenticator as AnyObject) === (auth as AnyObject))
        XCTAssertEqual(config.collections.count, 1)
        XCTAssertEqual(config.collections[0].documentIDs, ["doc1"])
        XCTAssertNotNil(config.collections[0].pushFilter)
        XCTAssertNotNil(config.collections[0].pullFilter)
        XCTAssertNotNil(config.collections[0].conflictResolver)
    }
    
    /**
     ### 2. TestConfigurationValidation

     #### Description
     Validate that a configuration cannot be created if the peerGroupID or collections are invalid.

     #### Steps
     1. Create the configuration with an empty peerGroupID:
         - peerGroupID: ""
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback returning true.
         - collections: Collection configs containing the default collection
     2. Check that the configuration cannot be created as the peerGroupID is empty.
     3. Create the configuration with an empty collections:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A self-signed TLSIdentity for both client and server auth
         - authenticator: Authenticator with a callback returning true.
         - collections: Zero collections
     4. Check that the configuration cannot be created as the collections are empty.
     */
    func testConfigurationValidation() throws {
        throw XCTSkip("Swift's Precondition cannot be asserted. Enable manually when needed.")
        
        // Create the collection and identity
        let collection = try db.defaultCollection()
        let identity = try createIdentity()
        let auth = MultipeerCertificateAuthenticator { _, _ in true }
        let collConfig = MultipeerCollectionConfiguration(collection: collection)

        // Create the configuration with an empty peerGroupID:
        _ = MultipeerReplicatorConfiguration(
            peerGroupID: "",
            identity: identity,
            authenticator: auth,
            collections: [collConfig]
        )
        
        // Create the configuration with an empty collections:
        _ = MultipeerReplicatorConfiguration(
            peerGroupID: self.kTestPeerGroupID,
            identity: identity,
            authenticator: auth,
            collections: []
        )
    }
    
    // MARK: - Stop and Restart
    
    /**
     ### 3. TestStartStop

     #### Description
     Test that a MultipeerReplicator can be started and stopped.

     #### Steps
     1. Create a MultipeerReplicator for a database with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: An authenticator with a callback that returns true.
         - collections: Collection configs containing the default collection.
     2. Add a listener to monitor the replicator's active status.
     3. Start the replicator.
     4. Wait until the replicator is active and ensure that there are no errors.
     5. Stop the replicator.
     6. Wait until the replicator is inactive and ensure that there are no errors.
     7. Start the replicator again and check that it cannot be restarted (for 3.3.0).
     */
    func testStartStop() throws {
        let repl = try multipeerReplicator(for: db)
            
        let xActive = expectation(description: "Active")
        let xInactive = expectation(description: "Inactive")
            
        let token = repl.addStatusListener(on: nil) { status in
            XCTAssertNil(status.error)
            if status.active {
                xActive.fulfill()
            } else {
                xInactive.fulfill()
            }
        }
            
        repl.start()
        wait(for: [xActive], timeout: expTimeout)
        
        repl.stop()
        wait(for: [xInactive], timeout: expTimeout)
        
        token.remove()
        
        expectException(exception: .internalInconsistencyException) {
            repl.start()
        }
    }
    
    /**
     ### 4. TestImmediateStartStop

     #### Description
     Test that a MultipeerReplicator can be started then stopped immediately.

     #### Steps
     1. Create a MultipeerReplicator for a database with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: An authenticator with a callback that returns true.
         - collections: Collection configs containing the default collection.
     2. Add a listener to monitor the replicator's active status.
     3. Start the replicator.
     4. Stop the replicator.
     5. Wait until the replicator is inactive and ensure that there are no errors.
     */
    func testImmediateStartStop() throws {
        let repl = try multipeerReplicator(for: db)

        let xInactive = expectation(description: "Inactive")

        let token = repl.addStatusListener(on: nil) { status in
            if !status.active {
                xInactive.fulfill()
            }
        }

        repl.start()
        repl.stop()

        wait(for: [xInactive], timeout: expTimeout)

        token.remove()
    }
    
    // MARK: - Database Close
    
    /**
     ### 5. TestStopOnCloseDatabase

     #### Description
     Test that a MultipeerReplicator can be started and stopped when the database is closed.

     #### Steps
     1. Create a MultipeerReplicator for a database with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback returning true.
         - collections: Collection configs containing the default collection.
     2. Add a listener to monitor the replicator's active status.
     3. Start the replicator.
     4. Wait until the replicator is active and ensure that there are no errors.
     5. Close the database.
     6. Wait until the MultipeerReplicator is inactive and ensure that there are no errors.
     */
    func testStopOnCloseDatabase() throws {
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
        wait(for: [xActive], timeout: expTimeout)
        
        try db.close()
        
        wait(for: [xInactive], timeout: expTimeout)
    }
    
    // MARK: - Replication
    
    /**
     ### 6. TestBasicReplication

     #### Description
     Test basic replication between two multipeer replicators.

     #### Steps
     1. Create a document in the default collection of db#1:
         - docID: "doc1"
         - body: {"greeting": "hello"}
     2. Create a document in the default collection of db#2:
         - docID: "doc2"
         - body: {"greeting": "hi"}
     3. Create MultipeerReplicator#1 for db#1 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback returning true.
         - collections: Collection configs containing the default collection.
     4. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     5. Start MultipeerReplicator#1 and wait until the replicator is active.
     6. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback returning true.
         - collections: Collection configs containing the default collection.
     7. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     8. Start MultipeerReplicator#2 and wait until the replicator is active.
     9. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     10. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
     11. Verify that both doc1 and doc2 exist in both databases.
     12. Stop both replicators and wait until the replicators are inactive.
     */
    func testBasicReplication() throws {
        let collection1 = try db.defaultCollection()
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("hello", forKey: "greeting")
        try collection1.save(document: doc1)

        let collection2 = try otherDB!.defaultCollection()
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("hi", forKey: "greeting")
        try collection2.save(document: doc2)

        let repl1 = try multipeerReplicator(for: db)
        startMultipeerReplicator(repl1)

        let repl2 = try multipeerReplicator(for: otherDB!)
        startMultipeerReplicator(repl2)

        waitForReplicatorStatus(for: repl1, peerID: repl2.peerID, activityLevel: .idle)
        waitForReplicatorStatus(for: repl2, peerID: repl1.peerID, activityLevel: .idle)

        let checkDoc1a = try collection1.document(id: "doc1")
        XCTAssertNotNil(checkDoc1a)
        let checkDoc2a = try collection1.document(id: "doc2")
        XCTAssertNotNil(checkDoc2a)
        
        let checkDoc1b = try collection2.document(id: "doc1")
        XCTAssertNotNil(checkDoc1b)
        let checkDoc2b = try collection2.document(id: "doc2")
        XCTAssertNotNil(checkDoc2b)

        stopMultipeerReplicator(repl1)
        stopMultipeerReplicator(repl2)
    }
    
    // MARK: - Authenticator
    
    /**
     ### 7. TestAuthenticationWithRootCerts

     #### Description
     Test that the authenticator can authenticate a peer's certificate that is signed by the
     given root certificates.

     #### Steps
     1. Create MultipeerReplicator#1 for db#1 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with the issuer certificate.
         - collections: Collection configs containing the default collection.
     2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     3. Start MultipeerReplicator#1 and wait until the replicator is active.
     4. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with the issuer certificate.
         - collections: Collection configs containing the default collection.
     5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     6. Start MultipeerReplicator#2 and wait until the replicator is active.
     7. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     8. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
     9. Stop both replicators and wait until the replicators are inactive.
     */
    func testAuthenticateWithRootCerts() throws {
        let issuer = try self.issuer
        let auth = MultipeerCertificateAuthenticator(rootCerts: issuer.certs)
        
        // Peer #1
        let repl1 = try multipeerReplicator(for: db, authenticator: auth)
        startMultipeerReplicator(repl1)
        
        // Peer #2
        let repl2 = try multipeerReplicator(for: otherDB!, authenticator: auth)
        startMultipeerReplicator(repl2)
        
        // Wait until the replicator is IDLE
        waitForReplicatorStatus(for: repl1, peerID: repl2.peerID, activityLevel: .idle)
        waitForReplicatorStatus(for: repl2, peerID: repl1.peerID, activityLevel: .idle)
        
        stopMultipeerReplicator(repl1)
        stopMultipeerReplicator(repl2)
    }
    
    /**
     ### 8. TestAuthenticationWithRootCertsFailed

     #### Description
     Test that the authenticator can reject a peer's certificate that is not signed by the given root certificates.

     #### Steps

     1. Create MultipeerReplicator#1 for db#1 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with the invalid root cert from asset #2.
         - collections: Collection configs containing the default collection.
     2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     3. Start MultipeerReplicator#1 and wait until the replicator is active.
     4. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with the issuer certificate.
         - collections: Collection configs containing the default collection.
     5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     6. Start MultipeerReplicator#2 and wait until the replicator is active.
     7. Wait until a peer's replicator becomes STOPPED with a TLSClientCertRejected (5010) error.
        Only the MultipeerReplicator that has an active replicator will report the replicator status.
        As you don't know which MultipeerReplicator's replicator will be active,
        you should listen to the replicator status on both MultipeerReplicators and ensure
        that one of the replicators is STOPPED with the error.
     */
    func testAuthenticateWithRootCertsFailed() throws {
        let rootCertPEM = """
        -----BEGIN CERTIFICATE-----
        MIIE/DCCAuSgAwIBAgIUHKj9KlERcqJF62FpOzQn7rC9PPgwDQYJKoZIhvcNAQEL
        BQAwFjEUMBIGA1UEAwwLQ0JMLVRFU1QtQ0EwHhcNMjUwNjIwMjExNDQ5WhcNMzUw
        NjE4MjExNDQ5WjAWMRQwEgYDVQQDDAtDQkwtVEVTVC1DQTCCAiIwDQYJKoZIhvcN
        AQEBBQADggIPADCCAgoCggIBALePrUMEM/yZtxMghU3MJ5RlA+OxYqt+NTFvPMTY
        xOzdEhT/fZr5AoGoOYSHdBoixOrztsJqoJSkfZrmGbSITVfr/p/KD9XwUYRn0EGq
        hVWN/HWPU5uu1TJ6nrbmuFHu99ydjohsgse+O20nskgacMxnO90L8rahKqnxz5ex
        HSfmn2NfB9Z5+cMK335eXYp4+RXeJv7PXIW2eWDJElO+qr5jZky3c8Vx62jGasQr
        A+2ld2o5eEAwAfqRTy9quTtClCaucR5zVyq2Al7VromYSnVe1LMqj+VwHR8tVAlk
        O+01zse45Gyrl/13YqUOGig+bhG0WTew2cF1TMK7fwnYLid/GD4Pn7gJBnglShd5
        nwKEXyse/6YC/TsEHgTxzbkEOX8o0fVIGusQ2v3Jxne7ikqtE/D3i10wJzBBzxfo
        rHFFl8gJdejq2YpclwXJN52cNVDEfz43gwDrCvh3WnfSrZmbAOAzbgNd4GMOLJ+Q
        PaAAdes295n++ShU6Cf6qEusxPhhazWqxjf86PPmAZNDRjrb4MbVY0DZK3Pq8Pr3
        bOVxzRSReu8phM/wcUuk4PVnHtE1ewN9mkWCqIDumibOTYPPVPXAF09SLB7TK0Lz
        XZWrvA+U/A1g+JgNbjslio7ezgf9RtMBOvj63pYwLTvYqZnQalTmxlTTs8ThEeFK
        3Xm7AgMBAAGjQjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0G
        A1UdDgQWBBT9ffZwg9GBhCkDqTmtK0dNezxl8DANBgkqhkiG9w0BAQsFAAOCAgEA
        l3I3BZ6e88Q+vmOgQoLgc9JS+tQHSfTf1PFhlxHcMpvLcFQ66VFJowrARtDEIdHj
        1xFJpoidXVAtX9ku4toT+65G9EnGvjut4zf1BcqAesxeSlMpr8nYIff2RZpNOkeF
        bURKabyfOHeK28SiJaOhCpZZznzlBwpI68zdAHRA12wiVjZHx1sZwK2eRJB+GE59
        d9HTM3xntWW1rJRUOS83HbaxN3P/XcD/DLcfRQf1GTszsxh3MpYFOOGMODV7xJ+a
        LQ5sdvsTtslcgqgaGqVMyShcKB12PFyJOsScZHMPFK2Bu9VnR5yUQsJLxlYtHJS7
        9IpAy/XW/ivEsTZJd6VrTsBobRIrUkLGgJnK1pFlcIDO6Cj1K/ZpX7u+v1aD+Btu
        2C1bHc0kwqj7xYv7EQUfeseiig/9prHCKpPrZp9cH+UppQZCXdINFvu+0w+3pdzr
        AStjq18eOYpplAAbkqj5WhNDCS3jF+7Uf/Azkh7BpG+ZTb+J3xBiU+SUZZoTIjc0
        hnbgyPPvzE1X+EMbR/5bQFeoxgEzp+MvWXIfgtQNptdIaPiRr0paKktF//2vP6JR
        /qle/sPmxhj5/U3SvLifM3lNnK21AEhJkCJSzTXffCWem+FP5c8Vr5xWG7p3q+cr
        0qsmhfuPRNBMd7cfE0Qz1koitWi9U3jVedH2eUNCf5k=
        -----END CERTIFICATE-----
        """

        let certRef = try createSecCertFromPEM(rootCertPEM)
        let auth = MultipeerCertificateAuthenticator(rootCerts: [certRef])

        let xStopped = expectation(description: "Stopped")

        // Peer #1
        let repl1 = try multipeerReplicator(for: db, authenticator: auth)
        let token1 = repl1.addPeerReplicatorStatusListener { change in
            if change.status.activity == .stopped {
                let error = change.status.error as NSError?
                XCTAssertNotNil(error)
                XCTAssertEqual(error?.code, CBLError.tlsClientCertRejected)
                XCTAssertEqual(error?.domain, CBLError.domain)
                xStopped.fulfill()
            }
        }
        startMultipeerReplicator(repl1)

        // Peer #2
        let repl2 = try multipeerReplicator(for: otherDB!, authenticator: auth)
        let token2 = repl2.addPeerReplicatorStatusListener { change in
            if change.status.activity == .stopped {
                let error = change.status.error as NSError?
                XCTAssertNotNil(error)
                XCTAssertEqual(error?.code, CBLError.tlsClientCertRejected)
                XCTAssertEqual(error?.domain, CBLError.domain)
                xStopped.fulfill()
            }
        }
        startMultipeerReplicator(repl2)

        wait(for: [xStopped], timeout: expTimeout)

        stopMultipeerReplicator(repl1)
        stopMultipeerReplicator(repl2)

        token1.remove()
        token2.remove()
    }
    
    /**
     ### 9. TestAuthenticationWithCallbackFailed

     #### Description
     Test that the authenticator can reject via the authentication callback.

     #### Steps

     1. Create MultipeerReplicator#1 for db#1 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
     2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     3. Start MultipeerReplicator#1 and wait until the replicator is active.
     4. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with the issuer certificate.
         - collections: Collection configs containing the default collection.
     5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     6. Start MultipeerReplicator#2 and wait until the replicator is active.
     7. Wait until a peer's replicator becomes STOPPED with a TLSClientCertRejected (5010) error.
        Only the MultipeerReplicator that has an active replicator will report the replicator status.
        As you don't know which MultipeerReplicator's replicator will be active,
        you should listen to the replicator status on both MultipeerReplicators and ensure
        that one of the replicators is STOPPED with the error.
     */
    func testAuthenticateWithCallbackFailed() throws {
        let auth = MultipeerCertificateAuthenticator { peerID, certs in
            XCTAssertNotNil(peerID)
            XCTAssertFalse(certs.isEmpty)
            return false
        }
    
        let xStopped = expectation(description: "Stopped")
    
        // Peer #1
        let repl1 = try multipeerReplicator(for: db, authenticator: auth)
        let token1 = repl1.addPeerReplicatorStatusListener { change in
            if change.status.activity == .stopped {
                let error = change.status.error as NSError?
                XCTAssertNotNil(error)
                XCTAssertEqual(error?.code, CBLError.tlsClientCertRejected)
                XCTAssertEqual(error?.domain, CBLError.domain)
                xStopped.fulfill()
            }
        }
        startMultipeerReplicator(repl1)
    
        // Peer #2
        let repl2 = try multipeerReplicator(for: otherDB!, authenticator: auth)
        let token2 = repl2.addPeerReplicatorStatusListener { change in
            if change.status.activity == .stopped {
                let error = change.status.error as NSError?
                XCTAssertNotNil(error)
                XCTAssertEqual(error?.code, CBLError.tlsClientCertRejected)
                XCTAssertEqual(error?.domain, CBLError.domain)
                xStopped.fulfill()
            }
        }
        startMultipeerReplicator(repl2)
    
        wait(for: [xStopped], timeout: expTimeout)
    
        stopMultipeerReplicator(repl1)
        stopMultipeerReplicator(repl2)
        
        token1.remove()
        token2.remove()
    }
    
    // MARK: - Listener
    
    /**
     ### 10. TestPeerDiscoveryListener

     #### Description
     Test that the peer discovery listener can receive the peer discovery events.

     #### Steps

     1. Create MultipeerReplicator#1 for db#1 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback returning true.
         - collections: Collection configs containing the default collection.
     2. Add a listener to monitor the replicator’s active status.
     3. Add a listener to monitor peer discovery status.
     4. Start MultipeerReplicator#1 and wait until the replicator is active.
     5. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback returning true.
         - collections: Collection configs containing the default collection.
     6. Add a listener to monitor the replicator’s active status,
     7. Add a listener to monitor peer discovery status.
     8. Start MultipeerReplicator#2 and wait until the replicator is active.
     9. Based on the peer discovery listener of the MultipeerReplicator#1,
         wait until MultipeerReplicator#2 is online.
     10. Based on the peer discovery listener of the MultipeerReplicator#2,
         wait until MultipeerReplicator#1 is online.
     11. Stop MultipeerReplicator#1 and wait until the replicator is inactive.
     12. Based on the peer discovery listener of the MultipeerReplicator#2,
         wait until MultipeerReplicator#1 is offline.
     13. Stop MultipeerReplicator#2 and wait until the replicator is inactive.
     */
    func testPeerDiscoveryListener() throws {
        let repl1 = try multipeerReplicator(for: db)
        let repl2 = try multipeerReplicator(for: otherDB!)
        
        let xPeer2Online = expectation(description: "Peer#2 Online")
        let token1 = repl1.addPeerDiscoveryStatusListener(on: listenerQueue) { status in
            XCTAssertEqual(status.peerID, repl2.peerID)
            if status.online {
                xPeer2Online.fulfill()
            }
        }
        
        startMultipeerReplicator(repl1)
        
        // Expectation: repl2 discovers repl1 online and then offline
        let xPeer1Online = expectation(description: "Peer#1 Online")
        let xPeer1Offline = expectation(description: "Peer#1 Offline")
        xPeer1Offline.assertForOverFulfill = false
        
        let token2 = repl2.addPeerDiscoveryStatusListener(on: listenerQueue) { status in
            XCTAssertEqual(status.peerID, repl1.peerID)
            if status.online {
                xPeer1Online.fulfill()
            } else {
                xPeer1Offline.fulfill()
            }
        }
        
        startMultipeerReplicator(repl2)
        
        wait(for: [xPeer2Online, xPeer1Online], timeout: expTimeout)
        
        Thread.sleep(forTimeInterval: 1.0)
        
        stopMultipeerReplicator(repl1)
        
        wait(for: [xPeer1Offline], timeout: expTimeout)
        
        stopMultipeerReplicator(repl2)
        
        token1.remove()
        token2.remove()
    }
    
    /**
     ### 11. TestDocumentReplicationListener

     #### Description
     Test that the document replication listener can receive the document replication events.
     Note : This test could be combined with TestBasicReplication.

     #### Steps

     1. Create MultipeerReplicator#1 for db#1 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback returning true.
         - collections: Collection configs containing the default collection.
     2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     3. Add a document replication listener that will record the document replication events.
     4. Start MultipeerReplicator#1 and wait until the replicator is active.
     5. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback returning true.
         - collections: Collection configs containing the default collection.
     6. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     7. Add a document replication listener that will record the document replication events.
     8. Start MultipeerReplicator#2 and wait until the replicator is active.
     9. Create a document in the default collection of db#1:
         - docID: "doc1"
         - body: {"greeting": "hello"}
     10. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     11. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
     12. Verify the recorded document replication events of MultipeerReplicator#1.
         - Verify that number of document replication : 1
         - Verify that number of replicated document : 1
         - Verify the replicated document :
             { isPush : true,  id : "doc1", flags : 0, error: NULL, scope: " _default", collection: "_default" }
     13. Verify the recorded document replication events of MultipeerReplicator#1.
         - Verify that number of document replication : 1
         - Verify that number of replicated document : 1
         - Verify the replicated document :
         { isPush : false,  id : "doc1", flags : 0, error: NULL, scope: " _default", collection: "_default" }
     14. Stop both replicators and wait until the replicators are inactive.
     */
    func testDocumentReplicationListener() throws {
        // Peer #1
        let repl1 = try multipeerReplicator(for: db)
        var docRepl1: [PeerDocumentReplication] = []
        let token1 = repl1.addPeerDocumentReplicationListener(on: listenerQueue) { docRepl in
            docRepl1.append(docRepl)
        }
    
        // Peer #2
        let repl2 = try multipeerReplicator(for: otherDB!)
        var docRepl2: [PeerDocumentReplication] = []
        let token2 = repl2.addPeerDocumentReplicationListener(on: listenerQueue) { docRepl in
            docRepl2.append(docRepl)
        }
    
        startMultipeerReplicator(repl1)
        startMultipeerReplicator(repl2)
    
        // Save a doc in one peer
        let collection1 = try db.defaultCollection()
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("hello", forKey: "greeting")
        try collection1.save(document: doc1)
    
        waitForReplicatorStatus(for: repl1, peerID: repl2.peerID, activityLevel: .idle)
        waitForReplicatorStatus(for: repl2, peerID: repl1.peerID, activityLevel: .idle)
    
        XCTAssertEqual(docRepl1.count, 1)
        XCTAssertTrue(docRepl1[0].isPush)
        XCTAssertEqual(docRepl1[0].documents.count, 1)
        XCTAssertEqual(docRepl1[0].documents[0].id, "doc1")
        XCTAssertEqual(docRepl1[0].documents[0].flags.rawValue, 0)
        XCTAssertNil(docRepl1[0].documents[0].error)
        XCTAssertEqual(docRepl1[0].documents[0].scope, "_default")
        XCTAssertEqual(docRepl1[0].documents[0].collection, "_default")
    
        XCTAssertEqual(docRepl2.count, 1)
        XCTAssertFalse(docRepl2[0].isPush)
        XCTAssertEqual(docRepl2[0].documents.count, 1)
        XCTAssertEqual(docRepl2[0].documents[0].id, "doc1")
        XCTAssertEqual(docRepl2[0].documents[0].flags.rawValue, 0)
        XCTAssertNil(docRepl2[0].documents[0].error)
        XCTAssertEqual(docRepl2[0].documents[0].scope, "_default")
        XCTAssertEqual(docRepl2[0].documents[0].collection, "_default")
    
        stopMultipeerReplicator(repl1)
        stopMultipeerReplicator(repl2)
    
        token1.remove()
        token2.remove()
    }
      
    // MARK: - Conflict Resolver
    
    func runConflictResolverTest(resolver: MultipeerConflictResolver?,verifyBlock: (Document?) -> Bool) throws {
        // Peer #1
        let repl1 = try multipeerReplicator(for: db) { config in
            config.conflictResolver = resolver
        }
        startMultipeerReplicator(repl1)
        
        // Peer #2
        let repl2 = try multipeerReplicator(for: otherDB!) { config in
            config.conflictResolver = resolver
        }
        startMultipeerReplicator(repl2)
        
        // Save a doc in peer#1
        var collection1 = try db.defaultCollection()
        var doc1 = MutableDocument(id: "doc1")
        doc1.setString("hello", forKey: "greeting")
        try collection1.save(document: doc1)
        
        // Wait until the replicator is IDLE
        waitForReplicatorStatus(for: repl1, peerID: repl2.peerID, activityLevel: .idle)
        waitForReplicatorStatus(for: repl2, peerID: repl1.peerID, activityLevel: .idle)
        
        // Stops
        stopMultipeerReplicator(repl1)
        stopMultipeerReplicator(repl2)
        
        // Update the doc in both peers, saving on peer#2 twice
        collection1 = try db.defaultCollection()
        doc1 = try collection1.document(id: "doc1")!.toMutable()
        doc1.setString("hi", forKey: "greeting")
        try collection1.save(document: doc1)
        
        let collection2 = try otherDB!.defaultCollection()
        let doc2 = try collection2.document(id: "doc1")!.toMutable()
        doc2.setString("hey", forKey: "greeting")
        try collection2.save(document: doc2)
        
        doc2.setString("howdy", forKey: "greeting")
        try collection2.save(document: doc2)
        
        // Restart both peers
        let repl1b = try multipeerReplicator(for: db) { config in
            config.conflictResolver = resolver
        }
        startMultipeerReplicator(repl1b)
        
        let repl2b = try multipeerReplicator(for: otherDB!) { config in
            config.conflictResolver = resolver
        }
        startMultipeerReplicator(repl2b)
        
        // Wait until the replicator is IDLE
        waitForReplicatorStatus(for: repl1b, peerID: repl2b.peerID, activityLevel: .idle)
        waitForReplicatorStatus(for: repl2b, peerID: repl1b.peerID, activityLevel: .idle)
        
        // Check the resolved document:
        let checkDoc1 = try collection1.document(id: "doc1")
        XCTAssertTrue(verifyBlock(checkDoc1))
        
        let checkDoc2 = try collection2.document(id: "doc1")
        XCTAssertTrue(verifyBlock(checkDoc2))
        
        stopMultipeerReplicator(repl1b)
        stopMultipeerReplicator(repl2b)
    }
    
    /**
     ### 12. TestDefaultConflictResolver

     #### Description
     Test that default conflict resolver is used when no custom conflict resolver specified.

     #### Steps

     1. Create MultipeerReplicator#1 for db#1 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
     2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     3. Start MultipeerReplicator#1 and wait until the replicator is active.
     4. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
     5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     6. Start MultipeerReplicator#1 and wait until the replicator is active.
     7. Create a document in the default collection of db#1:
         - docID: "doc1"
         - body: {"greeting": "hello"}
     8. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     9. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
     10. Stop MultipeerReplicator#2 and wait until the replicator is inactive.
     11. Update doc1 in db#1
         - docID: "doc1"
         - body: {"greeting": "hi"}
     12. Update doc1 in db#2
         - docID: "doc1"
         - body: {"greeting": "hey"}
     13. Update doc1 in db#2 again.
         - docID: "doc1"
         - body: {"greeting": "howdy"}
     14. Recreate and start both MultipeerReplicators.
     15. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     16. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
     17. Stop both MultipeerReplicators.
     18. Check the doc1 in both peers and verify that the its body is {"greeting": "howdy"}.
     */
    func testDefaultConflictResolver() throws {
        try runConflictResolverTest(resolver: nil) { resolvedDoc in
            resolvedDoc?.string(forKey: "greeting") == "howdy"
        }
    }

    /**
     ### 13. TestCustomConflictResolver

     #### Description
     Test that custom conflict resolver is used when it is specified.

     #### Steps

     1. Create MultipeerReplicator#1 for db#1 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
             - A custom conflict resolver running the document having greeting property's value == "hi"
     2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     3. Start MultipeerReplicator#1 and wait until the replicator is active.
     4. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
     5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     6. Start MultipeerReplicator#1 and wait until the replicator is active.
     7. Create a document in the default collection of db#1:
         - docID: "doc1"
         - body: {"greeting": "hello"}
     8. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     9. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
     10. Stop MultipeerReplicator#2 and wait until the replicator is inactive.
     11. Update doc1 in db#1
         - docID: "doc1"
         - body: {"greeting": "hi"}
     12. Update doc1 in db#2
         - docID: "doc1"
         - body: {"greeting": "hey"}
     13. Update doc1 in db#2 again.
         - docID: "doc1"
         - body: {"greeting": "howdy"}
     14. Recreate and start both MultipeerReplicators.
     15. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     16. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
     17. Stop both MultipeerReplicators.
     18. Check the doc1 in both peers and verify that the its body is {"greeting": "hi"}.
     */
    func testCustomConflictResolver() throws {
        let block: (PeerID, Conflict) -> Document? = { _, conflict in
            let greeting = conflict.localDocument?.string(forKey: "greeting")
            return greeting == "hi" ? conflict.localDocument : conflict.remoteDocument
        }
        let resolver = AnyMultipeerConflictResolver(resolver: block)
        try runConflictResolverTest(resolver: resolver) { resolvedDoc in
            resolvedDoc?.string(forKey: "greeting") == "hi"
        }
    }
    
    // MARK: - Replication Filter
    
    /**
     ### 14. TestDocumentIDsFilter

     #### Description
     Test that the documentIDs filter is used when it's specified.

     #### Steps
     1. Create MultipeerReplicator#1 for db#1 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
             - A documentIDs filter as ["doc1", "doc3"]
     2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     3. Start MultipeerReplicator#1 and wait until the replicator is active.
     4. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
     5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     6. Start MultipeerReplicator#2 and wait until the replicator is active.
     7. Save 3 documents in db#1
         - doc1: {"greeting": "hello"}
         - doc2: {"greeting": "hi"}
         - doc3: {"greeting": "howdy"}
     8. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     9. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
     10. Check that only doc1 and doc3 are pushed to MultipeerReplicator#2.
     11. Stop both replicators and wait until the replicators are inactive.
     */
    func testDocumentIDsFilter() throws {
        // Peer #1
        let repl1 = try multipeerReplicator(for: db) { config in
            config.documentIDs = ["doc1", "doc3"]
        }
        startMultipeerReplicator(repl1)
        
        // Peer #2
        let repl2 = try multipeerReplicator(for: otherDB!)
        startMultipeerReplicator(repl2)
        
        // Save 3 docs in peer #1
        let collection1 = try db.defaultCollection()
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("hello", forKey: "greeting")
        try collection1.save(document: doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("hi", forKey: "greeting")
        try collection1.save(document: doc2)
        
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("howdy", forKey: "greeting")
        try collection1.save(document: doc3)
        
        // Wait until the replicator is IDLE
        waitForReplicatorStatus(for: repl1, peerID: repl2.peerID, activityLevel: .idle)
        waitForReplicatorStatus(for: repl2, peerID: repl1.peerID, activityLevel: .idle)
        
        // Check that only doc1 and doc3 are pushed to Peer #2
        let collection2 = try otherDB!.defaultCollection()
        let checkDoc1 = try collection2.document(id: "doc1")
        XCTAssertNotNil(checkDoc1)
        XCTAssertEqual(checkDoc1?.string(forKey: "greeting"), "hello")
        
        let checkDoc2 = try collection2.document(id: "doc2")
        XCTAssertNil(checkDoc2)
        
        let checkDoc3 = try collection2.document(id: "doc3")
        XCTAssertNotNil(checkDoc3)
        XCTAssertEqual(checkDoc3?.string(forKey: "greeting"), "howdy")
        
        stopMultipeerReplicator(repl1)
        stopMultipeerReplicator(repl2)
    }
    
    /**
     ### 15. TestPushPullFilter

     #### Description
     Test that the push and pull filter are used when they are specified.

     #### Steps
     1. Create MultipeerReplicator#1 for db#1 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
             - pushFilter : Allow only document's ID == "doc1"
             - pullFilter : Allow only document's ID == "doc4"
     2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     3. Start MultipeerReplicator#1 and wait until the replicator is active.
     4. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
     5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
     6. Start MultipeerReplicator#2 and wait until the replicator is active.
     7. Save 2 documents in db#1
         - doc1: {"greeting": "hello"}
         - doc2: {"greeting": "hi"}
     8. Save 2 documents in db#2
         - doc3: {"greeting": "howdy"}
         - doc4: {"greeting": "hey"}
     9. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     10. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
     11. Check that only doc4 but not doc3 are pulled to MultipeerReplicator#1.
     12. Check that only doc1 but not doc2 are pushed to MultipeerReplicator#2.
     13. Stop both replicators and wait until the replicators are inactive.
     */
    func testPushPullFilter() throws {
        // Peer #1
        let repl1 = try multipeerReplicator(for: db) { config in
            config.pushFilter = { _, doc, _ in
                doc.id == "doc1"
            }
            config.pullFilter = { _, doc, _ in
                doc.id == "doc4"
            }
        }
        startMultipeerReplicator(repl1)
        
        // Peer #2
        let repl2 = try multipeerReplicator(for: otherDB!)
        startMultipeerReplicator(repl2)
        
        // Save doc1 and doc2 in peer #1
        let collection1 = try db.defaultCollection()
        let doc1 = MutableDocument(id: "doc1")
        doc1.setString("hello", forKey: "greeting")
        try collection1.save(document: doc1)
        
        let doc2 = MutableDocument(id: "doc2")
        doc2.setString("hi", forKey: "greeting")
        try collection1.save(document: doc2)
        
        // Save doc3 and doc4 in peer #2
        let collection2 = try otherDB!.defaultCollection()
        let doc3 = MutableDocument(id: "doc3")
        doc3.setString("howdy", forKey: "greeting")
        try collection2.save(document: doc3)
        
        let doc4 = MutableDocument(id: "doc4")
        doc4.setString("hey", forKey: "greeting")
        try collection2.save(document: doc4)
        
        // Wait until the replicator is IDLE
        waitForReplicatorStatus(for: repl1, peerID: repl2.peerID, activityLevel: .idle)
        waitForReplicatorStatus(for: repl2, peerID: repl1.peerID, activityLevel: .idle)
        
        // Check that only doc4 but not doc3 are pulled to peer #1
        let checkDoc4 = try collection1.document(id: "doc4")
        XCTAssertNotNil(checkDoc4)
        XCTAssertEqual(checkDoc4?.string(forKey: "greeting"), "hey")
        
        let checkDoc3 = try collection1.document(id: "doc3")
        XCTAssertNil(checkDoc3)
        
        // Check that only doc1 but not doc2 are pushed to peer #2
        let checkDoc1 = try collection2.document(id: "doc1")
        XCTAssertNotNil(checkDoc1)
        XCTAssertEqual(checkDoc1?.string(forKey: "greeting"), "hello")
        
        let checkDoc2 = try collection2.document(id: "doc2")
        XCTAssertNil(checkDoc2)
        
        stopMultipeerReplicator(repl1)
        stopMultipeerReplicator(repl2)
    }
    
    // MARK: - Peer Info
    
    /**
     ### 16. TestPeerID

     #### Description
     Test that getting the MultipeerReplicator's peerID returns a value as expected.

     #### Steps
     1. Create a MultipeerReplicator#1 for a database with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: An authenticator with a callback that returns true.
         - collections: Collection configs containing the default collection.
     2. Get the peerID of the replicator and and check that its data length is 32 bytes.
     3. Start MultipeerReplicator#1 and wait until the replicator is active.
     4. Stop MultipeerReplicator#1 and wait until the replicator is inactive.
     5. Get the peerID of the replicator and and check that its data length is 32 bytes.
     */
    func testPeerID() throws {
        let repl = try multipeerReplicator(for: db)
        XCTAssertNotNil(repl.peerID)
        XCTAssertEqual(repl.peerID.bytes.count, 32)
        
        startMultipeerReplicator(repl)
        stopMultipeerReplicator(repl)
        
        XCTAssertNotNil(repl.peerID)
        XCTAssertEqual(repl.peerID.bytes.count, 32)
    }
    
    /**
     ### 17. TestNeighborPeers

     #### Description
     Test that getting the MultipeerReplicator's neighborPeers returns the online peers
     as expected.

     #### Steps
     1. Create a MultipeerReplicator#1 for a database with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: An authenticator with a callback that returns true.
         - collections: Collection configs containing the default collection.
     2. Verify that MultipeerReplicator#1's neighborPeers is empty.
     3. Start MultipeerReplicator#1.
     4. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
     5. Verify that MultipeerReplicator#2's neighborPeers is empty.
     6. Start MultipeerReplicator#2
     7. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     8. Verify that MultipeerReplicator#1's neighborPeers includes MultipeerReplicator#2’s peerID.
     9. Verify that MultipeerReplicator#2's neighborPeers includes MultipeerReplicator#1’s peerID.
     10. Stop MultipeerReplicator#1 and wait until the replicator is inactive.
     11. Verify that the neighborPeers of both replicators are empty.
     12. Stop MultipeerReplicator#2 and wait until the replicator is inactive.
     13. Verify that MultipeerReplicator#2's neighborPeers is empty.
     */
    func testNeighborPeers() throws {
        let repl1 = try multipeerReplicator(for: db)
        XCTAssertEqual(repl1.neighborPeers.count, 0)

        startMultipeerReplicator(repl1)
        XCTAssertEqual(repl1.neighborPeers.count, 0)

        let repl2 = try multipeerReplicator(for: self.otherDB!)
        XCTAssertEqual(repl2.neighborPeers.count, 0)

        startMultipeerReplicator(repl2)
        waitForReplicatorStatus(for: repl1, peerID: repl2.peerID, activityLevel: .idle)
        waitForReplicatorStatus(for: repl2, peerID: repl1.peerID, activityLevel: .idle)

        XCTAssertEqual(repl1.neighborPeers.count, 1)
        XCTAssertEqual(repl1.neighborPeers[0], repl2.peerID)

        XCTAssertEqual(repl2.neighborPeers.count, 1)
        XCTAssertEqual(repl2.neighborPeers[0], repl1.peerID)

        stopMultipeerReplicator(repl1)
        XCTAssertEqual(repl1.neighborPeers.count, 0)
        
        // Wait to ensure the neighborPeers are updated
        Thread.sleep(forTimeInterval: 5.0)
        XCTAssertEqual(repl2.neighborPeers.count, 0)
        
        stopMultipeerReplicator(repl2)
        XCTAssertEqual(repl2.neighborPeers.count, 0)
    }

    /**
     ### 18. TestPeerInfo

     #### Description
     Verify that retrieving peer info returns the expected PeerInfo object for known peers.
     If the peer is unknown, ensure that nil is returned as expected.

     #### Steps
     1. Create a MultipeerReplicator#1 for a database with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: An authenticator with a callback that returns true.
         - collections: Collection configs containing the default collection.
     2. Create MultipeerReplicator#2 for db#2 with the following config:
         - peerGroupID: "MultipeerReplTestGroup"
         - identity: A TLSIdentity signed by an issuer from asset #1.
         - authenticator: Authenticator with a callback that returns false.
         - collections: Collection configs containing the default collection.
     3. From MultipeerReplicator#1, get peerInfo using its own peerID.
     4. Verify:
         - The returned peerInfo is not nil.
         - The peerID matches MultipeerReplicator#1’s peerID.
         - The certificate is not nil.
         - neighborPeers is empty.
         - The replicator activity level is STOPPED.
     5. From MultipeerReplicator#1, get peerInfo using MultipeerReplicator#2’s peerID.
     6. Verify that the returned peerInfo is nil as the peer is not yet discovered.
     7. Start both MultipeerReplicators.
     8. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
     9. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
     10. Re-fetch peerInfo from MultipeerReplicator#1 using both its own and MultipeerReplicator#2’s peerID.
     11.    Verify MultipeerReplicator#1's own peerInfo:
         - neighborPeers contains Replicator#2's peerID.
         - Activity level is STOPPED as no replication to itself
     12.    Verify MultipeerReplicator#2' peerInfo:
         - neighborPeers contains Replicator#1's peerID.
         - Activity level is IDLE
     13. Stop both replicators and wait until the replicators are inactive.
     */
    func testPeerInfo() throws {
        let repl1 = try multipeerReplicator(for: db)
        var repl1Peer1 = repl1.peerInfo(for: repl1.peerID)
        XCTAssertNotNil(repl1Peer1)
        XCTAssertEqual(repl1Peer1?.peerID, repl1.peerID)
        XCTAssertNotNil(repl1Peer1?.certificate)
        XCTAssertEqual(repl1Peer1?.neighborPeers.count, 0)
        XCTAssertEqual(repl1Peer1?.replicatorStatus.activity, .stopped)

        let repl2 = try multipeerReplicator(for: otherDB!)
        var repl1Peer2 = repl1.peerInfo(for: repl2.peerID)
        XCTAssertNil(repl1Peer2)

        startMultipeerReplicator(repl1)
        startMultipeerReplicator(repl2)

        waitForReplicatorStatus(for: repl1, peerID: repl2.peerID, activityLevel: .idle)
        waitForReplicatorStatus(for: repl2, peerID: repl1.peerID, activityLevel: .idle)

        repl1Peer1 = repl1.peerInfo(for: repl1.peerID)
        XCTAssertNotNil(repl1Peer1)
        XCTAssertEqual(repl1Peer1?.neighborPeers.count, 1)
        XCTAssertEqual(repl1Peer1?.neighborPeers.first, repl2.peerID)
        XCTAssertEqual(repl1Peer1?.replicatorStatus.activity, .stopped) // No replication to itself

        repl1Peer2 = repl1.peerInfo(for: repl2.peerID)
        XCTAssertNotNil(repl1Peer2)
        XCTAssertEqual(repl1Peer2?.neighborPeers.count, 1)
        XCTAssertEqual(repl1Peer2?.neighborPeers.first, repl1.peerID)
        XCTAssertEqual(repl1Peer2?.replicatorStatus.activity, .idle)

        stopMultipeerReplicator(repl1)
        stopMultipeerReplicator(repl2)
    }
}
