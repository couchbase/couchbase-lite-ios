//
//  URLEndpointListenerTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc. All rights reserved.
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

class URLEndpointListenerTest: ReplicatorTest {
    let wsPort: UInt16 = 4084
    let wssPort: UInt16 = 4085
    let serverCertLabel = "CBL-Server-Cert"
    let clientCertLabel = "CBL-Client-Cert"
    
    var listener: URLEndpointListener?
    
    override func setUpWithError() throws { }
    
    // MARK: --  Helper methods
    // MARK: Listener Helper methods
    @discardableResult
    func startListener(tls: Bool = true, auth: ListenerAuthenticator? = nil) throws -> URLEndpointListener {
        // Stop:
        if let listener = self.listener {
            listener.stop()
        }
        
        // Listener:
        var config = URLEndpointListenerConfiguration.init(collections: [self.otherDB_defaultCollection!])
        config.port = tls ? wssPort : wsPort
        config.disableTLS = !tls
        config.authenticator = auth
        
        return try startListener(withConfig: config)
    }
    
    @discardableResult
    func startListener(withConfig config: URLEndpointListenerConfiguration) throws -> URLEndpointListener {
        self.listener = URLEndpointListener(config: config)
        
        // Start:
        try self.listener!.start()
        
        return self.listener!
    }
    
    func stopListener(listener: URLEndpointListener? = nil) throws {
        let l = listener ?? self.listener
        
        l?.stop()
        if let id = l?.tlsIdentity {
            try id.deleteFromKeyChain()
        }
    }
    
    func cleanUpIdentities() throws {
        self.ignoreException {
            try URLEndpointListener.deleteAnonymousIdentities()
        }
    }
    
    // MARK: TLS Identity helpers
    
    func createTLSIdentity(isServer: Bool = true) throws -> TLSIdentity? {
        if !self.keyChainAccessAllowed { return nil }
        
        let label = isServer ? serverCertLabel : clientCertLabel
        
        // cleanup client cert authenticator identity
        try TLSIdentity.deleteIdentity(withLabel: label)
        
        // Create client identity:
        let attrs = [certAttrCommonName: isServer ? "CBL-Server" : "daniel"]
        let keyUsages: KeyUsages = isServer ? .serverAuth : .clientAuth
        return try TLSIdentity.createIdentity(for: keyUsages, attributes: attrs, expiration: nil,
                                              label: label)
    }
    
    func checkCertificateEqual(cert cert1: SecCertificate, andCert cert2: SecCertificate) {
        var cn1: CFString?
        XCTAssertEqual(SecCertificateCopyCommonName(cert1, &cn1), errSecSuccess)
        
        var cn2: CFString?
        XCTAssertEqual(SecCertificateCopyCommonName(cert2, &cn2), errSecSuccess)
        
        XCTAssertEqual(cn1! as String, cn2! as String)
    }
    
    // MARK: Replicator helper methods
    
    /// - Note: default value for continuous is true! Thats is common in this test suite
    func createReplicator(db: Database,
                          target: Endpoint,
                          continuous: Bool = true,
                          type: ReplicatorType = .pushAndPull,
                          serverCert: SecCertificate? = nil) -> Replicator {
        let db_defaultCollection = try! db.defaultCollection()
        var config = ReplicatorConfiguration(target: target)
        config.replicatorType = type
        config.continuous = continuous
        config.pinnedServerCertificate = serverCert
        config.addCollection(db_defaultCollection)
        return Replicator(config: config)
    }
    
    override func setUp() {
        super.setUp()
        try! cleanUpIdentities()
    }
    
    override func tearDown() {
        try! stopListener()
        try! cleanUpIdentities()
        super.tearDown()
    }
}

class URLEndpointListenerTest_Main: URLEndpointListenerTest {
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: Reusable helper methods
    
    /// Two replicators, replicates docs to the self.listener;
    /// pushAndPull
    func validateMultipleReplicationsTo(_ listener: URLEndpointListener, type: ReplicatorType) throws {
        let exp1 = expectation(description: "replicator#1 stop")
        let exp2 = expectation(description: "replicator#2 stop")
        let count = listener.config.database.count
        
        // open DBs
        try deleteDB(name: "db1")
        try deleteDB(name: "db2")
        let db1 = try openDB(name: "db1")
        let db2 = try openDB(name: "db2")
        let db1_defaultCollection = try db1.defaultCollection()
        let db2_defaultCollection = try db2.defaultCollection()
        
        // For keeping the replication long enough to validate connection status, we will use blob
        let imageData = try dataFromResource(name: "image", ofType: "jpg")
        
        // DB#1
        let doc1 = createDocument()
        let blob1 = Blob(contentType: "image/jpg", data: imageData)
        doc1.setBlob(blob1, forKey: "blob")
        try db1_defaultCollection.save(document: doc1)
        
        // DB#2
        let doc2 = createDocument()
        let blob2 = Blob(contentType: "image/jpg", data: imageData)
        doc2.setBlob(blob2, forKey: "blob")
        try db2_defaultCollection.save(document: doc2)
        
        let repl1 = createReplicator(db: db1,
                                     target: listener.localURLEndpoint,
                                     continuous: false,
                                     type: type,
                                     serverCert: listener.tlsIdentity!.certs[0])
        let repl2 = createReplicator(db: db2,
                                     target: listener.localURLEndpoint,
                                     continuous: false,
                                     type: type,
                                     serverCert: listener.tlsIdentity!.certs[0])
        let changeListener = { (change: ReplicatorChange) in
            if change.status.activity == .stopped {
                if change.replicator.config.database.name == "db1" {
                    exp1.fulfill()
                } else {
                    exp2.fulfill()
                }
            }
            
        }
        let token1 = repl1.addChangeListener(changeListener)
        let token2 = repl2.addChangeListener(changeListener)
        
        repl1.start()
        repl2.start()
        wait(for: [exp1, exp2], timeout: CBLTestCase.expTimeout)
        
        // pushAndPull might cause race, so only checking push
        if type == .push {
            XCTAssertEqual(listener.config.database.count, count + 2);
        }
        
        // pushAndPull might cause race, so only checking pull
        if type == .pull {
            XCTAssertEqual(db1.count, count + 1); // existing docs + pulls one doc from db#2
            XCTAssertEqual(db2.count, count + 1); // existing docs + pulls one doc from db#1
        }
        
        repl1.removeChangeListener(withToken: token1)
        repl2.removeChangeListener(withToken: token2)
        
        try db1.close()
        try db2.close()
    }
    
    func validateActiveReplicationsAndURLEndpointListener(isDeleteDBs: Bool) throws {
        if !self.keyChainAccessAllowed { return }
        
        let idleExp1 = allowOverfillExpectation(description: "replicator#1 idle")
        let idleExp2 = allowOverfillExpectation(description: "replicator#2 idle")
        let stopExp1 = expectation(description: "replicator#1 stop")
        let stopExp2 = expectation(description: "replicator#2 stop")
        
        let doc1 = createDocument("db-doc")
        try self.defaultCollection!.save(document: doc1)
        let doc2 = createDocument("other-db-doc")
        try self.otherDB_defaultCollection!.save(document: doc2)
        
        // start listener
        try startListener()
        
        // replicator#1
        let repl1 = createReplicator(db: self.otherDB!, target: DatabaseEndpoint(database: self.db))
        
        // replicator#2
        try deleteDB(name: "db2")
        let db2 = try openDB(name: "db2")
        let repl2 = createReplicator(db: db2,
                                     target: self.listener!.localURLEndpoint,
                                     serverCert: self.listener!.tlsIdentity!.certs[0])
        
        let changeListener = { (change: ReplicatorChange) in
            if change.status.activity == .idle && change.status.progress.completed == change.status.progress.total {
                if change.replicator.config.database.name == "db2" {
                    idleExp2.fulfill()
                } else {
                    idleExp1.fulfill()
                }
            } else if change.status.activity == .stopped {
                if change.replicator.config.database.name == "db2" {
                    stopExp2.fulfill()
                } else {
                    stopExp1.fulfill()
                }
            }
        }
        let token1 = repl1.addChangeListener(changeListener)
        let token2 = repl2.addChangeListener(changeListener)
        repl1.start()
        repl2.start()
        wait(for: [idleExp1, idleExp2], timeout: CBLTestCase.expTimeout)
        
        if (isDeleteDBs) {
            try db2.delete()
            try self.otherDB!.delete()
        } else {
            try db2.close()
            try self.otherDB!.close()
        }
        
        wait(for: [stopExp1, stopExp2], timeout: CBLTestCase.expTimeout)
        repl1.removeChangeListener(withToken: token1)
        repl2.removeChangeListener(withToken: token2)
        try stopListener()
    }
    
    func validateActiveReplicatorAndURLEndpointListeners(isDeleteDB: Bool) throws {
        if !self.keyChainAccessAllowed { return }
        
        let idleExp = allowOverfillExpectation(description: "replicator idle")
        let stopExp = expectation(description: "replicator stop")
        
        let config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        let listener1 = URLEndpointListener(config: config)
        let listener2 = URLEndpointListener(config: config)
        
        // listener
        try listener1.start()
        try listener2.start()
        
        let doc1 = createDocument("db-doc")
        try self.defaultCollection!.save(document: doc1)
        let doc2 = createDocument("other-db-doc")
        try self.otherDB_defaultCollection!.save(document: doc2)
        
        // replicator
        let repl1 = createReplicator(db: self.otherDB!,
                                     target: listener1.localURLEndpoint,
                                     serverCert: listener1.tlsIdentity!.certs[0])
        let token1 = repl1.addChangeListener({ (change: ReplicatorChange) in
            if change.status.activity == .idle && change.status.progress.completed == change.status.progress.total {
                idleExp.fulfill()
                
            } else if change.status.activity == .stopped {
                stopExp.fulfill()
            }
        })
        repl1.start()
        wait(for: [idleExp], timeout: CBLTestCase.expTimeout)
        
        if (isDeleteDB) {
            try self.otherDB!.delete()
        } else {
            try self.otherDB!.close()
        }
        
        wait(for: [stopExp], timeout: CBLTestCase.expTimeout)
        
        // cleanup
        repl1.removeChangeListener(withToken: token1)
        try stopListener(listener: listener1)
        try stopListener(listener: listener2)
    }
    
    // MARK: -- Tests
    
    func testPort() throws {
        if !self.keyChainAccessAllowed { return }
        
        var config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        config.port = wsPort
        self.listener = URLEndpointListener(config: config)
        XCTAssertNil(self.listener!.port)
        
        // Start:
        try self.listener!.start()
        XCTAssertEqual(self.listener!.port, wsPort)

        try stopListener()
        XCTAssertNil(self.listener!.port)
    }
    
    func testEmptyPort() throws {
        if !self.keyChainAccessAllowed { return }
        
        let config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        self.listener = URLEndpointListener(config: config)
        XCTAssertNil(self.listener!.port)
        
        // Start:
        try self.listener!.start()
        XCTAssertNotEqual(self.listener!.port, 0)

        try stopListener()
        XCTAssertNil(self.listener!.port)
    }
    
    func testBusyPort() throws {
        if !self.keyChainAccessAllowed { return }
        
        try startListener()
        
        var config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        config.port = self.listener!.port
        let listener2 = URLEndpointListener(config: config)
        
        expectError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE)) {
            try listener2.start()
        }
    }
    
    func testURLs() throws {
        if !self.keyChainAccessAllowed { return }
        
        var config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        config.port = wsPort
        self.listener = URLEndpointListener(config: config)
        XCTAssertNil(self.listener!.urls)
        
        // Start:
        try self.listener!.start()
        XCTAssert(self.listener!.urls?.count != 0)

        try stopListener()
        XCTAssertNil(self.listener!.urls)
    }
    
    func testTLSListenerAnonymousIdentity() throws {
        if !self.keyChainAccessAllowed { return }
        
        let doc = createDocument("doc-1")
        try self.otherDB_defaultCollection!.save(document: doc)
        
        let config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        let listener = URLEndpointListener(config: config)
        XCTAssertNil(listener.tlsIdentity)
        try listener.start()
        XCTAssertNotNil(listener.tlsIdentity)
        
        // anonymous identity
        run(target: listener.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: nil,
            serverCert: listener.tlsIdentity!.certs[0])
        
        // Different pinned cert
        try TLSIdentity.deleteIdentity(withLabel: "dummy")
        let tlsID = try TLSIdentity.createIdentity(for: .clientAuth,
                                                   attributes: [certAttrCommonName: "client"],
                                                   expiration: nil, label: "dummy")
        run(target: listener.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: nil,
            serverCert: tlsID.certs[0],
            expectedError: CBLError.tlsCertUnknownRoot)
        try TLSIdentity.deleteIdentity(withLabel: "dummy")
        
        // No pinned cert
        run(target: listener.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: nil,
            serverCert: nil,
            expectedError: CBLError.tlsCertUnknownRoot)
        
        try stopListener(listener: listener)
        XCTAssertNil(listener.tlsIdentity)
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
    }
    
    func testTLSListenerUserIdentity() throws {
        if !self.keyChainAccessAllowed { return }
        
        let doc = createDocument("doc-1")
        try self.otherDB_defaultCollection!.save(document: doc)
        
        let tls = try createTLSIdentity()
        var config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        config.tlsIdentity = tls
        let listener = URLEndpointListener(config: config)
        XCTAssertNil(listener.tlsIdentity)
        try listener.start()
        XCTAssertNotNil(listener.tlsIdentity)
        
        run(target: listener.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: nil,
            serverCert: listener.tlsIdentity!.certs[0])
        
        // Different pinned cert
        try TLSIdentity.deleteIdentity(withLabel: "dummy")
        let tlsID = try TLSIdentity.createIdentity(for: .clientAuth,
                                                   attributes: [certAttrCommonName: "client"],
                                                   expiration: nil, label: "dummy")
        run(target: listener.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: nil,
            serverCert: tlsID.certs[0],
            expectedError: CBLError.tlsCertUnknownRoot)
        try TLSIdentity.deleteIdentity(withLabel: "dummy")
        
        // No pinned cert
        run(target: listener.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: nil,
            serverCert: nil,
            expectedError: CBLError.tlsCertUnknownRoot)
        
        try stopListener(listener: listener)
        XCTAssertNil(listener.tlsIdentity)
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
    }
    
    func testNonTLSNullListenerAuthenticator() throws {
        if !self.keyChainAccessAllowed { return }
        
        let listener = try startListener(tls: false)
        XCTAssertNil(listener.tlsIdentity)
        
        // Replicator - No Authenticator:
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false)
        
        // Replicator - Basic Authenticator:
        let auth = BasicAuthenticator.init(username: "daniel", password: "123")
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: auth)
        
        // Replicator - Client Cert Authenticator
        let certAuth = ClientCertificateAuthenticator(identity: try createTLSIdentity(isServer: false)!)
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: certAuth)
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        
        // Cleanup:
        try stopListener()
    }
       
    func testNonTLSPasswordListenerAuthenticator() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Listener:
        let listenerAuth = ListenerPasswordAuthenticator.init {
            (username, password) -> Bool in
            return (username as NSString).isEqual(to: "daniel") &&
                (password as NSString).isEqual(to: "123")
        }
        let listener = try startListener(tls: false, auth: listenerAuth)
        
        // Replicator - No Authenticator:
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: nil, expectedError: CBLError.httpAuthRequired)
        
        // Replicator - Wrong Username:
        var auth = BasicAuthenticator.init(username: "daneil", password: "123")
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: auth, expectedError: CBLError.httpAuthRequired)
        
        // Replicator - Wrong Password:
        auth = BasicAuthenticator.init(username: "daniel", password: "456")
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: auth, expectedError: CBLError.httpAuthRequired)
        
        // Replicator - Client Cert Authenticator
        let certAuth = ClientCertificateAuthenticator(identity: try createTLSIdentity(isServer: false)!)
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: certAuth, expectedError: CBLError.httpAuthRequired)
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        
        // Replicator - Success:
        auth = BasicAuthenticator.init(username: "daniel", password: "123")
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: auth)
        
        // Cleanup:
        try stopListener()
    }
    
    func testClientCertAuthWithCallback() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Listener:
        let listenerAuth = ListenerCertificateAuthenticator.init { (certs) -> Bool in
            XCTAssertEqual(certs.count, 1)
            var commongName: CFString?
            let status = SecCertificateCopyCommonName(certs[0], &commongName)
            XCTAssertEqual(status, errSecSuccess)
            XCTAssertNotNil(commongName)
            XCTAssertEqual((commongName! as String), "daniel")
            return true
        }
        let listener = try startListener(auth: listenerAuth)
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Replicator:
        let auth = ClientCertificateAuthenticator(identity: try createTLSIdentity(isServer: false)!)
        let serverCert = listener.tlsIdentity!.certs[0]
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: auth, serverCert: serverCert)
        
        // Cleanup:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        try stopListener()
    }
    
    func testClientCertAuthWithCallbackError() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Listener:
        let listenerAuth = ListenerCertificateAuthenticator.init { (certs) -> Bool in
            XCTAssertEqual(certs.count, 1)
            return false
        }
        let listener = try startListener(auth: listenerAuth)
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Replicator:
        let auth = ClientCertificateAuthenticator(identity: try createTLSIdentity(isServer: false)!)
        let serverCert = listener.tlsIdentity!.certs[0]
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: auth, serverCert: serverCert, expectedError: CBLError.tlsClientCertRejected)
        
        // Cleanup:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        try stopListener()
    }
    
    func testClientCertAuthWithRootCerts() throws {
        #if os(macOS)
        try XCTSkipIf(true, "CBL-7005 : importIdentityWithData not working on newer macOS")
        #endif
        
        if !self.keyChainAccessAllowed { return }
        
        // Root Cert:
        let rootCertData = try dataFromResource(name: "identity/client-ca", ofType: "der")
        let rootCert = SecCertificateCreateWithData(kCFAllocatorDefault, rootCertData as CFData)!
        
        // Listener:
        let listenerAuth = ListenerCertificateAuthenticator.init(rootCerts: [rootCert])
        let listener = try startListener(auth: listenerAuth)
        
        // Cleanup:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        
        // Create client identity:
        let clientCertData = try dataFromResource(name: "identity/client", ofType: "p12")
        let identity = try TLSIdentity.importIdentity(withData: clientCertData, password: "123", label: clientCertLabel)
        
        // Replicator:
        let auth = ClientCertificateAuthenticator.init(identity: identity)
        let serverCert = listener.tlsIdentity!.certs[0]
        
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: auth, serverCert: serverCert)
        }
        
        // Cleanup:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        try stopListener()
    }
    
    func testClientCertAuthWithRootCertsError() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Root Cert:
        let rootCertData = try dataFromResource(name: "identity/client-ca", ofType: "der")
        let rootCert = SecCertificateCreateWithData(kCFAllocatorDefault, rootCertData as CFData)!
        
        // Listener:
        let listenerAuth = ListenerCertificateAuthenticator.init(rootCerts: [rootCert])
        let listener = try startListener(auth: listenerAuth)
        
        // Replicator:
        let auth = ClientCertificateAuthenticator.init(identity: try createTLSIdentity(isServer: false)!)
        let serverCert = listener.tlsIdentity!.certs[0]
        
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     auth: auth, serverCert: serverCert, expectedError: CBLError.tlsClientCertRejected)
        }
        
        // Cleanup:
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        try stopListener()
    }
    
    func testConnectionStatus() throws {
        if !self.keyChainAccessAllowed { return }
        
        let replicatorStop = expectation(description: "replicator stop")
        let pullFilterBusy = expectation(description: "pull filter busy")
        var config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        config.port = wsPort
        config.disableTLS = true
        self.listener = URLEndpointListener(config: config)
        XCTAssertEqual(self.listener!.status.connectionCount, 0)
        XCTAssertEqual(self.listener!.status.activeConnectionCount, 0)
        
        // Start:
        try self.listener!.start()
        XCTAssertEqual(self.listener!.status.connectionCount, 0)
        XCTAssertEqual(self.listener!.status.activeConnectionCount, 0)
        
        let doc1 = createDocument()
        try self.otherDB_defaultCollection!.save(document: doc1)
        
        var maxConnectionCount: UInt64 = 0, maxActiveCount:UInt64 = 0
        var rConfig = ReplicatorConfiguration(target: self.listener!.localURLEndpoint)
        rConfig.replicatorType = .pull
        rConfig.continuous = false
        var colConfig = CollectionConfiguration()
        colConfig.pullFilter = { (doc, flags) -> Bool in
            let s = self.listener!.status
            maxConnectionCount = max(s.connectionCount, maxConnectionCount)
            maxActiveCount = max(s.activeConnectionCount, maxActiveCount)
            pullFilterBusy.fulfill()
            return true
        }
        
        rConfig.addCollection(defaultCollection!, config: colConfig)
        let repl: Replicator = Replicator(config: rConfig)
        let token = repl.addChangeListener { (change) in
            if change.status.activity == .stopped {
                replicatorStop.fulfill()
            }
        }
        
        repl.start()
        wait(for: [pullFilterBusy, replicatorStop], timeout: CBLTestCase.expTimeout)
        repl.removeChangeListener(withToken: token)
        
        XCTAssertEqual(maxConnectionCount, 1)
        XCTAssertEqual(maxActiveCount, 1)
        XCTAssertEqual(self.otherDB_defaultCollection!.count, 1)

        try stopListener()
        XCTAssertEqual(self.listener!.status.connectionCount, 0)
        XCTAssertEqual(self.listener!.status.activeConnectionCount, 0)
    }
    
    func testMultipleListenersOnSameDatabase() throws {
        if !self.keyChainAccessAllowed { return }
        
        let config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        let listener1 = URLEndpointListener(config: config)
        let listener2 = URLEndpointListener(config: config)
        
        try listener1.start()
        try listener2.start()
        
        try generateDocument(withID: "doc-1")
        self.run(target: listener1.localURLEndpoint,
                 type: .pushAndPull,
                 continuous: false,
                 auth: nil,
                 serverCert: listener1.tlsIdentity!.certs[0])
        
        // since listener1 and listener2 are using same certificates, one listener only needs stop.
        listener2.stop()
        try stopListener(listener: listener1)
        XCTAssertEqual(self.otherDB_defaultCollection!.count, 1)
    }
    
    func testCloseWithActiveListener() throws {
        if !self.keyChainAccessAllowed { return }
        
        try startListener()
        
        // Close database should also stop the listener:
        try self.otherDB!.close()
        
        XCTAssertNil(self.listener!.port)
        XCTAssertNil(self.listener!.urls)
        
        try stopListener()
    }
    
    func testEmptyNetworkInterface() throws {
        if !self.keyChainAccessAllowed { return }
        
        try startListener()
        let urls = self.listener!.urls!
        
        /// Link local addresses cannot be assigned via network interface because they don't map to any given interface.
        let notLinkLocal: [URL] = urls.filter { !$0.host!.contains(":") && !$0.host!.contains(".local")}
        
        for (i, url) in notLinkLocal.enumerated() {
            // separate db instance!
            let db = try Database(name: "db-\(i)")
            let db_defaultCollection = try! db.defaultCollection()
            let doc = createDocument()
            doc.setString(url.absoluteString, forKey: "url")
            try db_defaultCollection.save(document: doc)
            
            // separate replicator instance
            let target = URLEndpoint(url: url)
            var rConfig = ReplicatorConfiguration(target: target)
            rConfig.pinnedServerCertificate = self.listener?.tlsIdentity!.certs[0]
            rConfig.addCollection(db_defaultCollection)
            run(config: rConfig, expectedError: nil)
            
            // remove the db
            try db.delete()
        }
        
        XCTAssertEqual(self.otherDB_defaultCollection!.count, UInt64(notLinkLocal.count))
        
        let q = QueryBuilder.select([SelectResult.all()]).from(DataSource.collection(self.otherDB_defaultCollection!))
        let rs = try q.execute()
        var result = [URL]()
        for res in rs.allResults() {
            let dict = res.dictionary(at: 0)
            result.append(URL(string: dict!.string(forKey: "url")!)!)
        }
        
        XCTAssertEqual(result, notLinkLocal)
        try stopListener()
    }
    
    func testMultipleReplicatorsToListener() throws {
        if !self.keyChainAccessAllowed { return }
        
        try startListener()
        
        let doc = createDocument()
        doc.setString("Tiger", forKey: "species")
        try self.otherDB_defaultCollection!.save(document: doc)
        
        // pushAndPull can cause race; so only push is validated
        try validateMultipleReplicationsTo(self.listener!, type: .push)
        
        try stopListener()
    }
    
    func testMultipleReplicatorsToReadOnlyListener() throws {
        if !self.keyChainAccessAllowed { return }
        
        var config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        config.readOnly = true
        try startListener(withConfig: config)
        
        let doc = createDocument()
        doc.setString("Tiger", forKey: "species")
        try self.otherDB_defaultCollection!.save(document: doc)
        
        try validateMultipleReplicationsTo(self.listener!, type: .pull)
        
        try stopListener()
    }
    
    func testReadOnlyListener() throws {
        if !self.keyChainAccessAllowed { return }
        
        let doc1 = createDocument()
        try self.defaultCollection!.save(document: doc1)
        
        var config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        config.readOnly = true
        try startListener(withConfig: config)
        
        self.run(target: self.listener!.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: nil, serverCert: self.listener!.tlsIdentity!.certs[0],
                 expectedError: CBLError.httpForbidden)
    }
    
    func testReplicatorServerCertificate() throws {
        if !self.keyChainAccessAllowed { return }
        
        let x1 = allowOverfillExpectation(description: "idle")
        let x2 = expectation(description: "stopped")
        
        let listener = try startListener()
        
        let serverCert = listener.tlsIdentity!.certs[0]
        let repl = createReplicator(db: self.otherDB!,
                              target: listener.localURLEndpoint,
                              serverCert: serverCert)
        repl.addChangeListener { (change) in
            let activity = change.status.activity
            if activity == .idle {
                x1.fulfill()
            } else if activity == .stopped && change.status.error == nil {
                x2.fulfill()
            }
        }
        XCTAssertNil(repl.serverCertificate)
        
        repl.start()
        
        wait(for: [x1], timeout: CBLTestCase.expTimeout)
        var receivedServerCert = repl.serverCertificate
        XCTAssertNotNil(receivedServerCert)
        checkCertificateEqual(cert: serverCert, andCert: receivedServerCert!)
        
        repl.stop()
        
        wait(for: [x2], timeout: CBLTestCase.expTimeout)
        receivedServerCert = repl.serverCertificate
        XCTAssertNotNil(receivedServerCert)
        checkCertificateEqual(cert: serverCert, andCert: receivedServerCert!)
        
        try stopListener()
    }
    
    func testReplicatorServerCertificateWithTLSError() throws {
        if !self.keyChainAccessAllowed { return }
        
        var x1 = expectation(description: "stopped")
        
        let listener = try startListener()
        
        var serverCert = listener.tlsIdentity!.certs[0]
        var repl = createReplicator(db: self.otherDB!, target: listener.localURLEndpoint)
        repl.addChangeListener { (change) in
            let activity = change.status.activity
            if activity == .stopped && change.status.error != nil {
                // TODO: https://issues.couchbase.com/browse/CBL-1471
                XCTAssertEqual((change.status.error! as NSError).code, CBLError.tlsCertUnknownRoot)
                x1.fulfill()
            }
        }
        XCTAssertNil(repl.serverCertificate)
        
        repl.start()
        
        wait(for: [x1], timeout: CBLTestCase.expTimeout)
        var receivedServerCert = repl.serverCertificate
        XCTAssertNotNil(receivedServerCert)
        checkCertificateEqual(cert: serverCert, andCert: receivedServerCert!)
        
        // Use the receivedServerCert to pin:
        x1 = allowOverfillExpectation(description: "idle")
        let x2 = expectation(description: "stopped")
        serverCert = receivedServerCert!
        repl = createReplicator(db: self.otherDB!,
                                target: listener.localURLEndpoint,
                                serverCert: serverCert)
        repl.addChangeListener { (change) in
            let activity = change.status.activity
            if activity == .idle {
                x1.fulfill()
            } else if activity == .stopped && change.status.error == nil {
                x2.fulfill()
            }
        }
        XCTAssertNil(repl.serverCertificate)
        
        repl.start()
        
        wait(for: [x1], timeout: CBLTestCase.expTimeout)
        receivedServerCert = repl.serverCertificate
        XCTAssertNotNil(receivedServerCert)
        checkCertificateEqual(cert: serverCert, andCert: receivedServerCert!)
        
        repl.stop()
        
        wait(for: [x2], timeout: CBLTestCase.expTimeout)
        receivedServerCert = repl.serverCertificate
        XCTAssertNotNil(receivedServerCert)
        checkCertificateEqual(cert: serverCert, andCert: receivedServerCert!)
        
        try stopListener()
    }
    
    func testReplicatorServerCertificateWithTLSDisabled() throws {
        let x1 = allowOverfillExpectation(description: "idle")
        let x2 = expectation(description: "stopped")
        
        let listener = try startListener(tls: false)
        let repl = createReplicator(db: self.otherDB!, target: listener.localURLEndpoint)
        repl.addChangeListener { (change) in
            let activity = change.status.activity
            if activity == .idle {
                x1.fulfill()
            } else if activity == .stopped && change.status.error == nil {
                x2.fulfill()
            }
        }
        XCTAssertNil(repl.serverCertificate)
        
        repl.start()
        
        wait(for: [x1], timeout: CBLTestCase.expTimeout)
        XCTAssertNil(repl.serverCertificate)
        
        repl.stop()
        
        wait(for: [x2], timeout: CBLTestCase.expTimeout)
        XCTAssertNil(repl.serverCertificate)
        
        try stopListener()
    }
    
    func testAcceptOnlySelfSignedServerCertificate() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Listener:
        let listener = try startListener()
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Replicator - TLS Error:
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     acceptSelfSignedOnly: false, serverCert: nil, expectedError: CBLError.tlsCertUnknownRoot)
        }
        
        // Replicator - Success:
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     acceptSelfSignedOnly: true, serverCert: nil)
        }
        
        // Cleanup
        try stopListener()
    }
    
    func testPinnedServerCertificate() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Listener:
        let listener = try startListener()
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Replicator - TLS Error:
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     acceptSelfSignedOnly: false, serverCert: nil, expectedError: CBLError.tlsCertUnknownRoot)
        }
        
        // Replicator - Success:
        self.ignoreException {
            let serverCert = listener.tlsIdentity!.certs[0]
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     acceptSelfSignedOnly: false, serverCert: serverCert)
        }
        
        // Cleanup
        try stopListener()
    }
    
    func testListenerWithImportIdentity() throws {
        #if os(macOS)
        try XCTSkipIf(true, "CBL-7005 : importIdentityWithData not working on newer macOS")
        #endif
        
        if !self.keyChainAccessAllowed { return }
        
        let data = try dataFromResource(name: "identity/certs", ofType: "p12")
        var identity: TLSIdentity!
        self.ignoreException {
            identity = try TLSIdentity.importIdentity(withData: data,
                                                      password: "123",
                                                      label: self.serverCertLabel)
        }
        XCTAssertEqual(identity.certs.count, 2)
        
        var config = URLEndpointListenerConfiguration.init(collections: [self.otherDB_defaultCollection!])
        config.tlsIdentity = identity
        
        self.ignoreException {
            try self.startListener(withConfig: config)
        }
        
        XCTAssertNotNil(listener!.tlsIdentity)
        XCTAssert(identity === listener!.tlsIdentity!)
        
        try generateDocument(withID: "doc-1")
        XCTAssertEqual(self.otherDB_defaultCollection!.count, 0)
        self.run(target: listener!.localURLEndpoint,
                 type: .pushAndPull,
                 continuous: false,
                 auth: nil,
                 serverCert: listener!.tlsIdentity!.certs[0])
        XCTAssertEqual(self.otherDB_defaultCollection!.count, 1)
        
        try stopListener(listener: listener!)
        XCTAssertNil(listener!.tlsIdentity)
    }
    
    func testStopListener() throws {
        let x1 = allowOverfillExpectation(description: "idle")
        let x2 = expectation(description: "stopped")
        
        // Listen:
        let listener = try startListener(tls: false)
        
        // Start replicator:
        let target = listener.localURLEndpoint
        let repl = createReplicator(db: self.otherDB!, target: target)
        repl.addChangeListener { (change) in
            let activity = change.status.activity
            if activity == .idle {
                x1.fulfill()
            } else if activity == .stopped {
                x2.fulfill()
            }
        }
        repl.start()
        
        // Wait until idle then stop the listener:
        wait(for: [x1], timeout: CBLTestCase.expTimeout)
        
        // Stop listen:
        try stopListener()
        
        // Wait for the replicator to be stopped:
        wait(for: [x2], timeout: CBLTestCase.expTimeout)
        
        // Check error:
        XCTAssertEqual((repl.status.error! as NSError).code, CBLError.webSocketGoingAway)
        
        // Check to ensure that the replicator is not accessible:
        run(target: target, type: .pushAndPull, continuous: false, auth: nil, serverCert: nil,
            maxAttempts: 2, expectedError: Int(ECONNREFUSED))
    }
    
    func testTLSPasswordListenerAuthenticator() throws {
        if !self.keyChainAccessAllowed { return }
        
        let doc1 = createDocument()
        try self.otherDB_defaultCollection!.save(document: doc1)
        
        // Listener:
        let auth = ListenerPasswordAuthenticator { (username, password) -> Bool in
            return (username as NSString).isEqual(to: "daniel") && (password as NSString).isEqual(to: "123")
        }
        try startListener(auth: auth)
        
        // Replicator - No Authenticator:
        run(target: self.listener!.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: nil,
            serverCert: self.listener!.tlsIdentity!.certs[0],
            expectedError: CBLError.httpAuthRequired)
        
        // Replicator - Wrong Username:
        run(target: self.listener!.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: BasicAuthenticator(username: "daneil", password: "123"),
            serverCert: self.listener!.tlsIdentity!.certs[0],
            expectedError: CBLError.httpAuthRequired)
        
        // Replicator - Wrong Password:
        run(target: self.listener!.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: BasicAuthenticator(username: "daniel", password: "132"),
            serverCert: self.listener!.tlsIdentity!.certs[0],
            expectedError: CBLError.httpAuthRequired)
        
        // Replicator - Different ClientCertAuthenticator
        run(target: self.listener!.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: ClientCertificateAuthenticator(identity: try createTLSIdentity(isServer: false)!),
            serverCert: self.listener!.tlsIdentity!.certs[0],
            expectedError: CBLError.httpAuthRequired)
        
        // cleanup client cert authenticator identity
        try TLSIdentity.deleteIdentity(withLabel: clientCertLabel)
        
        // Replicator - Success:
        run(target: self.listener!.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: BasicAuthenticator(username: "daniel", password: "123"),
            serverCert: self.listener!.tlsIdentity!.certs[0])
    }
    
    func testChainedCertServerAndCertPinning() throws {
        #if os(macOS)
        try XCTSkipIf(true, "CBL-7005 : importIdentityWithData not working on newer macOS")
        #endif
        
        if !keyChainAccessAllowed { return }
        
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        let data = try dataFromResource(name: "identity/certs", ofType: "p12")
        var identity: TLSIdentity!
        ignoreException {
            identity = try TLSIdentity.importIdentity(withData: data,
                                                      password: "123",
                                                      label: self.serverCertLabel)
        }
        XCTAssertEqual(identity.certs.count, 2)
        
        var config = URLEndpointListenerConfiguration.init(collections: [self.otherDB_defaultCollection!])
        config.tlsIdentity = identity
        
        ignoreException {
            try self.startListener(withConfig: config)
        }
        
        // pinning root cert should be successful
        run(target: listener!.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: nil,
            serverCert: identity!.certs[1])
        
        // pinning leaf cert shoud be successful
        run(target: listener!.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: nil,
            serverCert: identity!.certs[0])
        
        try stopListener(listener: listener!)
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
    }
    
    // MARK: acceptSelfSignedOnly tests
    
    func testAcceptSelfSignedWithNonSelfSignedCert() throws {
        #if os(macOS)
        try XCTSkipIf(true, "CBL-7005 : importIdentityWithData not working on newer macOS")
        #endif
        
        if !self.keyChainAccessAllowed { return }
        
        let data = try dataFromResource(name: "identity/certs", ofType: "p12")
        var identity: TLSIdentity!
        self.ignoreException {
            identity = try TLSIdentity.importIdentity(withData: data,
                                                      password: "123",
                                                      label: self.serverCertLabel)
        }
        XCTAssertEqual(identity.certs.count, 2)
        
        var config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        config.tlsIdentity = identity
        
        self.ignoreException {
            try self.startListener(withConfig: config)
        }
        
        try generateDocument(withID: "doc-1")
        XCTAssertEqual(self.otherDB_defaultCollection!.count, 0)
        
        // Reject the server with non-self-signed cert
        run(target: listener!.localURLEndpoint,
            type: .pushAndPull,
            continuous: false,
            auth: nil,
            acceptSelfSignedOnly: true,
            serverCert: nil,
            expectedError: CBLError.tlsCertUntrusted)
        
        try stopListener()
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
    }
    
    func testAcceptOnlySelfSignedCertificateWithPinnedCertificate() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Listener:
        let listener = try startListener()
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // listener = cert1; replicator.pin = cert2; acceptSelfSigned = true => fail
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        let dummyTLSIdentity = try createTLSIdentity()
        self.ignoreException {
            self.run(target: listener.localURLEndpoint,
                     type: .pushAndPull,
                     continuous: false,
                     acceptSelfSignedOnly: true,
                     serverCert: dummyTLSIdentity!.certs[0],
                     expectedError: CBLError.tlsCertUnknownRoot)
        }
        
        // listener = cert1; replicator.pin = cert1; acceptSelfSigned = false => pass
        self.ignoreException {
            self.run(target: listener.localURLEndpoint,
                     type: .pushAndPull,
                     continuous: false,
                     acceptSelfSignedOnly: false,
                     serverCert: listener.tlsIdentity!.certs[0])
        }
        
        // Cleanup
        try stopListener()
        try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
    }
    
    // MARK: -- Close & Delete Replicators and Listeners
    
    func testCloseWithActiveReplicationsAndURLEndpointListener() throws {
        try validateActiveReplicationsAndURLEndpointListener(isDeleteDBs: false)
    }
    
    func testDeleteWithActiveReplicationsAndURLEndpointListener() throws {
        try validateActiveReplicationsAndURLEndpointListener(isDeleteDBs: true)
    }
    
    func testCloseWithActiveReplicatorAndURLEndpointListeners() throws {
        try validateActiveReplicatorAndURLEndpointListeners(isDeleteDB: false)
    }
    
    func testDeleteWithActiveReplicatorAndURLEndpointListeners() throws {
        try validateActiveReplicatorAndURLEndpointListeners(isDeleteDB: true)
    }
    
    // MARK: ListenerConfig
    
    func testSetListenerConfigurationProperties() throws {
        var config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        let basic = ListenerPasswordAuthenticator { (uname, pswd) -> Bool in
            return uname == "username" && pswd == "secret"
        }
        config.authenticator = basic
        config.disableTLS = true
        config.enableDeltaSync = true
        config.networkInterface = "awesomeinterface.com"
        config.port = 3121
        config.readOnly = true
        if self.keyChainAccessAllowed {
            try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
            let tls = try createTLSIdentity()
            config.tlsIdentity = tls
        }
        let listener = URLEndpointListener(config: config)
        
        // ----------
        // update config after passing to configuration’s constructor
        config.authenticator = nil
        config.disableTLS = false
        config.enableDeltaSync = false
        config.networkInterface = "0.0.0.0"
        config.port = 3123
        config.readOnly = false
        
        // update the returned config from listener
        var config2 = listener.config
        config2.authenticator = nil
        config2.disableTLS = false
        config2.enableDeltaSync = false
        config2.networkInterface = "0.0.0.0"
        config2.port = 3123
        config2.readOnly = false
        
        // validate no impact with above updates to configs
        XCTAssertNotNil(listener.config.authenticator)
        XCTAssert(listener.config.disableTLS)
        XCTAssert(listener.config.enableDeltaSync)
        XCTAssertEqual(listener.config.networkInterface, "awesomeinterface.com")
        XCTAssertEqual(listener.config.port, 3121)
        XCTAssert(listener.config.readOnly)
        
        if self.keyChainAccessAllowed {
            XCTAssertNotNil(listener.config.tlsIdentity)
            XCTAssertEqual(listener.config.tlsIdentity!.certs.count, 1)
            
            try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        }
    }
    
    func testDefaultListenerConfiguration() throws {
        let config = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
        
        XCTAssertFalse(config.disableTLS)
        XCTAssertFalse(config.enableDeltaSync)
        XCTAssertFalse(config.readOnly)
        XCTAssertNil(config.authenticator)
        XCTAssertNil(config.networkInterface)
        XCTAssertEqual(config.port, URLEndpointListenerConfiguration.defaultPort)
        XCTAssertNil(config.tlsIdentity)
    }
    
    func testCopyingListenerConfiguration() throws {
        var config1 = URLEndpointListenerConfiguration(collections: [self.otherDB_defaultCollection!])
    
        let basic = ListenerPasswordAuthenticator { (uname, pswd) -> Bool in
            return uname == "username" && pswd == "secret"
        }
        config1.authenticator = basic
        config1.disableTLS = true
        config1.enableDeltaSync = true
        config1.networkInterface = "awesomeinterface.com"
        config1.port = 3121
        config1.readOnly = true
        
        if self.keyChainAccessAllowed {
            try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
            let tls = try createTLSIdentity()
            config1.tlsIdentity = tls
        }
        let config = URLEndpointListenerConfiguration(config: config1)
        
        // ------
        // update config1 after passing to configuration’s constructor
        config1.authenticator = nil
        config1.disableTLS = false
        config1.enableDeltaSync = false
        config1.networkInterface = "0.0.0.0"
        config1.port = 3123
        config1.readOnly = false
        
        XCTAssertNotNil(config.authenticator)
        XCTAssert(config.disableTLS)
        XCTAssert(config.enableDeltaSync)
        XCTAssertEqual(config.networkInterface, "awesomeinterface.com")
        XCTAssertEqual(config.port, 3121)
        XCTAssert(config.readOnly)
        
        if self.keyChainAccessAllowed {
            XCTAssertNotNil(config.tlsIdentity)
            XCTAssertEqual(config.tlsIdentity!.certs.count, 1)
            
            try TLSIdentity.deleteIdentity(withLabel: serverCertLabel)
        }
    }

}

extension URLEndpointListener {
    var localURL: URL {
        assert(self.port != nil && self.port! > UInt16(0))
        var comps = URLComponents()
        comps.scheme = self.config.disableTLS ? "ws" : "wss"
        comps.host = "localhost"
        comps.port = Int(self.port!)
        comps.path = "/\(self.config.database.name)"
        return comps.url!
    }
    
    var localURLEndpoint: URLEndpoint {
        return URLEndpoint.init(url: self.localURL)
    }
}
