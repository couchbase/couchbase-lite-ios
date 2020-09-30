//
//  URLEndpontListenerTest.swift
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

@available(macOS 10.12, iOS 10.0, *)
class URLEndpontListenerTest: ReplicatorTest {
    let wsPort: UInt16 = 4984
    let wssPort: UInt16 = 4985
    let serverCertLabel = "CBL-Server-Cert"
    let clientCertLabel = "CBL-Client-Cert"
    
    var listener: URLEndpointListener?
    
    // MARK: --  Helper methods
    
    @discardableResult
    func listen() throws -> URLEndpointListener {
        return try listen(tls: true, auth: nil)
    }
    
    @discardableResult
    func listen(tls: Bool) throws -> URLEndpointListener {
        return try! listen(tls: tls, auth: nil)
    }
    
    @discardableResult
    func listen(tls: Bool, auth: ListenerAuthenticator?) throws -> URLEndpointListener {
        // Stop:
        if let listener = self.listener {
            listener.stop()
        }
        
        // Listener:
        let config = URLEndpointListenerConfiguration.init(database: self.oDB)
        config.port = tls ? wssPort : wsPort
        config.disableTLS = !tls
        config.authenticator = auth
        
        return try listen(config: config)
    }
    
    @discardableResult
    func listen(config: URLEndpointListenerConfiguration) throws -> URLEndpointListener {
        self.listener = URLEndpointListener.init(config: config)
        
        // Start:
        try self.listener!.start()
        
        return self.listener!
    }
    
    func stopListen() throws {
        if let listener = self.listener {
            try stopListener(listener: listener)
        }
    }
    
    func stopListener(listener: URLEndpointListener) throws {
        let identity = listener.tlsIdentity
        listener.stop()
        if let id = identity {
            try id.deleteFromKeyChain()
        }
    }
    
    func cleanUpIdentities() throws {
        self.ignoreException {
            try URLEndpointListener.deleteAnonymousIdentities()
        }
    }
    
    func replicator(db: Database, continuous: Bool, target: Endpoint, serverCert: SecCertificate?) -> Replicator {
        let config = ReplicatorConfiguration(database: db, target: target)
        config.replicatorType = .pushAndPull
        config.continuous = continuous
        config.pinnedServerCertificate = serverCert
        return Replicator(config: config)
    }
    
    func tlsIdentity(_ isServer: Bool) throws -> TLSIdentity? {
        if !self.keyChainAccessAllowed { return nil }
        
        // Create client identity:
        let attrs = [certAttrCommonName: isServer ? "CBL-Server" : "daniel"]
        let label = isServer ? serverCertLabel : clientCertLabel
        return try TLSIdentity.createIdentity(forServer: false, attributes: attrs, expiration: nil,
                                              label: label)
    }
    
    func cleanupTLSIdentity(_ isServer: Bool) throws {
        if !self.keyChainAccessAllowed { return }
        
        try TLSIdentity.deleteIdentity(withLabel: isServer ? serverCertLabel : clientCertLabel)
    }
    
    /// Two replicators, replicates docs to the self.listener; validates connection status
    func validateMultipleReplicationsTo() throws {
        let exp1 = expectation(description: "replicator#1 stop")
        let exp2 = expectation(description: "replicator#2 stop")
        let count = self.listener!.config.database.count
        
        // open DBs
        try deleteDB(name: "db1")
        try deleteDB(name: "db2")
        let db1 = try openDB(name: "db1")
        let db2 = try openDB(name: "db2")
        
        // For keeping the replication long enough to validate connection status, we will use blob
        let imageData = try dataFromResource(name: "image", ofType: "jpg")
        
        // DB#1
        let doc1 = createDocument()
        let blob1 = Blob(contentType: "image/jpg", data: imageData)
        doc1.setBlob(blob1, forKey: "blob")
        try db1.saveDocument(doc1)
        
        // DB#2
        let doc2 = createDocument()
        let blob2 = Blob(contentType: "image/jpg", data: imageData)
        doc2.setBlob(blob2, forKey: "blob")
        try db2.saveDocument(doc2)
        
        let repl1 = replicator(db: db1,
                               continuous: false,
                               target: self.listener!.localURLEndpoint,
                               serverCert: self.listener!.tlsIdentity!.certs[0])
        let repl2 = replicator(db: db2,
                               continuous: false,
                               target: self.listener!.localURLEndpoint,
                               serverCert: self.listener!.tlsIdentity!.certs[0])
        
        var maxConnectionCount: UInt64 = 0, maxActiveCount: UInt64 = 0
        let changeListener = { (change: ReplicatorChange) in
            if change.status.activity == .busy {
                maxConnectionCount = max(self.listener!.status.connectionCount, maxConnectionCount);
                maxActiveCount = max(self.listener!.status.activeConnectionCount, maxActiveCount);
            }
            
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
        wait(for: [exp1, exp2], timeout: 5.0)
        
        // check both replicators connected to listener
        XCTAssert(maxConnectionCount > 0);
        XCTAssert(maxActiveCount > 0);
        
        // all data are transferred to/from
        XCTAssertEqual(self.listener!.config.database.count, count + 2);
        XCTAssertEqual(db1.count, count + 1/* db2 doc*/);
        XCTAssertEqual(db2.count, count + 1/* db1 doc*/);
        
        repl1.removeChangeListener(withToken: token1)
        repl2.removeChangeListener(withToken: token2)
        
        try db1.close()
        try db2.close()
    }
    
    func checkEqual(cert cert1: SecCertificate, andCert cert2: SecCertificate) {
        if #available(iOS 11, *) {
            var cn1: CFString?
            XCTAssertEqual(SecCertificateCopyCommonName(cert1, &cn1), errSecSuccess)
            
            var cn2: CFString?
            XCTAssertEqual(SecCertificateCopyCommonName(cert2, &cn2), errSecSuccess)
            
            XCTAssertEqual(cn1! as String, cn2! as String)
        }
    }
    
    func validateActiveReplicationsAndURLEndpointListener(isDeleteDBs: Bool) throws {
        if !self.keyChainAccessAllowed { return }
        
        let idleExp1 = expectation(description: "replicator#1 idle")
        let idleExp2 = expectation(description: "replicator#2 idle")
        let stopExp1 = expectation(description: "replicator#1 stop")
        let stopExp2 = expectation(description: "replicator#2 stop")
        
        let doc1 = createDocument("db-doc")
        try self.db.saveDocument(doc1)
        let doc2 = createDocument("other-db-doc")
        try self.oDB.saveDocument(doc2)
        
        // start listener
        try self.listen()
        
        // replicator#1
        let repl1 = replicator(db: self.oDB,
                               continuous: true,
                               target: DatabaseEndpoint(database: self.db),
                               serverCert: nil)
        
        // replicator#2
        try deleteDB(name: "db2")
        let db2 = try openDB(name: "db2")
        let repl2 = replicator(db: db2,
                               continuous: true,
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
        wait(for: [idleExp1, idleExp2], timeout: 5.0)
        
        if (isDeleteDBs) {
            try db2.delete()
            try self.oDB.delete()
        } else {
            try db2.close()
            try self.oDB.close()
        }
        
        wait(for: [stopExp1, stopExp2], timeout: 5.0)
        repl1.removeChangeListener(withToken: token1)
        repl2.removeChangeListener(withToken: token2)
        try stopListen()
    }
    
    func validateActiveReplicatorAndURLEndpointListeners(isDeleteDB: Bool) throws {
        if !self.keyChainAccessAllowed { return }
        
        let idleExp = expectation(description: "replicator idle")
        let stopExp = expectation(description: "replicator stop")
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        let listener1 = URLEndpointListener(config: config)
        let listener2 = URLEndpointListener(config: config)
        
        // listener
        try listener1.start()
        try listener2.start()
        
        let doc1 = createDocument("db-doc")
        try self.db.saveDocument(doc1)
        let doc2 = createDocument("other-db-doc")
        try self.oDB.saveDocument(doc2)
        
        // replicator
        let repl1 = replicator(db: self.oDB,
                               continuous: true,
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
        wait(for: [idleExp], timeout: 5.0)
        
        if (isDeleteDB) {
            try self.oDB.delete()
        } else {
            try self.oDB.close()
        }
        
        wait(for: [stopExp], timeout: 5.0)
        
        // cleanup
        repl1.removeChangeListener(withToken: token1)
        try stopListener(listener: listener1)
        try stopListener(listener: listener2)
    }
    
    override func setUp() {
        super.setUp()
        try! cleanUpIdentities()
    }
    
    override func tearDown() {
        try! stopListen()
        try! cleanUpIdentities()
        super.tearDown()
    }
    
    // MARK: -- Tests
    
    func testPort() throws {
        if !self.keyChainAccessAllowed { return }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.port = wsPort
        self.listener = URLEndpointListener(config: config)
        XCTAssertNil(self.listener!.port)
        
        // Start:
        try self.listener!.start()
        XCTAssertEqual(self.listener!.port, wsPort)

        try stopListen()
        XCTAssertNil(self.listener!.port)
    }
    
    func testEmptyPort() throws {
        if !self.keyChainAccessAllowed { return }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        self.listener = URLEndpointListener(config: config)
        XCTAssertNil(self.listener!.port)
        
        // Start:
        try self.listener!.start()
        XCTAssertNotEqual(self.listener!.port, 0)

        try stopListen()
        XCTAssertNil(self.listener!.port)
    }
    
    func testBusyPort() throws {
        if !self.keyChainAccessAllowed { return }
        
        try listen()
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.port = self.listener!.port
        let listener2 = URLEndpointListener(config: config)
        
        expectError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE)) {
            try listener2.start()
        }
    }
    
    func testURLs() throws {
        if !self.keyChainAccessAllowed { return }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.port = wsPort
        self.listener = URLEndpointListener(config: config)
        XCTAssertNil(self.listener!.urls)
        
        // Start:
        try self.listener!.start()
        XCTAssert(self.listener!.urls?.count != 0)

        try stopListen()
        XCTAssertNil(self.listener!.urls)
    }
    
    func testTLSIdentity() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Disabled TLS:
        var config = URLEndpointListenerConfiguration.init(database: self.oDB)
        config.disableTLS = true
        var listener = URLEndpointListener.init(config: config)
        XCTAssertNil(listener.tlsIdentity)
        
        try listener.start()
        XCTAssertNil(listener.tlsIdentity)
        try stopListener(listener: listener)
        XCTAssertNil(listener.tlsIdentity)
        
        // Anonymous Identity:
        config = URLEndpointListenerConfiguration.init(database: self.oDB)
        listener = URLEndpointListener.init(config: config)
        XCTAssertNil(listener.tlsIdentity)
        
        try listener.start()
        XCTAssertNotNil(listener.tlsIdentity)
        try stopListener(listener: listener)
        XCTAssertNil(listener.tlsIdentity)
        
        // User Identity:
        let identity = try tlsIdentity(true)
        config = URLEndpointListenerConfiguration.init(database: self.oDB)
        config.tlsIdentity = identity
        listener = URLEndpointListener.init(config: config)
        XCTAssertNil(listener.tlsIdentity)
        
        try listener.start()
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssert(identity === listener.tlsIdentity!)
        try stopListener(listener: listener)
        XCTAssertNil(listener.tlsIdentity)
        try cleanupTLSIdentity(true) // cleanup the server tlsIdentity
    }
    
    func testNonTLSNullListenerAuthenticator() throws {
        let listener = try listen(tls: false)
        
        // Replicator - No Authenticator:
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false)
        
        // Replicator - Basic Authenticator:
        let auth = BasicAuthenticator.init(username: "daniel", password: "123")
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: auth)
        
        // Replicator - Client Cert Authenticator
        let certAuth = ClientCertificateAuthenticator(identity: try tlsIdentity(false)!)
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: certAuth)
        try cleanupTLSIdentity(false) // cleanup client cert auth identity
        
        // Cleanup:
        try stopListen()
    }
       
    func testNonTLSPasswordListenerAuthenticator() throws {
        // Listener:
        let listenerAuth = ListenerPasswordAuthenticator.init {
            (username, password) -> Bool in
            return (username as NSString).isEqual(to: "daniel") &&
                (password as NSString).isEqual(to: "123")
        }
        let listener = try listen(tls: false, auth: listenerAuth)
        
        // Replicator - No Authenticator:
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: nil, expectedError: CBLErrorHTTPAuthRequired)
        
        // Replicator - Wrong Username:
        var auth = BasicAuthenticator.init(username: "daneil", password: "123")
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: auth, expectedError: CBLErrorHTTPAuthRequired)
        
        // Replicator - Wrong Password:
        auth = BasicAuthenticator.init(username: "daniel", password: "456")
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: auth, expectedError: CBLErrorHTTPAuthRequired)
        
        // Replicator - Client Cert Authenticator
        let certAuth = ClientCertificateAuthenticator(identity: try tlsIdentity(false)!)
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: certAuth, expectedError: CBLErrorHTTPAuthRequired)
        try cleanupTLSIdentity(false) // cleanup client cert auth identity
        
        // Replicator - Success:
        auth = BasicAuthenticator.init(username: "daniel", password: "123")
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: auth)
        
        // Cleanup:
        try stopListen()
    }
    
    @available(macOS 10.12, iOS 10.3, *)
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
        let listener = try listen(tls: true, auth: listenerAuth)
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Replicator:
        let auth = ClientCertificateAuthenticator(identity: try tlsIdentity(false)!)
        let serverCert = listener.tlsIdentity!.certs[0]
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: auth, serverCert: serverCert)
        
        // Cleanup:
        try cleanupTLSIdentity(false)
        try stopListen()
    }
    
    @available(macOS 10.12, iOS 10.3, *)
    func testClientCertAuthWithCallbackError() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Listener:
        let listenerAuth = ListenerCertificateAuthenticator.init { (certs) -> Bool in
            XCTAssertEqual(certs.count, 1)
            return false
        }
        let listener = try listen(tls: true, auth: listenerAuth)
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Replicator:
        let auth = ClientCertificateAuthenticator(identity: try tlsIdentity(false)!)
        let serverCert = listener.tlsIdentity!.certs[0]
        self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false, auth: auth, serverCert: serverCert, expectedError: CBLErrorTLSClientCertRejected)
        
        // Cleanup:
        try cleanupTLSIdentity(false)
        try stopListen()
    }
    
    func testClientCertAuthWithRootCerts() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Root Cert:
        let rootCertData = try dataFromResource(name: "identity/client-ca", ofType: "der")
        let rootCert = SecCertificateCreateWithData(kCFAllocatorDefault, rootCertData as CFData)!
        
        // Listener:
        let listenerAuth = ListenerCertificateAuthenticator.init(rootCerts: [rootCert])
        let listener = try listen(tls: true, auth: listenerAuth)
        
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
        try stopListen()
    }
    
    func testClientCertAuthWithRootCertsError() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Root Cert:
        let rootCertData = try dataFromResource(name: "identity/client-ca", ofType: "der")
        let rootCert = SecCertificateCreateWithData(kCFAllocatorDefault, rootCertData as CFData)!
        
        // Listener:
        let listenerAuth = ListenerCertificateAuthenticator.init(rootCerts: [rootCert])
        let listener = try listen(tls: true, auth: listenerAuth)
        
        // Replicator:
        let auth = ClientCertificateAuthenticator.init(identity: try tlsIdentity(false)!)
        let serverCert = listener.tlsIdentity!.certs[0]
        
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     auth: auth, serverCert: serverCert, expectedError: CBLErrorTLSClientCertRejected)
        }
        
        // Cleanup:
        try cleanupTLSIdentity(false)
        try stopListen()
    }
    
    func testConnectionStatus() throws {
        if !self.keyChainAccessAllowed { return }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.port = wsPort
        config.disableTLS = true
        self.listener = URLEndpointListener(config: config)
        XCTAssertEqual(self.listener!.status.connectionCount, 0)
        XCTAssertEqual(self.listener!.status.activeConnectionCount, 0)
        
        // Start:
        try self.listener!.start()
        XCTAssertEqual(self.listener!.status.connectionCount, 0)
        XCTAssertEqual(self.listener!.status.activeConnectionCount, 0)
        
        try generateDocument(withID: "doc-1")
        let rConfig = self.config(target: self.listener!.localURLEndpoint,
                                 type: .pushAndPull, continuous: false, auth: nil,
                                 acceptSelfSignedOnly: false, serverCert: nil)
        var maxConnectionCount: UInt64 = 0, maxActiveCount:UInt64 = 0
        run(config: rConfig, reset: false, expectedError: nil) { (replicator) in
            replicator.addChangeListener { (change) in
                maxConnectionCount = max(self.listener!.status.connectionCount, maxConnectionCount)
                maxActiveCount = max(self.listener!.status.activeConnectionCount, maxActiveCount)
            }
        }
        XCTAssertEqual(maxConnectionCount, 1)
        XCTAssertEqual(maxActiveCount, 1)
        XCTAssertEqual(self.oDB.count, 1)

        try stopListen()
        XCTAssertEqual(self.listener!.status.connectionCount, 0)
        XCTAssertEqual(self.listener!.status.activeConnectionCount, 0)
    }
    
    func testMultipleListenersOnSameDatabase() throws {
        if !self.keyChainAccessAllowed { return }
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
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
        XCTAssertEqual(self.oDB.count, 1)
    }
    
    func testReplicatorAndListenerOnSameDatabase() throws {
        if !self.keyChainAccessAllowed { return }
        
        let exp1 = expectation(description: "replicator#1 stop")
        let exp2 = expectation(description: "replicator#2 stop")
        
        // listener
        let doc = createDocument()
        try self.oDB.saveDocument(doc)
        try listen()
        
        // Replicator#1 (otherDB -> DB#1)
        let doc1 = createDocument()
        try self.db.saveDocument(doc1)
        let target = DatabaseEndpoint(database: self.db)
        let repl1 = replicator(db: self.oDB, continuous: true, target: target, serverCert: nil)
        
        // Replicator#2 (DB#2 -> Listener(otherDB))
        try deleteDB(name: "db2")
        let db2 = try openDB(name: "db2")
        let doc2 = createDocument()
        try db2.saveDocument(doc2)
        let repl2 = replicator(db: db2,
                               continuous: true,
                               target: self.listener!.localURLEndpoint,
                               serverCert: self.listener!.tlsIdentity!.certs[0])
        
        let changeListener = { (change: ReplicatorChange) in
            if change.status.activity == .idle &&
                change.status.progress.completed == change.status.progress.total {
                if self.oDB.count == 3 && self.db.count == 3 && db2.count == 3 {
                    change.replicator.stop()
                }
            }
            
            if change.status.activity == .stopped {
                if change.replicator.config.database.name == "db2" {
                    exp2.fulfill()
                } else {
                    exp1.fulfill()
                }
            }
            
        }
        let token1 = repl1.addChangeListener(changeListener)
        let token2 = repl2.addChangeListener(changeListener)
        
        repl1.start()
        repl2.start()
        wait(for: [exp1, exp2], timeout: 5.0)
        
        XCTAssertEqual(self.oDB.count, 3)
        XCTAssertEqual(self.db.count, 3)
        XCTAssertEqual(db2.count, 3)
        
        repl1.removeChangeListener(withToken: token1)
        repl2.removeChangeListener(withToken: token2)
        
        try db2.close()
        try stopListen()
    }
    
    func testCloseWithActiveListener() throws {
        if !self.keyChainAccessAllowed { return }
        
        try listen()
        
        // Close database should also stop the listener:
        try self.oDB.close()
        
        XCTAssertNil(self.listener!.port)
        XCTAssertNil(self.listener!.urls)
        
        try stopListen()
    }
    
    func testEmptyNetworkInterface() throws {
        if !self.keyChainAccessAllowed { return }
        
        try listen()
        let urls = self.listener!.urls!
        
        /// Link local addresses cannot be assigned via network interface because they don't map to any given interface.
        let notLinkLocal: [URL] = urls.filter { !$0.host!.contains("fe80::") && !$0.host!.contains(".local")}
        
        for (i, url) in notLinkLocal.enumerated() {
            // separate db instance!
            let db = try Database(name: "db-\(i)")
            let doc = createDocument()
            doc.setString(url.absoluteString, forKey: "url")
            try db.saveDocument(doc)
            
            // separate replicator instance
            let target = URLEndpoint(url: url)
            let rConfig = ReplicatorConfiguration(database: db, target: target)
            rConfig.pinnedServerCertificate = self.listener?.tlsIdentity!.certs[0]
            run(config: rConfig, expectedError: nil)
            
            // remove the db
            try db.delete()
        }
        
        XCTAssertEqual(self.oDB.count, UInt64(notLinkLocal.count))
        
        let q = QueryBuilder.select([SelectResult.all()]).from(DataSource.database(self.oDB))
        let rs = try q.execute()
        var result = [URL]()
        for res in rs.allResults() {
            let dict = res.dictionary(at: 0)
            result.append(URL(string: dict!.string(forKey: "url")!)!)
        }
        
        XCTAssertEqual(result, notLinkLocal)
        try stopListen()
    }
    
    func testMultipleReplicatorsToListener() throws {
        if !self.keyChainAccessAllowed { return }
        
        try listen()
        
        let doc = createDocument()
        doc.setString("Tiger", forKey: "species")
        try self.oDB.saveDocument(doc)
        
        try validateMultipleReplicationsTo()
        
        try stopListen()
    }
    
    func testReadOnlyListener() throws {
        if !self.keyChainAccessAllowed { return }
        
        let doc1 = createDocument()
        try self.db.saveDocument(doc1)
        
        let config = URLEndpointListenerConfiguration(database: self.oDB)
        config.readOnly = true
        try listen(config: config)
        
        self.run(target: self.listener!.localURLEndpoint, type: .pushAndPull, continuous: false,
                 auth: nil, serverCert: self.listener!.tlsIdentity!.certs[0],
                 expectedError: CBLErrorHTTPForbidden)
    }
    
    func testReplicatorServerCertificate() throws {
        if !self.keyChainAccessAllowed { return }
        
        let x1 = expectation(description: "idle")
        let x2 = expectation(description: "stopped")
        
        let listener = try listen()
        
        let serverCert = listener.tlsIdentity!.certs[0]
        let repl = replicator(db: self.oDB,
                              continuous: true,
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
        
        wait(for: [x1], timeout: 5.0)
        var receivedServerCert = repl.serverCertificate
        XCTAssertNotNil(receivedServerCert)
        checkEqual(cert: serverCert, andCert: receivedServerCert!)
        
        repl.stop()
        
        wait(for: [x2], timeout: 5.0)
        receivedServerCert = repl.serverCertificate
        XCTAssertNotNil(receivedServerCert)
        checkEqual(cert: serverCert, andCert: receivedServerCert!)
        
        try stopListen()
    }
    
    func testReplicatorServerCertificateWithError() throws {
        if !self.keyChainAccessAllowed { return }
        
        var x1 = expectation(description: "stopped")
        
        let listener = try listen()
        
        var serverCert = listener.tlsIdentity!.certs[0]
        var repl = replicator(db: self.oDB,
                              continuous: true,
                              target: listener.localURLEndpoint,
                              serverCert: nil)
        repl.addChangeListener { (change) in
            let activity = change.status.activity
            if activity == .stopped && change.status.error != nil {
                x1.fulfill()
            }
        }
        XCTAssertNil(repl.serverCertificate)
        
        repl.start()
        
        wait(for: [x1], timeout: 5.0)
        var receivedServerCert = repl.serverCertificate
        XCTAssertNotNil(receivedServerCert)
        checkEqual(cert: serverCert, andCert: receivedServerCert!)
        
        // Use the receivedServerCert to pin:
        x1 = expectation(description: "idle")
        let x2 = expectation(description: "stopped")
        serverCert = receivedServerCert!
        repl = replicator(db: self.oDB,
                          continuous: true,
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
        
        wait(for: [x1], timeout: 5.0)
        receivedServerCert = repl.serverCertificate
        XCTAssertNotNil(receivedServerCert)
        checkEqual(cert: serverCert, andCert: receivedServerCert!)
        
        repl.stop()
        
        wait(for: [x2], timeout: 5.0)
        receivedServerCert = repl.serverCertificate
        XCTAssertNotNil(receivedServerCert)
        checkEqual(cert: serverCert, andCert: receivedServerCert!)
        
        try stopListen()
    }
    
    func testReplicatorServerCertificateWithTLSDisabled() throws {
        let x1 = expectation(description: "idle")
        let x2 = expectation(description: "stopped")
        
        let listener = try listen(tls: false)
        let repl = replicator(db: self.oDB,
                              continuous: true,
                              target: listener.localURLEndpoint,
                              serverCert: nil)
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
        
        wait(for: [x1], timeout: 5.0)
        XCTAssertNil(repl.serverCertificate)
        
        repl.stop()
        
        wait(for: [x2], timeout: 5.0)
        XCTAssertNil(repl.serverCertificate)
        
        try stopListen()
    }
    
    func testAcceptOnlySelfSignedServerCertificate() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Listener:
        let listener = try listen(tls: true)
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Replicator - TLS Error:
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     acceptSelfSignedOnly: false, serverCert: nil, expectedError: CBLErrorTLSCertUnknownRoot)
        }
        
        // Replicator - Success:
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     acceptSelfSignedOnly: true, serverCert: nil)
        }
        
        // Cleanup
        try stopListen()
    }
    
    func testPinnedServerCertificate() throws {
        if !self.keyChainAccessAllowed { return }
        
        // Listener:
        let listener = try listen(tls: true)
        XCTAssertNotNil(listener.tlsIdentity)
        XCTAssertEqual(listener.tlsIdentity!.certs.count, 1)
        
        // Replicator - TLS Error:
        self.ignoreException {
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     acceptSelfSignedOnly: false, serverCert: nil, expectedError: CBLErrorTLSCertUnknownRoot)
        }
        
        // Replicator - Success:
        self.ignoreException {
            let serverCert = listener.tlsIdentity!.certs[0]
            self.run(target: listener.localURLEndpoint, type: .pushAndPull, continuous: false,
                     acceptSelfSignedOnly: false, serverCert: serverCert)
        }
        
        // Cleanup
        try stopListen()
    }
    
    func testListenerWithImportIdentity() throws {
        if !self.keyChainAccessAllowed { return }
        
        let data = try dataFromResource(name: "identity/certs", ofType: "p12")
        var identity: TLSIdentity!
        self.ignoreException {
            identity = try TLSIdentity.importIdentity(withData: data,
                                                      password: "123",
                                                      label: self.serverCertLabel)
        }
        
        let config = URLEndpointListenerConfiguration.init(database: self.oDB)
        config.tlsIdentity = identity
        
        self.ignoreException {
            try self.listen(config: config)
        }
        
        XCTAssertNotNil(listener!.tlsIdentity)
        XCTAssert(identity === listener!.tlsIdentity!)
        
        try generateDocument(withID: "doc-1")
        XCTAssertEqual(self.oDB.count, 0)
        self.run(target: listener!.localURLEndpoint,
                 type: .pushAndPull,
                 continuous: false,
                 auth: nil,
                 serverCert: listener!.tlsIdentity!.certs[0])
        XCTAssertEqual(self.oDB.count, 1)
        
        try stopListener(listener: listener!)
        XCTAssertNil(listener!.tlsIdentity)
    }
    
    func testStopListener() throws {
        let x1 = expectation(description: "idle")
        let x2 = expectation(description: "stopped")
        
        // Listen:
        let listener = try listen(tls: false)
        
        // Start replicator:
        let target = listener.localURLEndpoint
        let repl = replicator(db: self.oDB,
                              continuous: true,
                              target: target,
                              serverCert: nil)
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
        wait(for: [x1], timeout: 5.0)
        
        // Stop listen:
        try stopListen()
        
        // Wait for the replicator to be stopped:
        wait(for: [x2], timeout: 5.0)
        
        // Check error:
        XCTAssertEqual((repl.status.error! as NSError).code, CBLErrorWebSocketGoingAway)
        
        // Check to ensure that the replicator is not accessible:
        run(target: target, type: .pushAndPull, continuous: false, auth: nil, serverCert: nil,
            expectedError: Int(ECONNREFUSED))
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
}

@available(macOS 10.12, iOS 10.0, *)
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
